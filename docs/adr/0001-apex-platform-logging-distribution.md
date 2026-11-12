# ADR 0001: Ship apex-platform-logging as its own unlocked package on top of apex-core-lib

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** Chad Countryman

## Context

`apex-core-lib` (A) owns the ports: `ILogger` (`debug`, `info`, `warn`, `error(String, Exception)`, `flush`) and `IAlertSink` (`send(List<Alert>)`). Its defaults are `DebugLogger` and `NoOpAlertSink`, so A runs with no logging infrastructure at all. This repo (B) provides the real adapters: a Platform Event logger, persistence to a custom object, and Slack alerts. C (`apex-event-ingestion`) and F (`agentforce-action-pack`) log through `ILogger` and must not need B to compile or to pass their tests.

Constraints:

1. B must install into an org that already has A, and pin A's version (`1.0.0-1`, `04tak000000u0zpAAA`).
2. Swapping the adapter in must need no change to A or to any consumer's code, only configuration (`DI_Binding__mdt`, ADR 0004 in A).
3. The free Developer Edition Dev Hub allows 6 package version creates per rolling 24 hours, shared with A's releases.

## Options

1. **Own unlocked package, no namespace, depending on `apex-core-lib@1.0.0-1`** (chosen). For: it is dependency inversion made visible. A defines the ports, B is an optional adapter package installed on top, and the binding rows B ships switch A's defaults over with no code change anywhere. B is versioned and pinned the same way as A (A's ADR 0001), and C and F stay free of any dependency on B. Against: each release spends one of the 6 daily package version creates. B's `DI_Binding__mdt` records are rows of a type that A defines, so the package build has to accept cross-package Custom Metadata records. The deploy proves that in a scratch org, and the first package build proves it fully. Without a namespace, B's public surface is governed by ApexDoc `@group Public API`, not the compiler.
2. **A source-only repo with no package.** For: no `release.yml`, no package builds, a simpler quick start. Against: a consumer can't "install logging". They would have to copy source, which is the copy-paste reuse these repos argue against, and nothing pins B's version.
3. **Add the adapters to A as another module.** For: one install. Against: A would then depend on Platform Events, a custom object and Slack, and every consumer would carry them. That reverses the ports-and-adapters boundary A was designed around (A's ADR 0002).

## Decision

Option 1: an unlocked package with no namespace that declares `apex-core-lib@1.0.0-1` as its dependency, because it keeps A's ports free of infrastructure and lets an org opt into the adapters through configuration alone.

## Consequences

- `sfdx-project.json` pins A with `packageAliases` (`apex-core-lib@1.0.0-1` → `04tak000000u0zpAAA`). `scripts/org-setup.sh` installs it before the deploy, locally and in CI.
- Upgrading A is a PR in this repo that changes the alias, and the CI scratch org proves it.
- `release.yml` builds a beta on a `vX.Y.Z` tag. Promotion is manual and irreversible. A tag is pushed only with the owner's approval.
- Rollback: uninstall B, or deactivate its `DI_Binding__mdt` rows. Either way A falls back to `DebugLogger` and `NoOpAlertSink` with no deploy of A.
- Revisit if C or F need a logging feature that only B provides (that would argue for a port in A, not for a dependency on B), or if build allocations stop being a constraint.
