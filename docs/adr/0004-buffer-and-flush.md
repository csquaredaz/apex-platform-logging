# ADR 0004: Buffer entries per transaction, flush on error, size and demand, and never throw

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** Chad Countryman

## Context

Each `EventBus.publish` call uses one of the transaction's 150 publish-immediate calls (ADR 0003). Publishing on every `ILogger` call would let a loop of 150 log lines exhaust the limit, and the next call would throw a `LimitException`. Apex can't catch that, so it would take the caller's transaction down with it.

Two more facts shape the buffer:

1. A's `ServiceFactory.newInstance` returns a new `ILogger` on every call, so state held on a logger instance is lost between callers in the same transaction.
2. The logger is configured without a deploy, so admins can change the level in production.

## Options

1. **A static per-transaction buffer that flushes on `flush()`, on every `error()`, and at a configurable size, with a limit guard and a debug-log fallback** (chosen). For: one publish call per batch of up to 50 entries by default. Errors are published at once, with the entries that led up to them. The buffer survives A's new-instance-per-call factory. Against: entries still buffered when a transaction ends without `flush()` or `error()` are lost. The `ILogger` contract already asks callers to `flush()` at the end of a unit of work.
2. **Explicit `flush()` only.** For: the simplest model. Against: an uncaught exception or a forgotten `flush()` loses everything, including the error.
3. **Publish on every call.** For: nothing is ever buffered. Against: one publish call per line, and the limit failure described above.

## Decision

Option 1, because it spends a publish call per batch rather than per line, and it publishes failures straight away, which is when the log matters most.

## Rules

- **Shared buffer.** `LogBuffer.current()` is a static singleton, so every `PlatformEventLogger` instance in a transaction writes to one buffer.
- **Flush triggers:** `flush()`, every `error()`, and reaching `Buffer_Size__c` (default 50, clamped to 1–500).
- **Limit guard.** `LogBuffer` stops publishing when 5 or fewer publish-immediate calls remain (`PUBLISH_CALLS_RESERVED`). The host application always keeps its last calls, and logging never triggers the `LimitException`.
- **Never throw.** A publisher exception, a failed `SaveResult`, a missing result, or the reserve being reached all send the affected entries to `System.debug(ERROR, ...)` with the reason. The buffer is emptied first, so an entry is never published twice.
- **Configuration.** The `Logging_Setting__mdt` `Default` row holds `Is_Enabled__c` (a kill switch), `Minimum_Level__c` (default `DEBUG`) and `Buffer_Size__c`. Its fields are subscriber-controlled, so an admin can change them in production. A missing row or a blank field falls back to the defaults (D8 in `handoff.md`).

A hierarchy custom setting would allow per-user or per-profile levels. It was rejected for now, because metadata deploys with the package and needs no data step, but it is the recorded extension point.

## Consequences

- Callers should call `flush()` at the end of each unit of work, as A's `ILogger` documents.
- **Sampling is deliberately omitted** (2026-11-13). Volume is controlled by `Minimum_Level__c`, and storage is bounded by retention (ADR 0007). Random sampling would drop exactly the entries needed to follow one request. If it's ever needed, decide per transaction rather than per entry, and apply it only below `WARN`.
- A transaction that has used 145 publish-immediate calls on its own events logs only to the debug log. That is visible in the fallback reason, "publish-immediate limit reserve reached".
- Unit tests stub `ILogEventPublisher` with A's `Mocks`, so every fallback path is tested without a real publish. `PlatformEventLoggerIntegrationTest` pins the real behaviour: 200 entries at a buffer of 50 make exactly 4 publish calls.
