# PHASE_V3_1_REPORT

```text
Phase: V3-1 — DesktopLocalAdapter
Authorization: PASS — AUTHORIZE PRAGMATIC V3 IMPLEMENTATION
Date: 2026-08-10
Scope: Desktop-local observation foundation only
Result: PASS — V3-1 IMPLEMENTATION COMPLETE; DO NOT ENTER V3-2 IN THIS PHASE
```

## Delivered

- `StateDBReader` opens the selected `state_5.sqlite`-style source only with
  `SQLITE_OPEN_READONLY`, validates a caller-pinned user version and the exact
  `threads` query columns, and uses a bounded SQLite busy retry.
- `DesktopLocalAdapter` admits a thread only through a validated source root,
  exact state-DB thread-to-rollout path, then matching `session_meta.payload.id`.
  It namespaces thread, turn and item IDs with `DesktopLocalSourceID`.
- `RolloutIncrementalReader` maintains device/inode, byte offset and mtime;
  performs a bounded header/tail bootstrap; reads later appends only; buffers a
  partial final JSONL line; and fail-closes on file loss, truncation,
  replacement, session mismatch, and consumed-field type mismatch.
- The rollout allow-list retains only closed activity categories, opaque IDs,
  model/reasoning effort, timestamps and numeric token facts.  It does not
  retain message, reasoning, command, output, patch, approval, credential or
  path content in observations.
- Session Token is per selected rollout/thread: cumulative
  `total_token_usage.total_tokens` is emitted directly, duplicate totals are
  deduplicated, and `last_token_usage` remains a non-additive last-call fact.
  `threads.tokens_used` is read only as same-thread metadata/cross-check.
- Source health uses PID plus process-start epoch and selected-file ownership.
  Epoch mismatch or source/writer loss emits unavailable source evidence only;
  there is no terminal-state synthesis and no Codex lifecycle action.

## Retained regression coverage

`DesktopLocalAdapterTests` covers exact DB/path/session admission and mismatch,
two-thread timestamp/token isolation, one terminal thread alongside another
active thread, token deduplication, partial JSON append, truncate/replacement,
archive move rebind, PID reuse, writer/source loss, long silence, scoped schema
failure, bounded busy handling, read-only DB/session behavior, privacy-safe
observations, and adapter shutdown with no process signal/kill path.

## Verification

```text
swift build                         PASS
swift test                          PASS — 60 tests, 0 failures
swift test --filter DesktopLocalAdapterTests
                                    PASS — 14 tests, 0 failures
git diff --check                    PASS
```

SwiftPM needed to run outside the workspace sandbox because its own manifest
sandbox cannot start inside the managed sandbox; this did not change the
implementation scope.

## Explicitly not implemented

No old H2 custom WebSocket work was added or restored. This phase contains no
State Engine/reducer, Waiting Approval adapter or Accessibility, Account/Quota/
Usage/Reset, Monitor SQLite history, UI, notifications, or Codex Desktop
launch/restart/kill/resume/fork control.

## Stop condition

V3-1 stops at the scoped local commit for this implementation and report.
V3-2 has not been started.
