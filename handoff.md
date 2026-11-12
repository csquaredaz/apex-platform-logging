# Handoff: apex-platform-logging

Last updated: 2026-11-12 · Phase: roadmap step 2, PR 0 (scaffold)

## Done

- Repository scaffolded by hand from the `sf-repo-scaffold` template at `claude-code-salesforce-skills` `main` (back-port PR #8), plus the template `LICENSE` from E PR #9.
- Depends on `apex-core-lib@1.0.0-1` (`04tak000000u0zpAAA`). `sfdx-project.json` adds `definitionFile` and `versionDescription`, which a package version build needs and the template lacks (an E final-pass item).
- ADR 0001: B is its own unlocked package with no namespace.
- Local dev org `apl-dev` (7 days, expires 2026-11-19): A installed, empty deploy OK.

## Next

1. PR 0 `chore/scaffold`: Chad runs `gh secret set` (`SF_JWT_KEY`, `SF_CONSUMER_KEY`, `SF_DEVHUB_USERNAME`). Then mark the PR ready once and check the scratch-org job (deploy only; tests skipped until a test class exists).
2. Before PR 1, probe in `apl-dev`: R3 (a Publish Immediately event is still delivered when the publisher throws) and the scratch org's Platform Event limits.
3. PR 1 `feat/event-logger`, then PR 2 `feat/persistence`, PR 3 `feat/slack-alerts` (probe R2 first), PR 4 `feat/retention`, PR 5 `docs/example-and-readme`, then the release (tag only with approval).

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

## Risks to probe

- **R1:** B packages `DI_Binding__mdt` records of A's type. The deploy shows it; the package build proves it at release.
- **R2:** the Queueable enqueued from the Platform Event trigger runs as the Automated Process user, which needs External Credential principal access. Probe a permission set assignment to that user. Fallback: `PlatformEventSubscriberConfig` with a named user, documented as setup.
- **R3:** a Publish Immediately event is delivered even when the publishing transaction throws.
- **R4:** the scratch org's own Platform Event limits.

## Notes for the next session

- `ServiceFactory.newInstance` returns a new instance on every call (no caching), so the logger's buffer must be static, per transaction.
- `TriggerDispatcher.run()` works for a Platform Event trigger. Bind the `LogEvents` domain with a `DI_Binding__mdt` row whose Kind is Domain. A's `Trigger_Setting__mdt` then gives persistence a kill switch.
- `sf org display` is blocked in auto mode, so API 68.0 came from A's verified value.
- An empty `force-app` deploys with "No changes to deploy" and exit 0.
