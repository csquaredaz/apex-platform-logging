# ADR 0002: Publish one Log_Event\_\_e per entry, with typed fields

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** Chad Countryman

## Context

`PlatformEventLogger` turns `ILogger` calls into Platform Events. A subscriber persists them (PR 3), and later alerting reads the same stream. The schema decides three things: how much one publish call can carry, how many events count against the hourly publish allocation, and whether a subscriber can filter or map entries without parsing them.

Facts that shape it:

1. One `EventBus.publish(List<SObject>)` call counts once against the per-transaction limit of 150 publish-immediate calls, however many events the list holds.
2. The hourly allocation counts events, not calls. A scratch org allows 250,000 high-volume publishes per hour (measured in `apl-dev`, 2026-11-12).
3. An event can be up to 1 MB, and long text fields on a Platform Event can be up to 131,072 characters.
4. Persistence wants an idempotency key, because Platform Event delivery is at-least-once.

## Options

1. **One event per entry, with typed fields** (chosen). For: a subscriber maps fields one to one, and a trigger batch of up to 2,000 events is ordinary bulk Apex. `Level__c` can be filtered without parsing. `Request_Id__c` plus `Sequence__c` is a natural external Id for an idempotent upsert. A bad entry fails alone. Against: every entry counts against the hourly event allocation, so a chatty DEBUG level can use it up. `Minimum_Level__c` is the control.
2. **One event per flush, carrying a JSON array.** For: one event per transaction, so the hourly allocation stretches 50 times further. Against: the subscriber has to parse and validate JSON. One malformed entry poisons the whole batch, nothing can be filtered on a field, and a batch nears the 1 MB event limit with stack traces.
3. **A hybrid: typed fields for the first entry, JSON for the rest.** For: none worth the complexity. Against: two code paths in both the publisher and the subscriber.

## Decision

Option 1, because it keeps the subscriber a plain field mapping with a natural idempotency key. The allocation risk it brings is controlled by configuration (`Minimum_Level__c`) rather than by code.

## Schema

| Field                  | Type          | Notes                                                                   |
| ---------------------- | ------------- | ----------------------------------------------------------------------- |
| `Level__c`             | Text(10)      | `DEBUG`, `INFO`, `WARN` or `ERROR`. Platform Events have no picklists.  |
| `Message__c`           | LongText(32K) | Cut at 32,768 characters with a `...[truncated]` marker.                |
| `Exception_Type__c`    | Text(255)     | For example `System.DmlException`.                                      |
| `Exception_Message__c` | LongText(32K) | Kept apart from `Message__c`, so the caller's text stays searchable.    |
| `Stack_Trace__c`       | LongText(32K) |                                                                         |
| `Request_Id__c`        | Text(64)      | `Request.getCurrent().getRequestId()`.                                  |
| `Sequence__c`          | Number(6,0)   | Starts at 1 per transaction. With `Request_Id__c`, the idempotency key. |
| `Quiddity__c`          | Text(40)      | The execution context, for example `QUEUEABLE`.                         |
| `Logged_At__c`         | DateTime      | When the entry was logged. The event `CreatedDate` is the flush time.   |

The 32,768-character cap keeps three long fields well under the 1 MB event limit. The publishing user is the event's `CreatedById`, so no user field is added.

## Consequences

- PR 3's subscriber upserts on `Request_Id__c` + `Sequence__c`, so a redelivered event updates the same row instead of duplicating it.
- Each entry is one event against the hourly allocation. Production orgs should run at `INFO` or above. Storage is handled by retention (ADR 0007, PR #6).
- Adding a field later is backward compatible. Removing or retyping one needs a new package version and a subscriber change in the same release.
