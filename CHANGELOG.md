# Changelog

Each `## X.Y.Z` section is added to the GitHub release notes for tag `vX.Y.Z` by `release.yml`.

## 1.0.0

First release. It requires [apex-core-lib](https://github.com/csquaredaz/apex-core-lib) `1.1.0` (`04tak000000u3MbAAI`), so install that first.

### Added

- **Logging:** `PlatformEventLogger` implements A's `ILogger` and is bound by `DI_Binding.Platform_Event_Logger`. Entries are buffered per transaction and published as Publish Immediately `Log_Event__e` events, so they survive a rollback. It never throws, and it keeps 5 publish-immediate calls for your code. Configured by `Logging_Setting__mdt.Default`: `Is_Enabled__c`, `Minimum_Level__c`, `Buffer_Size__c` (ADRs 0002–0004).
- **Persistence:** a `Log_Event__e` subscriber upserts each entry as a `Log__c` row on `Log_Key__c` and retries a failed batch three times (ADR 0005). `Log__c` is Private.
- **Slack alerts:** `SlackAlertSink` implements A's `IAlertSink`. `ERROR` entries become one Block Kit message per batch through the `Slack` Named Credential. `DI_Binding.Slack_Alert_Sink` ships **inactive** (ADR 0006).
- **Retention:** `LogRetentionBatch` hard-deletes `Log__c` rows older than `Retention_Days__c` (default 30). Schedule it with `LogRetentionSchedule.schedule()`; turn it off with `Is_Retention_Enabled__c` (ADR 0007).
- **Permission sets:** `Log_Event_Publisher` (for users whose code logs), `Log_Viewer` (read logs) and `Slack_Alert_Sender` (for the Automated Process user, once Slack is set up).

### After installing

1. Assign `Log_Event_Publisher` to users whose code logs, and `Log_Viewer` to people who read logs. Without `Log_Event_Publisher`, entries go to the debug log.
2. Run `LogRetentionSchedule.schedule();` in anonymous Apex, as an admin who has `Log_Event_Publisher`. An unlocked package can't schedule its own job.
3. Optionally, set up Slack: see the README's Setup section and ADR 0006.
