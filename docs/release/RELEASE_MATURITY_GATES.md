# Codex Monitor — Release Maturity Gates

## Current

```text
PREVIEW-ONLY
```

Version 1.0.1 Preview may be Developer ID signed, notarized, stapled, and
distributed to ordinary macOS users. It must not be represented as a stable,
production-supported Codex integration: the app-server/WebSocket transport is
experimental/unsupported for production workloads and desktop-runtime
observation relies on undocumented local SQLite and rollout formats.

## 1.0.1 Preview distribution disclosure

Codex Monitor 1.0.1 Preview supports macOS 13 or later on Apple Silicon. It
requires Codex Desktop to be installed and the user to be signed in. It depends
on Codex local interfaces, so Codex updates can temporarily affect some
capabilities. Codex Monitor is not an official OpenAI product, is not a stable
production-supported Codex integration, and does not support Intel Macs.

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

Until a later review changes this decision, every packaging/release artifact
must identify itself as Preview-only and use the distribution disclosure above.
