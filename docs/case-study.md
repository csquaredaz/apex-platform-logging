# Case study: apex-platform-logging

<!--
Reused verbatim on the portfolio site, so keep it self-contained: no relative links, no employer
or client names, and no production metrics. "Informed by production experience at scale" is the
most specific claim allowed.
-->

**Problem.** Salesforce Apex has no log that survives the failure it describes. `System.debug` is invisible without a trace flag, and log records inserted in a transaction vanish when it rolls back. A logger also has to stay within governor limits, keep its storage bounded, and tell a person when something breaks, without ever breaking the code it watches.

**Approach.** The package is an adapter for a core library's `ILogger` and `IAlertSink` ports (Ports and Adapters, wired by a Custom Metadata DI container), so calling code never references it. Entries are buffered per transaction and published as Publish Immediately Platform Events, which survive a rollback. A subscriber persists them through a Domain and a Unit of Work, upserting on an idempotency key, and turns `ERROR` entries into Slack Block Kit alerts from a Queueable with a Finalizer. A scheduled batch hard-deletes rows past their retention.

**Trade-offs.**

- One event per entry rather than one per flush: it costs more of the hourly event allocation, but the subscriber is a plain field mapping with a natural idempotency key, and one bad entry can't poison a batch.
- Alerts are raised by the subscriber, not the logger, because an enqueue from a failing transaction would roll back with it.
- Retention hard-deletes, because a daily soft delete would crowd users' records out of the Recycle Bin.
- Each choice is recorded in an ADR with its rejected alternatives.

**Result.**

- 120+ Apex tests at 100% coverage of the package's classes, including 200-record bulk cases, Minimum Access `runAs` tests and a real-event-bus rollback test.
- Zero High Code Analyzer findings, and CI that runs a fresh scratch org per ready PR.
- Seven ADRs, with platform behaviour proven by small probes before design: who runs a Platform Event subscriber and its Queueable, when emptied Recycle Bin rows disappear from SOQL, and that an unlocked package can't run a post-install script.
- Free tooling throughout.

**Stack.** Apex · Platform Events · Salesforce DX · unlocked packages · GitHub Actions · Claude Code (`apex-standards`)
