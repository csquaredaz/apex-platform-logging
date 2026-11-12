# Handoff: apex-platform-logging

Last updated: 2026-11-12 · Phase: roadmap step 2. PRs #1–#3 merged; PR #4 `feat/persistence` open on apex-core-lib 1.1.0-1

## Done

- Repository scaffolded by hand from the `sf-repo-scaffold` template at `claude-code-salesforce-skills` `main` (back-port PR #8), plus the template `LICENSE` from E PR #9.
- Depends on `apex-core-lib@1.1.0-1` (`04tak000000u3MbAAI`, adds upsert) since PR #4; `1.0.0-1` before that. `sfdx-project.json` adds `definitionFile` and `versionDescription`, which a package version build needs and the template lacks (an E final-pass item).
- ADR 0001: B is its own unlocked package with no namespace.
- Local dev org `apl-dev` (7 days, expires 2026-11-19): A upgraded to `1.1.0-1`; B deployed with `--source-dir force-app`.

- PR #1 `chore/scaffold` merged; CI secrets set; `main` green.
- PR #2 `feat/event-logger` (merged; the `main` run reused the PR result): `Log_Event__e` (Publish Immediately, high volume), `Logging_Setting__mdt` + `Default` row, `DI_Binding.Platform_Event_Logger` (ILogger → `PlatformEventLogger`), the `Log_Event_Publisher` permission set, `PlatformEventLogger`, `LogBuffer`, `LogEntry`, `LogContext`, `LoggingSettings`, `ILogEventPublisher` + `EventBusPublisher`, and ADRs 0002–0004. 40 tests and 100% coverage on B's classes in `apl-dev`.

- GitHub PR #3 `docs/handoff-pr3-plan` merged: the persistence plan and D10–D13. (The plan called the persistence PR "#3"; on GitHub it is #4.)
- **PR #4 `feat/persistence`** (open; Chad merges): `Log__c` (AutoNumber, OWD Private, `Log_Key__c` Text 80 External Id + Unique + case-sensitive), `LogEventTrigger` → `TriggerDispatcher`, `LogEventsDomain` + `Constructor` bound by `DI_Binding.Log_Events_Domain`, `LogBuffer.suppress()` / `resume()`, the `Log_Viewer` permission set, and ADR 0005. 62 tests and 100% coverage on B's classes in `apl-dev`.
  - Proven in tests: Publish Immediately survives a caller's savepoint rollback (R3); `Test.getEventBus().deliver()` redelivers after `RetryableException`, so the retry path uses the real `EventBus.TriggerContext.retries` (4 deliveries, 4 commits, 1 give-up); the `Log_Key__c` describe is `idLookup`.
  - Added beyond the plan: the domain keeps one row per key per batch (a repeated key fails the whole upsert), and a key falls back to `uuid-<EventUuid>`, or to null (insert) when the event has neither part.

## Next

1. Chad merges PR #4; check that the `main` run takes the reuse path.
2. PR #5 `feat/slack-alerts`: probe R2 first (the Automated Process user's External Credential access) in `apl-dev`.
3. PR #6 `feat/retention`: storage is the binding limit (R4).
4. PR #7 `docs/example-and-readme`, then the release (tag only with approval). The README must document assigning `Log_Event_Publisher` and `Log_Viewer`, and the `Trigger_Setting__mdt` kill switch for `Log_Event__e`.

## Open decisions and known items

- `LogBuffer` has one Moderate Code Analyzer finding: the class's total cognitive complexity is 52 against a threshold of 50 (no method is above 8). CI gates at High. Splitting the fallback and limit logic out of `LogBuffer` would clear it; decide before the release.
- Before B goes public: check README snippets against the code, then follow the going-public sequence (as for A).

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

### Decisions for PR #4, persistence (2026-11-12)

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
