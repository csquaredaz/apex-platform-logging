# ADR 0007: Hard-delete old Log\_\_c rows with a scheduled batch that runs in system mode and reports at WARN

- **Status:** Accepted
- **Date:** 2026-11-13
- **Deciders:** Chad Countryman

## Context

`Log__c` grows with every persisted entry (ADR 0005). Storage is the binding limit (R4): a scratch org allows 250,000 high-volume publishes per hour but has 500 MB of data storage, and a `Log__c` row counts as about 2 KB. That makes about 256,000 rows in all, so without retention a chatty org fills its storage in hours. Constraints:

1. **Running user.** `Log__c` is OWD Private, and its rows are owned by the Automated Process user. Whoever runs retention may have no `Log__c` access at all.
2. **Configuration** lives in the `Logging_Setting__mdt` `Default` row (D8) and must fail safe when it's blank.
3. **A's layers apply.** Selectors own SOQL and a Unit of Work owns DML. A's `SObjectSelector` queries in user mode only and has no query locator.
4. **Loop guard (D15).** Only `ERROR` entries raise Slack alerts, so retention must never log at `ERROR`.
5. **Free only.** No paid archiving or storage service. Rows past their retention are deleted, not exported. Exporting first (for example, the Bulk API to a file) is left to the org.

### Probes (`apl-dev`, 2026-11-13)

Throwaway classes deployed from a separate project and removed afterwards.

| Question                                                                    | Result                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **R7a.** Do soft-deleted `Log__c` rows count against data storage?          | **Probably not; weak evidence.** 10,000 rows took the org from 500 to 481 MB remaining. The storage figure lags by about 30–60 s, and once the soft delete had registered it read 500 MB again with all 10,000 rows in the bin. After an undelete it read 481 MB again. The soft-delete step wasn't repeated under the 30-second poller, and the "back to 500" reading is a single read taken right after the undelete. That agrees with Salesforce's help and large data volumes guide; some third-party sources disagree. |
| **R7b.** Does `Database.emptyRecycleBin` from a batch remove them?          | **Yes.** All 10,000 results succeeded, and undeleting one afterwards fails with `UNDELETE_FAILED: Entity is not in the recycle bin`. `SELECT … ALL ROWS` still returns emptied rows with `IsDeleted = true` for minutes afterwards, in the org and in tests, so tests check the undelete result, not SOQL.                                                                                                                                                                                                                  |
| **R8.** Can a no-namespace unlocked package schedule its job at install?    | **No.** `@salesforce/packaging` (`packageVersionCreate.js`, `validateOptionsForPackageType`) rejects a post-install or uninstall script for an Unlocked package with `errorScriptsNotApplicableToUnlockedPackage`: "available only for second-generation managed packages". Read from the CLI source (sf 2.157.8); no package version was spent.                                                                                                                                                                            |
| Who runs a scheduled `Batchable`?                                           | **The user who called `System.schedule`.** That user ran the `Schedulable` and the batch's `execute` and `finish`, and created all three `AsyncApexJob` records.                                                                                                                                                                                                                                                                                                                                                            |
| What does that user need, as a Minimum Access user without `Log__c` access? | **Nothing on `Log__c`, if the code is `without sharing`.** A system-mode query in a `with sharing` class saw 0 rows, because sharing still applies. The same query `without sharing` saw all of them. A system-mode delete then worked. `LogRetentionIntegrationTest` pins it, including `emptyRecycleBin` from the `with sharing` `RecycleBinPurge`.                                                                                                                                                                       |

## Options

### Mechanism (D17)

1. **`Schedulable` + `Database.Batchable` over a query locator** (chosen). For: up to 50 million rows per run, each chunk is its own transaction, and `Database.Stateful` carries the totals. Against: one scheduled job to set up, plus a batch slot per run.
2. **A self-chaining `Queueable`.** Against: 50,000 rows per query, hand-written paging, and a chain that has to stop itself.
3. **A scheduled Flow.** Against: it can't empty the Recycle Bin or use the selector and Unit of Work, and it is harder to test.

### Scheduling (D18)

1. **`LogRetentionSchedule.schedule()` / `schedule(cron)` / `unschedule()`, run once from anonymous Apex** (chosen). It is idempotent: a job with the same name is replaced, inside a savepoint, so an invalid cron expression keeps the old job. Against: a manual step after installing.
2. **Only the Setup "Schedule Apex" page.** Against: daily or weekly only, and nothing stops a second copy of the job.
3. **A post-install script.** Ruled out by R8.

### Retention setting (D19)

1. **One `Retention_Days__c` for every level** (chosen). Blank or below 1 means 30, and above 3650 means 3650, the same fail-safe clamp as `Buffer_Size__c`. For: one range on the indexed `CreatedDate`. Against: errors can't outlive debug lines. Per-level retention is the recorded extension point.
2. **Two values, with a longer `Error_Retention_Days__c`.** Against: two OR'ed ranges, a less selective query, and more configuration.
3. **One value per level.** Against: four ranges for a need nobody has stated yet.

### Delete path (D20)

1. **Hard delete through the Unit of Work: `registerDeleted` with `SystemDml`, then `registerWork(new RecycleBinPurge(scope))`** (chosen). For: no change to A, because A's commit runs registered work after its deletes, inside the same savepoint, so a failed purge rolls the delete back. R7a suggests storage alone doesn't need it, but the Recycle Bin holds only about 25 records per MB of storage and purges its oldest entries early when full. Daily log purges would push users' deleted business records out of it. Hard deletion also removes exception text for good. Against: no undo.
2. **Soft delete only.** For: the simplest option, with a 15-day undo. Against: the Recycle Bin crowding above.
3. **`IDml.dmlHardDelete` in apex-core-lib 1.2.0.** Against: an A release, a package version and a dependency bump for one call, when `IDoWork` already fits.

### Kill switch (D21)

1. **`Is_Retention_Enabled__c` checkbox, default true, checked in `start` and in every `execute`** (chosen). Unticking it stops a run in progress, without a deploy.
2. **Blank `Retention_Days__c` means off.** Against: blank means "the default" for `Buffer_Size__c`, so it would mean two things.
3. **Unscheduling only.** Against: it needs Apex, and a run in progress keeps going.

### Failure reporting (D22)

1. **Catch each failed chunk, log WARN with its size and cause, and continue; `finish` logs an INFO summary, plus a WARN if any chunk failed** (chosen). Against: an uncatchable `LimitException` shows only as a failed `AsyncApexJob`.
2. **The same, plus `Database.RaisesPlatformEvents` and a `BatchApexErrorEvent` trigger.** For: it covers the uncatchable case. Against: another trigger, its running user's permissions and more tests, for a case that a 2,000-row delete with no `Log__c` triggers is unlikely to hit.
3. **Let it throw.** Against: nothing reaches `Log__c`, only the failure email to the submitter.

## Decision

Option 1 in each group.

## Rules

- **Cutoff.** `start` computes it once: now minus `Retention_Days__c`. `LogsSelector.queryLocatorCreatedBefore` selects `Id` and `CreatedDate` where `CreatedDate` is before the cutoff, oldest first. `CreatedDate` is indexed and never null; `Logged_At__c` is neither. A null cutoff (retention off) selects nothing.
- **Sharing exceptions.** `LogsSelector` is `without sharing` and queries in system mode, for the reason in the probe table. It is the second documented exception to the repository's user-mode rule, after `SystemDml` in the subscriber (ADR 0005). `CronTriggersSelector` stays user mode.
- **Chunks.** `BATCH_SIZE = 2000`, the query-locator maximum. Per chunk: 3 DML statements (savepoint, delete, purge), 4,000 DML rows, no SOQL. `Log__c` has no triggers.
- **Log lines** start with `Log retention: ` (`LogRetentionBatch.LOG_PREFIX`) and are only INFO or WARN. They go through `ILogger`, so they are published, persisted and visible in `Log__c` like any other entry.
- **Bindings.** `DI_Binding.Logs_Selector` binds `Log__c` to `LogsSelector`, so tests substitute a mock through `Application.Selector`.

## Setup (once per org, after installing)

1. Optionally, set `Logging_Setting__mdt.Default.Retention_Days__c` (default 30).
2. As an admin, assign yourself `Log_Event_Publisher`, so the job's own log lines are published. Without it, they go to the debug log (ADR 0003).
3. Run `LogRetentionSchedule.schedule();` in anonymous Apex (daily at 02:00, org time), or pass a cron expression.

The job runs as that admin. If the admin is deactivated, the job stops; schedule it again as another user.

## Consequences

- **Rollback.** Untick `Is_Retention_Enabled__c` to stop deleting at once, or run `LogRetentionSchedule.unschedule()`. Rows that are already deleted are gone (no undo by design).
- Steady state is about `Retention_Days__c` × the rows logged per day. At 30 days, about 8,500 rows a day fit in a 500 MB scratch org. `Minimum_Level__c` (ADR 0002) is still the first control.
- Tests can't measure storage. The storage figures here come from the probe.
- Not proven: the Setup UI route for scheduling, and the behaviour once the 25-records-per-MB Recycle Bin limit is reached.
