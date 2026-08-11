# PHASE V3-3 REPORT — Monitor Runtime / View Model Integration

## Result

PASS — V3-3 implementation completed.

## Implemented

- Added `MonitorRuntimeStore`, an actor-isolated, passive runtime projection layer.
  It performs no Codex I/O, starts no polling loop, and exposes one coherent
  `MonitorRuntimeSnapshot` for UI consumption.
- Added UI-facing view models for current state, representative thread/turn
  attribution, per-thread state, session tokens, usage, quota, reset
  information, source health, and capability availability.
- Extended the reducer snapshot with exact active-turn attribution and explicit
  session-token availability. No turn or token is inferred from title/status.
- Added stale-data protection for account snapshot values. Expired usage,
  quota, and reset data are withheld and marked `STALE`, not displayed as
  current values.
- Integrated pause/reconciliation lifecycle so UI receives stale/paused state
  until an atomic reconciliation installation returns the runtime to live.
- Kept the existing reducer's exact tool-completion fallback. The runtime store
  intentionally does not consume `ApprovalResolved` observations.

## UI contract now available

`MonitorRuntimeSnapshot` gives the UI one stable boundary with:

- Current `THINKING`, `WORKING`, `WAITING_APPROVAL`, `COMPLETED`, `FAILED`,
  `INTERRUPTED`, `IDLE`, `DISCONNECTED`, or `PAUSED` state.
- Current source/thread/active-turn attribution and all projected threads.
- Waiting-approval count and per-thread approval-source health.
- Session-token cumulative value plus provenance, only while fresh and
  available.
- Usage, primary/secondary quota windows, and reset information with explicit
  availability instead of fabricated defaults.
- Desktop-local, approval-local, and account source health.
- A product-level capability map, so presentation never needs to understand
  SQLite, rollout files, logs, RPC, or reducer fallback details.

## Capability status

Available when their corresponding local source is fresh:

- State projection and current thread/turn attribution.
- Thinking, working, waiting approval, completed, failed, and interrupted
  projection from the existing state engine.
- Session token from admitted rollout data.
- Usage, primary quota, and reset-credit count when the account snapshot route
  exposes validated snapshot fields.

Explicitly unavailable by default:

- `approvalResolution` — `UNAVAILABLE` with reason
  `EXTERNAL_CODEX_DESKTOP_CAPABILITY`. The runtime store does not synthesize
  Approved, Declined, or Cancelled and does not consume resolution events.
- Secondary quota and reset details, unless a future host supplies a validated
  capability configuration for them.

Unavailable, stale, and unknown sources are represented directly. No zero
token count, zero quota, empty reset data, or terminal result is fabricated.

## Runtime behavior

- Actor isolation keeps snapshot construction off the UI thread when callers
  feed it from a background task.
- The store is passive: the host can use existing incremental local readers and
  avoid high-frequency polling.
- Source loss degrades to `DISCONNECTED`/unavailable without crashing.
- Pause, sleep/wake, and restart paths remain stale until exact reconciliation
  is installed; the existing local adapter/reconciliation installer handles
  rebind and recovery.
- A representative-thread switch preserves exact attribution and does not mix
  state or tokens between threads.

## High-value tests added

- State, attribution, token, usage/quota/reset, and capability snapshot mapping.
- Source-unavailable fail-closed behavior without retaining a current token.
- Pause/reconciliation stale protection and recovery.
- Frozen unavailable approval-resolution contract plus tool-completion fallback.
- Stale account snapshot suppression.
- Representative thread switching without cross-thread attribution.

## Verification

- `swift build` — passed.
- `swift test --filter MonitorRuntimeTests` — 6 passed.
- `swift test` — 113 executed, 0 failures, 3 pre-existing environment-gated
  production-path tests skipped.
- `git diff --check` — passed.

## Real blocker

No implementation blocker.

Approval-resolution remains an external Codex Desktop capability limitation,
not a V3-3 blocker. This phase does not reopen, infer, or extend it.

## Suggested next phase

Wire `MonitorRuntimeStore.snapshot()` into the macOS app's existing data
controller/view binding, using the current local-reader scheduling policy. Do
not expand approval-resolution capability until Codex Desktop publishes a
reliable source.
