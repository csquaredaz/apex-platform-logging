# ADR 0006: Send ERROR log entries to Slack as one Block Kit message per batch, from a Queueable that runs as the subscriber

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** Chad Countryman

## Context

A's `IAlertSink` port (`send(List<Alert>)`) is for things a human should act on. Its default, `NoOpAlertSink`, discards them. This repo provides a Slack adapter. The port and the platform constrain it:

1. **`send` must not throw**, and it takes a list, so an adapter can batch. `Alert` is immutable and has only `severity` (`INFO`, `WARNING`, `CRITICAL`), a required `title`, `detail` and `source`.
2. **Callouts aren't allowed everywhere `send` can run.** They are blocked in a Platform Event trigger and after uncommitted DML. A Queueable with `Database.AllowsCallouts` can call out.
3. **`System.enqueueJob` is transactional.** If the caller's transaction rolls back, the job is never enqueued, and a failing transaction is exactly when an ERROR is logged.
4. **A's `CalloutClient` doesn't retry a 429** (an immediate retry hits the same limit), and it never retries a POST without an idempotency key. Slack ignores idempotency keys.
5. **Slack's limits:** at most 50 blocks per message, 3,000 characters per `section` text, and a 429 with `Retry-After` when rate limited. Most errors (`not_authed`, `channel_not_found`) come back as HTTP 200 with `{"ok": false, "error": "<code>"}`.
6. **Free only.** No real Slack workspace, token or webhook URL is used anywhere. Tests use `HttpCalloutMock`.

### R2 probe (`apl-dev`, 2026-11-12)

Before this design, a throwaway probe tested who runs the Queueable and whether that user can be given External Credential access. The probe added a second trigger on `Log_Event__e` that enqueued a Queueable with a Finalizer. The Queueable called a Custom-protocol External Credential with an `Authorization` header formula. The Named Credential pointed at `https://r2-probe.invalid` and no token was set, so nothing left Salesforce. The probe metadata and rows were removed afterwards.

| Probe                                                                                                                 | Result                                                                                                      |
| --------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Running user of the subscriber, of the Queueable it enqueues, and of that job's Finalizer                             | All three run as the **Automated Process** user                                                             |
| Callout with no principal access                                                                                      | Catchable `System.CalloutException`: "We couldn't access the credential(s)…"                                |
| A permission set with `externalCredentialPrincipalAccesses`, assigned to the Automated Process user by an Apex insert | Accepted. The callout then passed the credential check and reached the transport (HTTP 503 from `.invalid`) |
| Header formula with no token value set                                                                                | Evaluates anyway and the callout is sent. A missing token shows up as Slack's `not_authed`                  |
| `HttpCalloutMock` on `callout:` as a Minimum Access `runAs` user without principal access                             | The mock answers. Tests need no credential setup                                                            |
| Custom protocol plus header-formula metadata                                                                          | Deploys                                                                                                     |

Not proven:

- Assigning the permission set to the Automated Process user from the Setup UI. The probe used Apex, and the setup steps below do the same.
- Whether Named and External Credentials package in a no-namespace unlocked package. That is risk R6, proven by the release package build, like R1.

The fallback, a `PlatformEventSubscriberConfig` that runs the subscriber as a named integration user, isn't needed. It stays a documented option for orgs that want one: give that user the permission sets below instead.

## Options

### Transport and secret (D6)

1. **Web API `chat.postMessage` through a Named Credential, with the bot token in an External Credential** (chosen). It uses the Custom protocol, an `Authorization: Bearer {!$Credential.Slack.Bot_Token}` header formula, and the channel in `Logging_Setting__mdt`. For: the token never appears in metadata, source or logs, and principal access is a permission set. Against: an admin sets the token in Setup and assigns the permission set.
2. **Incoming webhook.** Rejected: the secret is the URL, so it would sit in a Named Credential URL or in configuration, and one webhook is fixed to one channel.

### Callout timing (D7)

1. **`SlackAlertSink.send` enqueues one `SlackAlertJob` (Queueable with a Finalizer); one message per `send`; the 50-block cap; one delayed re-enqueue on a 429** (chosen). For: it works from triggers and the subscriber, and a burst of alerts costs one message. Against: alerts are asynchronous, and one Queueable is used per `send`.
2. **A synchronous callout in `send`.** Rejected: it fails in the subscriber and after DML (Context point 2).

### Where alerts come from (D14)

1. **The `Log_Event__e` subscriber** (chosen). Once `LogEventsDomain` has persisted a batch, or given it up, it maps the batch's `ERROR` rows to `CRITICAL` alerts and makes one `send` call. For: it survives the caller's rollback, because the event was published immediately (ADR 0003). It runs as one known user (R2). A batch that throws `RetryableException` rolls back its enqueue, so a retried batch alerts once. Against: alerts depend on persistence being on (`Trigger_Setting__mdt`). Consumers can still call `IAlertSink` directly.
2. **Explicit calls only.** B ships only the adapter. Against: nothing links logs to alerts, and every calling user needs the permission set.
3. **In the logger: `PlatformEventLogger.error()` calls the sink.** Rejected: the enqueue is lost whenever the caller rolls back (Context point 3), and every logging user would need the permission set.

### Level and loop guard (D15)

1. **Only `ERROR` raises alerts, and that is fixed; every alerting failure is logged at `WARN`** (chosen). This covers the sink, the job and the finalizer. A failed delivery is published, persisted and visible in `Log__c`, but it can't raise another alert, so the loop can't start. Tests assert that no outcome logs at `ERROR`.
2. **A configurable alert level, with `LogBuffer` suppressed inside the job.** Against: delivery failures would reach only the debug log.
3. **A configurable level, with the subscriber skipping entries logged by the job.** Against: it needs a source field on `Log_Event__e`, which changes ADR 0002's schema.

### Finalizer (D16)

1. **On `UNHANDLED_EXCEPTION`, log one `WARN` with the cause and one `WARN` per lost alert title, and don't retry** (chosen). For: a failure that escapes the job's own handling is likely to repeat, and it could come after a successful post. The source entries are in `Log__c` anyway.
2. **Retry once, then log.** Against: it could post twice, and it shares the single-retry budget with the 429 path.

### Activation (D5)

The `DI_Binding.Slack_Alert_Sink` row ships **inactive**, so `IAlertSink` resolves to A's `NoOpAlertSink` until an admin finishes setup. The subscriber always calls the sink, and the binding decides whether anything is sent.

## Decision

Option 1 in each group.

## Rules

- **Message.** `SlackMessageBuilder` builds one `header` ("N alerts"), then a `section` (severity marker, bold severity, title, then the detail) and a `context` (source) for each alert. That is 2 blocks per alert, so 24 alerts fit in 49 blocks. From the 25th alert on, the rest are counted in one last `context` block, which makes exactly 50. Text is escaped (`&`, `<`, `>`), so a log message can't mention `@channel` or inject a link. Text is cut to 3,000 characters. The `text` fallback is the first title plus a count. Link and media unfurling are off.
- **Alert mapping.** The title is the first line of the message (cut at 150), else the exception type, else "ERROR log entry". The detail is `Exception_Type__c: Exception_Message__c`. The source is `Quiddity__c | Log_Key__c <key>`, which finds the row in `Log__c`.
- **Sink.** It drops null entries. With no channel, no Queueable left, or a failed enqueue, it logs a WARN and drops the alerts. It never throws.
- **Job outcomes.**

  | Response                                                | Action                                                                                                |
  | ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
  | 200 with `ok: true`                                     | Done                                                                                                  |
  | 200 with `ok: false`, or an unreadable body             | WARN with the error code                                                                              |
  | 429, first attempt                                      | Re-enqueue once (`MAX_ATTEMPTS = 2`), delayed by `Retry-After` rounded up to minutes, clamped to 1–10 |
  | 429, second attempt                                     | WARN; the batch is dropped                                                                            |
  | Another non-2xx status                                  | WARN; no retry (a resent POST could post twice)                                                       |
  | `CalloutClientException` (credential, timeout, network) | WARN, with a hint to assign `Slack_Alert_Sender` to the running user type                             |

- **Failure lines start with `Slack alert delivery failed:`** (`SlackAlertJob.FAILURE_PREFIX`), so they're easy to find in `Log__c`.
- **Test seam.** `AlertJobEnqueuer` wraps `System.enqueueJob`, so unit tests record the 429 re-enqueue instead of chaining a Queueable, which tests can't do.

## Setup (before activating the binding)

1. Create a Slack app with the `chat:write` bot scope, install it, and invite the bot to the channel.
2. In Setup > Named Credentials > External Credentials > **Slack** > Principals > **Slack_Bot**, add the authentication parameter `Bot_Token` with the `xoxb-` token. It is stored encrypted and is never in source.
3. Set `Logging_Setting__mdt.Default.Slack_Channel__c` to the channel ID.
4. Assign **`Slack_Alert_Sender`** and **`Log_Event_Publisher`** to the Automated Process user, so the job can call out and its WARN lines are published. Also assign them to any user whose own code calls `IAlertSink`. The R2 probe assigned it with Apex; the Setup UI route wasn't tested. For example: `insert new PermissionSetAssignment(AssigneeId = <Automated Process user Id>, PermissionSetId = <Slack_Alert_Sender Id>);`.
5. Activate `DI_Binding.Slack_Alert_Sink`.

## Consequences

- **Rollback:** deactivate `DI_Binding.Slack_Alert_Sink`. Alerts go back to `NoOpAlertSink`, with no deploy.
- A burst of failing batches means one message per batch. A 429 is retried once, then dropped with a WARN, and the entries are still in `Log__c`. Deliberately omitted: cross-transaction throttling or de-duplication of alerts. That needs shared state (a DML or Platform Cache per alert), like the circuit breaker A left out (A's ADR 0007).
- `LoggingSettings` gains `slackChannel`. The field is subscriber-controlled, so admins can change the channel in production.
- Slack can only be tested with mocks here (free only). The first real post is a manual check after setup.
- R6: the release package build proves that the Named and External Credentials package.
