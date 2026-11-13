# Handoff: apex-platform-logging

Last updated: 2026-11-13 · Phase: roadmap step 2. PRs #1–#9 merged; **`v1.0.0` released as `1.0.0-2` (`04tak000000uEhpAAE`)**; PR #10 `docs/release-1.0.0` open

## Done

- Repository scaffolded by hand from the `sf-repo-scaffold` template at `claude-code-salesforce-skills` `main` (back-port PR #8), plus the template `LICENSE` from E PR #9.
- Depends on `apex-core-lib@1.1.0-1` (`04tak000000u3MbAAI`, adds upsert) since PR #4; `1.0.0-1` before that. `sfdx-project.json` adds `definitionFile` and `versionDescription`, which a package version build needs and the template lacks (an E final-pass item).
- ADR 0001: B is its own unlocked package with no namespace.
- Local dev org `apl-dev` (7 days, expires 2026-11-19): A upgraded to `1.1.0-1`; B deployed with `--source-dir force-app`.

- PR #1 `chore/scaffold` merged; CI secrets set; `main` green.
- PR #2 `feat/event-logger` (merged; the `main` run reused the PR result): `Log_Event__e` (Publish Immediately, high volume), `Logging_Setting__mdt` + `Default` row, `DI_Binding.Platform_Event_Logger` (ILogger → `PlatformEventLogger`), the `Log_Event_Publisher` permission set, `PlatformEventLogger`, `LogBuffer`, `LogEntry`, `LogContext`, `LoggingSettings`, `ILogEventPublisher` + `EventBusPublisher`, and ADRs 0002–0004. 40 tests and 100% coverage on B's classes in `apl-dev`.

- GitHub PR #3 `docs/handoff-pr3-plan` merged: the persistence plan and D10–D13. (The plan called the persistence PR "#3"; on GitHub it is #4.)
- **PR #4 `feat/persistence`** (merged as `cc4b925`; the `main` run took the reuse path): `Log__c` (AutoNumber, OWD Private, `Log_Key__c` Text 80 External Id + Unique + case-sensitive), `LogEventTrigger` → `TriggerDispatcher`, `LogEventsDomain` + `Constructor` bound by `DI_Binding.Log_Events_Domain`, `LogBuffer.suppress()` / `resume()`, the `Log_Viewer` permission set, and ADR 0005. 62 tests and 100% coverage on B's classes in `apl-dev`.
  - Proven in tests: Publish Immediately survives a caller's savepoint rollback (R3); `Test.getEventBus().deliver()` redelivers after `RetryableException`, so the retry path uses the real `EventBus.TriggerContext.retries` (4 deliveries, 4 commits, 1 give-up); the `Log_Key__c` describe is `idLookup`.
  - Added beyond the plan: the domain keeps one row per key per batch (a repeated key fails the whole upsert), and a key falls back to `uuid-<EventUuid>`, or to null (insert) when the event has neither part.

- **PR #5 `feat/slack-alerts`** (merged as `8d1c9a7`; the `main` run took the reuse path): `SlackAlertSink` (the `IAlertSink` adapter; the `DI_Binding.Slack_Alert_Sink` row ships inactive), `SlackAlertJob` (Queueable + AllowsCallouts), `SlackAlertFinalizer`, `SlackMessageBuilder` (Block Kit, 50-block cap), the `AlertJobEnqueuer` seam, the `Slack` Named Credential and External Credential (Custom protocol, `Bot_Token` header formula, no token in source), the `Slack_Alert_Sender` permission set, `Logging_Setting__mdt.Slack_Channel__c`, alert raising in `LogEventsDomain`, and ADR 0006. 100 tests and 100% coverage on B's 13 classes in `apl-dev`.
  - R2 proven first with a throwaway probe (removed afterwards); see below and ADR 0006.

- **PR #6 `feat/retention`** (merged as `260ed3f`; the `main` run took the reuse path): `LogRetentionBatch` (Batchable + Stateful, 2,000-row chunks), `LogRetentionSchedule` (Schedulable plus idempotent `schedule()` / `schedule(cron)` / `unschedule()`), `ILogsSelector` + `LogsSelector` (system mode, `without sharing`, a query locator on `CreatedDate`) bound by `DI_Binding.Logs_Selector`, `CronTriggersSelector`, `RecycleBinPurge` (`IDoWork` → `Database.emptyRecycleBin`), `Logging_Setting__mdt.Retention_Days__c` (30) and `Is_Retention_Enabled__c` (true), and ADR 0007. 123 tests and 100% coverage on B's 17 classes in `apl-dev`, including a 200-row bulk case and a Minimum Access `runAs` run.
  - R7, R8 and the running user were probed first with throwaway metadata (removed afterwards); see below and ADR 0007.
  - Also proven in tests: a savepoint rollback restores a job that `System.abortJob` aborted, so `schedule('bad cron')` keeps the existing job; `emptyRecycleBin` works from a `with sharing` class for a Minimum Access user.

- **PR #7 `docs/example-and-readme`** (merged as `f75bf69`; the `main` run took the reuse path):
  - The README, written in full in the workspace order, with a setup checklist and a kill-switch table.
  - `docs/case-study.md`.
  - An unpackaged `example/` package directory, as in A: `OrderConfirmationService` logs through `ILogger`, and `OrderConfirmationIntegrationTest` proves an ERROR survives the rollback and raises one alert. The README snippet is copied from it.
  - `scripts/org-test.sh`, so `npm run org:test` runs only this repo's `*Test` classes (the old `RunLocalTests` also ran A's tests).
  - Sampling recorded as a deliberate omission in ADR 0004 and the README.
  - 126 tests in `apl-dev`.
  - Retention isn't scheduled by `org:setup`: a live job with `LogRetentionSchedule.JOB_NAME` would sit next to `LogRetentionScheduleTest`'s scheduling. The README documents the setup step.
- **PR #8 `refactor/log-buffer`** (merged as `c9b8f46`; the `main` run took the reuse path): `LogFallback` now owns the failure path, `write` (to the debug log, with the reason) and `describe` (a failed save result, plus the `Log_Event_Publisher` hint), along with the test counters. `LogBuffer` keeps buffering, flush triggers, suppression and the limit guard. No behaviour change. Code Analyzer reports **zero Moderate** and zero High; 130 tests and 100% on 19 classes in `apl-dev`. ADR 0004 notes the split.
- **Release prep (2026-11-13):**
  - Package `apex-platform-logging` created in the Dev Hub: `0Hoak0000007WWDCA2`, Unlocked, no namespace. Trap: `sf package create` rewrote the `force-app` package directory, dropping `default`, `dependencies` and `definitionFile` and resetting the version to `0.1.0`, so only the alias was kept.
  - **R1 and R6 proven at packaging level** by a skip-validation build (`04tak000000uEGPAA2`, `1.0.0.1`; it used the 500/day budget, not the 6): `DI_Binding__mdt` rows of A's type and the Named and External Credentials package, with `HasMetadataRemoved: false`. Installing is proven only by the beta smoke test. That probe took build number 1, so the validated release will be **`1.0.0-2`**. The probe version can't be promoted.
  - PR #9 `chore/release-1.0.0` (merged as `135254f`; the `main` run took the reuse path): `CHANGELOG.md`, plus A's `scripts/changelog-section.sh` and the `release.yml` steps that use it (a tag without a changelog section fails before the build; both jobs add the section to the notes), the package alias, and this handoff.
- **Release `v1.0.0` (2026-11-13):**
  - Tag `v1.0.0` pushed at `135254f` with Chad's approval. Release run 43474023414 built `1.0.0-2` = `04tak000000uEhpAAE`, validated, with 100% code coverage.
  - **Smoke test** in a throwaway scratch org `apl-smoke` (A `1.1.0-1`, then the beta; Chad deleted it afterwards):
    - all 4 DI bindings present (Slack inactive); the Default setting; `LogEventTrigger`; the 3 permission sets; the `Slack` Named and External Credentials
    - `ILogger` resolves to `PlatformEventLogger`; `example/` is absent
    - a live INFO and ERROR round trip into `Log__c`; `schedule()` and `unschedule()` work
    - 127/127 packaged tests pass
  - **R1 and R6 are fully proven.**
  - Chad promoted it with `workflow_dispatch` (run 43475422877). The version is released, and the GitHub release `v1.0.0` is Latest, with the changelog section in its notes.
  - PR #10 `docs/release-1.0.0`: the README install section and dependency snippet, the `apex-platform-logging@1.0.0-2` alias, and this handoff.

## Next

1. Chad merges PR #10; check the `main` run.
2. Optional cleanup, with Chad's OK: delete the unpromotable skip-validation probe version `04tak000000uEGPAA2`, and the merged branches.
3. Before B goes public: check the README snippets against the code (done for Usage in PR #7), then the going-public sequence used for A. That is: fix any leak sources first; delete the old CI runs; scan the remaining logs and the PR text; then Chad flips visibility.
4. After that, roadmap step 3: repo C `apex-event-ingestion`. Apply the E final-pass items first or along the way (see below).

## Open decisions and known items

- `LogBuffer` has one Moderate Code Analyzer finding: the class's total cognitive complexity is 52 against a threshold of 50 (no method is above 8). CI gates at High. Fixed 2026-11-13 in PR #8 (`LogFallback` split out).
- Sampling (promised in the roadmap) is deliberately omitted (decided 2026-11-13, ADR 0004); the roadmap line was updated.
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

### Decisions for PR #6, retention (2026-11-13, ADR 0007)

| #   | Decision          | Choice                                                                                                                           | Rejected                                                                     |
| --- | ----------------- | -------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| D17 | Mechanism         | `Schedulable` + `Batchable` over a query locator, 2,000-row chunks                                                               | A self-chaining Queueable; a scheduled Flow                                  |
| D18 | Scheduling        | `LogRetentionSchedule.schedule()` / `unschedule()` from anonymous Apex; idempotent, daily at 02:00 by default                    | The Setup "Schedule Apex" page only; a post-install script (impossible, R8)  |
| D19 | Retention setting | One `Retention_Days__c`: default 30, blank or below 1 → 30, above 3650 → 3650                                                    | A longer error retention; one value per level (the recorded extension point) |
| D20 | Delete path       | Hard delete in one Unit of Work: `registerDeleted` (`SystemDml`) then `registerWork(RecycleBinPurge)`                            | Soft delete only (crowds the Recycle Bin); `IDml.dmlHardDelete` in A 1.2.0   |
| D21 | Kill switch       | `Is_Retention_Enabled__c`, default true, checked in `start` and every `execute`                                                  | Blank days means off; unscheduling only                                      |
| D22 | Failures          | Catch a failed chunk, WARN with size and cause, continue; INFO summary in `finish`, plus a WARN if any chunk failed; never ERROR | Also a `BatchApexErrorEvent` trigger; letting it throw                       |

### Decisions for PR #5, Slack alerts (2026-11-12, ADR 0006)

D5–D7 above are implemented as decided. The new decisions:

| #   | Decision     | Choice                                                                                                                  | Rejected                                                                                                 |
| --- | ------------ | ----------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| D14 | Alert origin | The subscriber: after a batch is persisted or given up, its `ERROR` rows become `CRITICAL` alerts, one `send` per batch | Explicit `IAlertSink` calls only; `PlatformEventLogger.error()` (its enqueue rolls back with the caller) |
| D15 | Loop guard   | Only `ERROR` alerts (fixed); the sink, job and finalizer log failures at `WARN` only                                    | A configurable level with `LogBuffer` suppressed in the job; a source field on `Log_Event__e`            |
| D16 | Finalizer    | On an unhandled failure: WARN with the cause and each lost alert title; no retry                                        | Retry once (could post twice)                                                                            |

### Decisions for PR #4, persistence (2026-11-12)

| #   | Decision         | Choice                                                                                | Rejected                                                                                                |
| --- | ---------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| D10 | Upsert path      | Add `dmlUpsert` / `registerUpsert` to A's `IDml` / `IUnitOfWork`, released as A 1.1.0 | A B-owned `ILogStore` with direct `Database.upsert`; insert and ignore duplicates; extension interfaces |
| D11 | Subscriber retry | `EventBus.RetryableException` while retries < 3, then the debug log                   | No retries; per-event checkpoints                                                                       |
| D12 | Recursion        | `LogBuffer` suppression flag around persistence                                       | Relying on D9's `DebugLogger` alone (A's dispatcher logs through `ILogger`)                             |
| D13 | Visibility       | OWD Private + a `Log_Viewer` permission set (Read, View All)                          | Public Read Only                                                                                        |

Probe (2026-11-12, `apl-dev`): `Database.upsert` on a generic `List<SObject>` with an external-Id field works in default and user mode, so A's `dmlUpsert(List<SObject>, SObjectField)` is feasible. Anonymous Apex can't use `AccessLevel.SYSTEM_MODE`, so probe system mode from a class.

## Risks to probe

- **R1 (proven 2026-11-13):** B packages `DI_Binding__mdt` records of A's type. Proven by the skip-validation build, the `1.0.0-2` build and an install into a clean scratch org.
- **R2 (proven 2026-11-12, `apl-dev`):** the subscriber, the Queueable it enqueues and that job's Finalizer all run as the Automated Process user. Without principal access the callout throws a catchable `CalloutException` ("We couldn't access the credential(s)"). A permission set with `externalCredentialPrincipalAccesses`, assigned to that user by an Apex insert, lets the callout through. A header formula with no token still sends, so a missing token shows up as Slack's `not_authed`. `HttpCalloutMock` answers even for a Minimum Access user without principal access. Not proven: the Setup UI assignment route. The `PlatformEventSubscriberConfig` fallback isn't needed and is documented as an option. The probe metadata and rows were removed.
- **R6 (proven 2026-11-13):** Named and External Credentials package and install in a no-namespace unlocked package (the `1.0.0-2` build and smoke test). Still unproven: a real Slack post after setting a token (free only).
- **R3 (proven 2026-11-12):** a Publish Immediately event is delivered after an uncaught exception and after a `LimitException`. Publish After Commit events are lost on rollback. Evidence is in ADR 0003.
- **R4 (measured 2026-11-12):** the scratch org allows 250,000 high-volume publishes per hour and has 500 MB of data storage, so storage is the binding limit (retention, PR #6, ADR 0007).
- **R7 (probed 2026-11-13, `apl-dev`):** soft-deleted `Log__c` rows probably don't count against data storage, but the evidence is weak. The org's storage figure lags by about 30–60 s, so the readings come from a 30-second poll, and the soft-delete step itself wasn't repeated under the poller. `Database.emptyRecycleBin` from a batch removes them for good: undelete fails with `UNDELETE_FAILED`. `ALL ROWS` still returns emptied rows for minutes, so tests check the undelete result. Retention hard-deletes anyway (D20).
- **R8 (proven 2026-11-13, CLI source):** an Unlocked package can't have a post-install script (`errorScriptsNotApplicableToUnlockedPackage` in `@salesforce/packaging`), so scheduling retention is a documented setup step (D18).
- **Retention running user (proven 2026-11-13):** a scheduled batch runs as the user who called `System.schedule`. It needs no `Log__c` permission when the code is `without sharing` and in system mode; a system-mode query in a `with sharing` class sees no rows for a user without View All.
- **R5 (found 2026-11-12, resolved):** `EventBus.publish` checks the running user's Create permission on `Log_Event__e`, even from Apex and from `without sharing` code. Create requires Read. Resolved with the packaged `Log_Event_Publisher` permission set (ADR 0003), pinned by two integration tests.

## Notes for the next session

- The `apl-dev` admin has `Log_Viewer` (assigned during the R2 probe), so `Log__c` can be queried from the CLI.
- `ServiceFactory.newInstance` returns a new instance on every call (no caching), so the logger's buffer must be static, per transaction.
- `TriggerDispatcher.run()` works for a Platform Event trigger. Bind the `LogEvents` domain with a `DI_Binding__mdt` row whose Kind is Domain. A's `Trigger_Setting__mdt` then gives persistence a kill switch.
- `sf org display` is blocked in auto mode, so API 68.0 came from A's verified value.
- An empty `force-app` deploys with "No changes to deploy" and exit 0.
