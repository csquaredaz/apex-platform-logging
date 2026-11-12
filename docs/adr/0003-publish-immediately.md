# ADR 0003: Publish log events immediately, and grant publish access through a permission set

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** Chad Countryman

## Context

A logger is most needed when a transaction fails, and a failing transaction usually rolls back. A Platform Event's publish behaviour decides whether the entries survive that rollback:

- **Publish After Commit** events are published only if the transaction commits.
- **Publish Immediately** events are published when `EventBus.publish` is called, whatever happens to the transaction afterwards.

Both claims were probed in the dev scratch org `apl-dev` on 2026-11-12 before this decision (risk R3 in `handoff.md`):

| Probe                                                  | Result                                                                                         |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| Publish Immediately, then an uncaught exception        | Event delivered                                                                                |
| Publish Immediately, then a `LimitException`           | Event delivered                                                                                |
| Publish After Commit, then rollback                    | Event lost; the caller's DML also rolled back                                                  |
| Scratch org allocation (R4)                            | 250,000 high-volume publishes per hour; 500 MB storage                                         |
| `EventBus.publish` as a Minimum Access user, from Apex | **Rejected**: `CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY`, "Access to entity 'Log_Event__e' denied" |
| The same from a `without sharing` publisher            | Rejected the same way                                                                          |

The last two rows were found by `PlatformEventLoggerIntegrationTest` while building PR 2. `EventBus.publish` checks the running user's Create permission on the event, even from Apex, and sharing keywords don't change that. Create on a Platform Event also requires Read.

## Options

1. **Publish Immediately, with a packaged `Log_Event_Publisher` permission set** (chosen). For: entries survive rollbacks, uncaught exceptions and limit failures, which is exactly when they matter. The permission set grants the minimum: Create and the Read it requires on `Log_Event__e`, nothing else. Against: an entry can describe work that was later rolled back, so messages must describe attempts ("Booking shipment for order 42"), not outcomes ("Shipment booked"). Every user whose code logs needs the assignment, and a missing assignment loses entries to the debug log.
2. **Publish After Commit.** For: the log only ever describes committed work. Against: the entries for a failed transaction, the ones you need most, are lost.
3. **Two event types, one of each.** For: the caller chooses. Against: two schemas and two subscribers, and every call site has to choose correctly.
4. **No permission set; document the access only.** For: nothing extra in the package. Against: it is easy to miss, and a missing grant is silent unless someone reads debug logs.

## Decision

Option 1, because surviving a rollback is the reason this logger exists, and the access it needs can be packaged as the smallest permission set that works.

## Consequences

- **Setup step:** assign `Log_Event_Publisher` to every user whose code logs. That includes integration users, and the Automated Process user if logging runs from Platform Event triggers (checked with R2 in the Slack PR).
- The Read that Create requires also lets an assigned user subscribe to the event channel over the Pub/Sub or Streaming API. That is acceptable for log data in this design. Revisit it if log messages ever carry sensitive data.
- When the permission is missing, `LogBuffer` writes the entry to the debug log. The fallback reason ends with "Assign the Log_Event_Publisher permission set to this user." Two integration tests pin both paths.
- Each flush uses one of the 150 publish-immediate calls per transaction. ADR 0004 covers the guard.
- **Rollback posture:** deactivating `DI_Binding.Platform_Event_Logger` returns every caller to A's `DebugLogger` with no deploy of code.
