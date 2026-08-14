# Codex Monitor — Release Maturity Gates

## Current

```text
INTERNAL / DEVELOPER ONLY
```

## Architecture readiness and release readiness are separate

A technically functioning internal build does not imply:

```text
Beta ready
Public release ready
Production supported
```

## Before any Beta/Public review

At minimum re-review:

```text
official app-server/transport maturity
selected transport provenance
owned-runtime lifecycle completeness
approval capability if advertised
terminal outcome capability if advertised
Session Token semantics if advertised
multi-Thread if advertised
reconnect/reattach if advertised
Desktop source classification if shown
privacy/security
reset mutation if enabled
migration safety
support/disclosure wording
```

A later Sol review must explicitly output a new release-maturity decision.

Until then every packaging/release artifact must say Internal/Developer only.
