# Handoff: apex-platform-logging

Last updated: 2026-11-12 · Phase: roadmap step 2, PR #2 `feat/event-logger`

## Done

- Repository scaffolded by hand from the `sf-repo-scaffold` template at `claude-code-salesforce-skills` `main` (back-port PR #8), plus the template `LICENSE` from E PR #9.
- Depends on `apex-core-lib@1.0.0-1` (`04tak000000u0zpAAA`). `sfdx-project.json` adds `definitionFile` and `versionDescription`, which a package version build needs and the template lacks (an E final-pass item).
- ADR 0001: B is its own unlocked package with no namespace.
- Local dev org `apl-dev` (7 days, expires 2026-11-19): A installed, empty deploy OK.

- PR #1 `chore/scaffold` merged; CI secrets set; `main` green.
- PR #2 `feat/event-logger`: `Log_Event__e` (Publish Immediately, high volume), `Logging_Setting__mdt` + `Default` row, `DI_Binding.Platform_Event_Logger` (ILogger → `PlatformEventLogger`), the `Log_Event_Publisher` permission set, `PlatformEventLogger`, `LogBuffer`, `LogEntry`, `LogContext`, `LoggingSettings`, `ILogEventPublisher` + `EventBusPublisher`, and ADRs 0002–0004. 40 tests and 100% coverage on B's classes in `apl-dev`.

## Next

1. PR #3 `feat/persistence`: `Log__c` and the `LogEvents` domain through A's `TriggerDispatcher` (D9). Include an end-to-end test (`Test.getEventBus().deliver()`), and prove that delivery survives a rollback in a test as well as in the R3 probe.
2. PR #4 `feat/slack-alerts`: probe R2 first.
3. PR #5 `feat/retention`, PR #6 `docs/example-and-readme`, then the release (tag only with approval). The README must document assigning `Log_Event_Publisher`.

## Approved design (2026-11-12, D1–D9)

| #   | Decision        | Choice                                                                                                                                                               | Rejected                                                           |
| --- | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| D1  | Event schema    | One `Log_Event__e` per entry with typed fields                                                                                                                       | One event per flush with a JSON array; a hybrid                    |
| D2  | Publish         | Publish Immediately; log messages describe attempts, not outcomes                                                                                                    | Publish After Commit; two event types                              |
| D3  | Flush           | Static transaction buffer; flush on `flush()`, on `error()`, at the buffer size (default 50) and before the publish limit runs out; fail safe to `System.debug`      | Explicit flush only; publish per call                              |
| D4  | Packaging       | Own unlocked package, no namespace (ADR 0001)                                                                                                                        | Source-only; a module inside A                                     |
| D5  | Activation      | `ILogger` binding active, `IAlertSink` Slack binding inactive until the token is set                                                                                 | Both active; both inactive                                         |
| D6  | Slack transport | Web API `chat.postMessage`, bot token in an External Credential (Custom protocol, header formula), channel in CMDT                                                   | Incoming webhook (the secret is in the URL)                        |
| D7  | Callout timing  | `SlackAlertSink.send` enqueues `SlackAlertJob` (Queueable + Finalizer); one message per batch, 50-block cap, one 429 re-enqueue                                      | Synchronous callout in `send`                                      |
| D8  | Config          | `Logging_Setting__mdt` `Default` row                                                                                                                                 | Hierarchy custom setting (recorded as the extension point)         |
| D9  | Persistence     | `LogEvents` domain via A's `TriggerDispatcher`; `SystemDml` upsert on external Id `Request_Id + Sequence`; subscriber logs via `DebugLogger`; static recursion guard | User-mode DML; logging via `Application.Service` in the subscriber |

## Risks to probe

- **R1:** B packages `DI_Binding__mdt` records of A's type. The deploy shows it; the package build proves it at release.
- **R2:** the Queueable enqueued from the Platform Event trigger runs as the Automated Process user, which needs External Credential principal access. Probe a permission set assignment to that user. Fallback: `PlatformEventSubscriberConfig` with a named user, documented as setup.
- **R3 (proven 2026-11-12):** a Publish Immediately event is delivered after an uncaught exception and after a `LimitException`. Publish After Commit events are lost on rollback. Evidence is in ADR 0003.
- **R4 (measured 2026-11-12):** the scratch org allows 250,000 high-volume publishes per hour and has 500 MB of data storage, so storage is the binding limit (retention, PR #5).
- **R5 (found 2026-11-12, resolved):** `EventBus.publish` checks the running user's Create permission on `Log_Event__e`, even from Apex and from `without sharing` code. Create requires Read. Resolved with the packaged `Log_Event_Publisher` permission set (ADR 0003), pinned by two integration tests.

## Notes for the next session

- `ServiceFactory.newInstance` returns a new instance on every call (no caching), so the logger's buffer must be static, per transaction.
- `TriggerDispatcher.run()` works for a Platform Event trigger. Bind the `LogEvents` domain with a `DI_Binding__mdt` row whose Kind is Domain. A's `Trigger_Setting__mdt` then gives persistence a kill switch.
- `sf org display` is blocked in auto mode, so API 68.0 came from A's verified value.
- An empty `force-app` deploys with "No changes to deploy" and exit 0.
