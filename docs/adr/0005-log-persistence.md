# ADR 0005: Persist log events with a domain that upserts on a log key, retries three times, and never logs back into itself

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** Chad Countryman

## Context

`Log_Event__e` events (ADR 0002) are retained for 72 hours and can't be queried with SOQL, so a log that people can search, report on and keep needs a custom object. The subscriber that writes it has some constraints of its own:

1. It runs as the Automated Process user, in its own transaction, for entries logged by any user. The logging user's object and field access doesn't apply.
2. The event bus can redeliver a batch, after a `RetryableException` or after a subscriber failure. A redelivered event must not create a second row.
3. The subscriber can't log through `ILogger`. `ILogger` is bound to `PlatformEventLogger`, so a log line written while persisting would publish another event and trigger the subscriber again. A's `TriggerDispatcher` logs its depth-guard warning through `ILogger` too.
4. Logs can hold sensitive data, for example exception messages that quote field values. Not every user should read them.

## Options

### Persistence path (D9, D10)

1. **A `LogEvents` domain dispatched by A's `TriggerDispatcher`, committing through A's Unit of Work with `SystemDml` and `registerUpsert` on an external Id** (chosen). For: it uses A's layers as a consumer would, so `Trigger_Setting__mdt` can switch persistence off without a deploy, and tests stub the Unit of Work. Against: it needed A 1.1.0 to add `IDml.dmlUpsert` and `IUnitOfWork.registerUpsert`.
2. **A B-owned `ILogStore` calling `Database.upsert` directly.** For: no change to A. Against: B would bypass the Unit of Work it exists to demonstrate, and every future consumer that needs upsert would do the same.
3. **Insert and ignore duplicate errors.** For: no upsert needed. Against: `IDml` is all-or-none, so one duplicate fails the whole batch.
4. **User-mode DML.** Rejected: the Automated Process user has no access to `Log__c`, and the rows belong to every logging user, not to the subscriber.

### Retries (D11)

1. **Throw `EventBus.RetryableException` while the batch has been retried fewer than 3 times, then write the batch to the debug log and move on** (chosen). For: a brief lock or storage blip heals itself, and a poison batch can't stop the stream for good. Against: a batch that still fails after the last retry survives only in the debug log.
2. **No retries.** Against: any failure loses the whole batch at once.
3. **Per-event checkpoints (`setResumeCheckpoint`).** Against: they help when part of a batch succeeds, but `IDml` is all-or-none, so it never does.

### Recursion (D12)

1. **A `LogBuffer` suppression flag around persistence** (chosen). For: every `ILogger` call in the subscriber goes to the debug log, whoever makes it. Against: one more piece of static state in the buffer.
2. **Have the subscriber use `DebugLogger` and nothing else** (D9 alone). Against: A's dispatcher and any host code still resolve `ILogger` through `Application.Service`, which returns `PlatformEventLogger`.

### Visibility (D13)

1. **OWD Private, plus a `Log_Viewer` permission set with Read and View All on `Log__c` and read on every field** (chosen). Against: an admin has to assign it.
2. **Public Read Only.** Against: every internal user could read exception text.

## Decision

Option 1 in each group.

## Rules

- **Key.** `Log_Key__c` is Text(80), External Id, Unique and case-sensitive, set to `Request_Id__c-Sequence__c`. If either part is missing it is `uuid-<EventUuid>`, and if the event has neither, it's null and the row is inserted. Request Ids are case-sensitive, so the unique index is too.
- **A 1.1.0 rules.** `registerUpsert` takes one key field per type per Unit of Work, and the field must be `idLookup`. Each trigger batch gets a new Unit of Work that registers only `Log_Key__c`. `LogPersistenceIntegrationTest` pins the describe.
- **One row per key per batch.** A repeated key in one upsert list fails the whole batch, so the domain keeps the last event for each key.
- **Logged by.** `Logged_By__c` is the event's `CreatedById`, the user whose transaction logged it. `CreatedById` on `Log__c` is the subscriber.
- **System mode.** This is the one place B writes in system mode. It is the documented exception to the repository's user-mode rule, for the reason in Context point 1.
- **Retries.** `LogEventsDomain.MAX_RETRIES = 3`, read from `EventBus.TriggerContext.currentContext().retries`. When the batch is given up, the domain writes one `ERROR` line with the cause, then one `WARN` line per entry with its key, level and message, all through A's `DebugLogger`.
- **Suppression.** `onAfterInsert` calls `LogBuffer.suppress()` and calls `resume()` in `finally`. While suppressed, `add()` and `flush()` drain to the debug log with the reason `publishing suppressed in the log subscriber`.
- **Kill switch.** An inactive `Trigger_Setting__mdt` row for `Log_Event__e` stops persistence. Events published while it is off are not persisted later.

## Consequences

- People who read logs need `Log_Viewer`, and people whose code logs need `Log_Event_Publisher` (ADR 0003). The README documents both.
- The R3 behaviour is now a test as well as a probe: `LogPersistenceIntegrationTest.callerRollsBack_entryStillPersists` rolls the caller back to a savepoint and still finds the row after delivery.
- `Test.getEventBus().deliver()` redelivers after a `RetryableException`, so the retry path is tested with the real `EventBus.TriggerContext`: four deliveries, four commits, one give-up.
- Storage is the binding limit (R4). Retention deletes old rows (ADR 0007).
