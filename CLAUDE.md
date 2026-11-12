# CLAUDE.md: apex-platform-logging

Platform Event logging, persistence and Slack Block Kit alerts that plug into the ILogger and IAlertSink ports of apex-core-lib.

## Stack

- Salesforce DX source format, API 68.0, an unlocked package with no namespace.
- Depends on: apex-core-lib@1.1.0-1
- Standards plugin: `apex-standards`. Apply `apex-fflib-layers`, `apex-security` and `apex-testing` to all Apex, and run `apex-code-review` before opening a PR.

## Hard rules

1. **Clean-room.** No code, names, object models or data from any employer or client. The domain is fictional Orders / Shipments / Customers.
2. **No secrets.** No credentials, org IDs, usernames or URLs with tokens. Callouts use Named Credentials. gitleaks runs in pre-commit and CI.
3. **Bulk-safe and layered.** Selectors own SOQL, a Unit of Work owns DML, services are stateless, and nothing touches the database inside a loop.
4. **Secure by default.** Every class declares its sharing, and queries and DML run in user mode. Every exception is documented in ApexDoc and an ADR.
5. **Tests prove behaviour.** Stub API unit tests, a few real-DML integration tests, a 200-record bulk case and negative paths. Coverage is at least 90% as a floor, not a target.
6. **Done means:** CI green, zero High or Critical Code Analyzer findings, no `TODO`, ApexDoc on every public class, ADRs written, README complete, `docs/case-study.md` written.
7. **Free only.** No paid services or SaaS. Note each deliberate omission where a reader would look for it.

## Layout

`force-app/<feature>/{classes,objects,triggers,customMetadata,permissionsets,…}`. Organise by feature, not metadata type, wherever that helps a reader.

## Workflow

- Plan first: file tree, class list and test plan before code.
- Branch per feature, small Conventional Commits, PR into `main` even when working solo. Keep the `Co-Authored-By: Claude` trailer on AI-assisted commits.
- Before pushing: `npm run format:check && npm run lint && npm run analyze`.
- At the end of every session, update `handoff.md`.
