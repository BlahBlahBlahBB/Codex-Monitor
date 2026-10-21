# Codex Monitor — Release Maturity Gates (Historical v1.0.1)

> This file records the release-maturity decision made for v1.0.1. It is **not** an up-to-date approval or prohibition for the current v1.0.12 artifact. See the [main README](../../README.md) and the [v1.0.12 GitHub Release](https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/v1.0.12). The current artifact is a publicly downloadable **Preview**, signed ad-hoc and **not Apple-notarized**; it is not a stable, officially supported Codex integration.

## Recorded maturity status (v1.0.1)

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

At the time this decision was recorded, future packaging/release artifacts were required to retain Preview-only disclosures until a subsequent maturity review. This historical restriction must not be mistaken for a claim that v1.0.12 was notarized or that its published Preview status constitutes stable production support.
