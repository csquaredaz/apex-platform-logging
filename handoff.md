# Handoff: apex-platform-logging

Last updated: 2026-11-12 · Phase: roadmap step 2, PR #2 merged; PR #3 `feat/persistence` blocked on apex-core-lib 1.1.0

## Done

- Repository scaffolded by hand from the `sf-repo-scaffold` template at `claude-code-salesforce-skills` `main` (back-port PR #8), plus the template `LICENSE` from E PR #9.
- Depends on `apex-core-lib@1.0.0-1` (`04tak000000u0zpAAA`). `sfdx-project.json` adds `definitionFile` and `versionDescription`, which a package version build needs and the template lacks (an E final-pass item).
- ADR 0001: B is its own unlocked package with no namespace.
- Local dev org `apl-dev` (7 days, expires 2026-11-19): A installed, empty deploy OK.

- PR #1 `chore/scaffold` merged; CI secrets set; `main` green.
- PR #2 `feat/event-logger` (merged; the `main` run reused the PR result): `Log_Event__e` (Publish Immediately, high volume), `Logging_Setting__mdt` + `Default` row, `DI_Binding.Platform_Event_Logger` (ILogger → `PlatformEventLogger`), the `Log_Event_Publisher` permission set, `PlatformEventLogger`, `LogBuffer`, `LogEntry`, `LogContext`, `LoggingSettings`, `ILogEventPublisher` + `EventBusPublisher`, and ADRs 0002–0004. 40 tests and 100% coverage on B's classes in `apl-dev`.

## Next

1. **apex-core-lib 1.1.0 (separate thread, repo A):** add `dmlUpsert(List<SObject> records, SObjectField externalIdField)` to `IDml`, implemented by `SystemDml`, `UserModeDml` and `StripInaccessibleDml`. Add `registerUpsert(List<SObject> records, SObjectField externalIdField)` to `IUnitOfWork` and `UnitOfWork` (upserts run after inserts, in commit order). This is Chad's choice (D10). The release notes must say that hand-written `IDml` or `IUnitOfWork` implementers have to add the methods; Stub API mocks are unaffected. Tag `v1.1.0` only with approval; Chad promotes it.
2. **PR #3 `feat/persistence`** on `apex-core-lib@1.1.0-1` (bump `sfdx-project.json` and upgrade A in `apl-dev`). Plan:
   - `force-app/persistence/objects/Log__c`: AutoNumber `LOG-{000000}`, OWD Private. Fields: `Level__c`, `Message__c`, `Exception_Type__c`, `Exception_Message__c`, `Stack_Trace__c`, `Request_Id__c`, `Sequence__c`, `Quiddity__c`, `Logged_At__c`, `Logged_By__c` (Lookup User, from the event's `CreatedById`), and `Log_Key__c` (Text 80, External Id, Unique: `Request_Id-Sequence`).
   - `LogEventTrigger` (after insert) calls `TriggerDispatcher.run()`. `LogEventsDomain` + `Constructor`, bound by `DI_Binding.Log_Events_Domain` (Domain, `Log_Event__e`).
   - The domain maps events to `Log__c` and commits through a `UnitOfWork` with `SystemDml` and `registerUpsert(rows, Log__c.Log_Key__c)`.
   - **Retries (D11):** if the commit throws, throw `EventBus.RetryableException` while `retries < 3`, then write the batch to `DebugLogger` and move on. `IDml` is all-or-none, so a bad row fails its batch.
   - **Recursion (D12):** a `LogBuffer` suppression flag is set around persistence (cleared in `finally`). Any `ILogger` call in the subscriber transaction, including A's `TriggerDispatcher` warning, goes to the debug log and is never published.
   - **Visibility (D13):** OWD Private, plus a `Log_Viewer` permission set (Read, View All, field read).
   - Tests:
     - `LogEventsDomainTest` (stubbed UoW or `IDml`): mapping and key, 200 events in one commit, retry and give-up, suppression cleared on exception.
     - `LogPersistenceIntegrationTest` (`Test.getEventBus().deliver()`): log, flush and deliver makes a row; a redelivery leaves one row; a caller rollback still persists (R3 in a test); a Minimum Access publisher with `Log_Event_Publisher`; visibility with and without `Log_Viewer`.
     - `LogBufferTest`: a suppressed flush publishes nothing.
   - ADR 0005 (persistence: D9–D13).
3. PR #4 `feat/slack-alerts` (probe R2 first), PR #5 `feat/retention`, PR #6 `docs/example-and-readme`, then the release (tag only with approval). The README must document assigning `Log_Event_Publisher` and `Log_Viewer`.

## E final-pass items found here

- CI ran `RunLocalTests` and gated on org-wide coverage. With a dependency that has no namespace (A), that runs A's packaged tests too. A's `ApplicationTest.service_logger_defaultsToDebugLogger` fails by design once B rebinds `ILogger`. B's CI now runs only its own `*Test` classes and gates on the coverage of its own classes (`package-coverage.txt`, which the reuse job reads). Back-port this to E's `sf-repo-scaffold` template for C and F.
- When running tests in the dev org, use the same scope: `--class-names` with the repo's own tests.

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

### Decisions for PR #3 (2026-11-12)

| #   | Decision         | Choice                                                                                | Rejected                                                                                                |
| --- | ---------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| D10 | Upsert path      | Add `dmlUpsert` / `registerUpsert` to A's `IDml` / `IUnitOfWork`, released as A 1.1.0 | A B-owned `ILogStore` with direct `Database.upsert`; insert and ignore duplicates; extension interfaces |
| D11 | Subscriber retry | `EventBus.RetryableException` while retries < 3, then the debug log                   | No retries; per-event checkpoints                                                                       |
| D12 | Recursion        | `LogBuffer` suppression flag around persistence                                       | Relying on D9's `DebugLogger` alone (A's dispatcher logs through `ILogger`)                             |
| D13 | Visibility       | OWD Private + a `Log_Viewer` permission set (Read, View All)                          | Public Read Only                                                                                        |

Probe (2026-11-12, `apl-dev`): `Database.upsert` on a generic `List<SObject>` with an external-Id field works in default and user mode, so A's `dmlUpsert(List<SObject>, SObjectField)` is feasible. Anonymous Apex can't use `AccessLevel.SYSTEM_MODE`, so probe system mode from a class.

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
