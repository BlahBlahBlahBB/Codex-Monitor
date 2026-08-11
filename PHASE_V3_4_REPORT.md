# PHASE V3-4 REPORT — Product Integration

## Result

PASS — Codex Monitor is now a runnable macOS App whose UI consumes the stable
`MonitorRuntimeSnapshot` boundary only.

## Implemented

- Added the `CodexMonitorApp` macOS SwiftUI executable target.
- Added `MonitorAppModel`, a MainActor observable bridge from
  `MonitorRuntimeStore` to SwiftUI. It has no SQLite, rollout, log, RPC, or
  adapter dependency.
- Added a basic debug window displaying current state, thread/turn attribution,
  session token, usage/quota/reset, source health, and all product capability
  availability values.
- Added a basic floating status panel/orb driven by the same observable model.
  It renders offline/source unavailable, idle, working, thinking, waiting
  approval, failed, interrupted, and completed product states without any final
  Liquid Glass styling work.
- Added `CodexLocalMonitorDriver`: one actor-owned, bounded two-second local
  loop that discovers at most 12 recent state-DB threads, opens exact rollout
  bindings, and feeds incremental observations into `MonitorRuntimeStore`.
- Added sleep/wake handling. Sleep pauses runtime projection; wake sets a
  reconciliation requirement and safely reboots the local binding path.
- Added bounded `StateDBReader.recentThreads` discovery. It returns only the
  existing allow-listed metadata and still requires `DesktopLocalAdapter.open`
  exact rollout/session admission.
- Added snapshot presentation equivalence so sampling timestamps alone do not
  trigger UI refreshes.

## UI/runtime boundary

```text
Codex local state DB + admitted rollout
    -> CodexLocalMonitorDriver (background actor)
    -> MonitorRuntimeStore
    -> MonitorAppModel (MainActor)
    -> SwiftUI debug window + floating status panel
```

The UI does not import or use local adapters, SQLite, rollout files, logs, or
RPC. All unavailable values render their availability state; they are never
converted to zero, false, empty, or completed.

## Real macOS smoke test

The actual `CodexMonitorApp` was built and launched against the current local
Codex Desktop data sources for six seconds, then auto-exited through its
smoke-only environment hook. The emitted result was:

```text
CODEX_MONITOR_SMOKE runtime=WORKING ui=WORKING activity=tool
threads=12 desktop=available token=9487844 usage=unknown quota=unknown
uiUpdates=5
```

This confirms a real local chain from Codex Desktop data to runtime to the App
observable model and running UI. The snapshot showed the active task as
`WORKING` with tool activity, 12 bounded local threads, a live session-token
value, and an available Desktop source.

The current implementation turn remained active while the smoke ran, so an
independent real idle/completed transition could not be captured in the same
turn without creating unrelated Codex work. Existing state-engine and product
binding tests cover completed, failed, interrupted, and recovery projection.
This is a QA-capture gap, not a product or capability blocker.

## Waiting Approval and approval resolution

- The UI correctly renders `WAITING_APPROVAL` when the runtime emits it; the
  product-binding test covers the live App Model path.
- `approvalResolution` remains explicitly `UNAVAILABLE` with the existing
  external Codex Desktop capability reason.
- No resolution event is consumed, inferred, fabricated, or displayed as
  Approved/Declined/Cancelled.
- The local app driver deliberately leaves an unconfigured approval source as
  unavailable rather than replaying historic requests and mislabeling them as
  pending. The existing runtime fallback remains intact.

## Usage, quota, reset, and token

- Session token is shown from admitted rollout data when fresh; the real smoke
  displayed `9487844`.
- Usage, quota, and reset fields are present in the UI contract and show their
  availability state. The V3-4 App driver does not add a new account-RPC
  scheduler, so the real smoke correctly displayed `unknown` for usage/quota.
- No unavailable value is fabricated as a numeric default.

## CPU/polling behavior

- Exactly one driver task is created; `start()` is idempotent and `stop()`
  cancels it and unregisters sleep/wake observers.
- The driver performs bounded discovery plus incremental rollout polling every
  two seconds, not busy polling or whole-history scanning.
- The App Model has one one-second snapshot observation task. It performs an
  actor snapshot read only, and presentation-equivalent snapshots do not cause
  a published UI refresh.
- File/database work remains actor-owned off the MainActor.

## Tests and verification

- Added `MonitorAppModelTests`:
  - runtime -> observable state -> UI model mapping;
  - duplicate/timestamp-only snapshot suppression;
  - working, failed, waiting approval, source unavailable, and unavailable
    approval-resolution presentation.
- `swift build` — passed.
- `swift test --filter 'MonitorAppModelTests|MonitorRuntimeTests'` — 8 passed.
- `swift test` — 115 executed, 0 failures, 3 pre-existing environment-gated
  production-path tests skipped.
- `git diff --check` — passed.

## Remaining blocker

No implementation blocker for V3-4.

The deliberately unavailable approval-resolution capability remains an external
Codex Desktop limitation. Account read scheduling is a bounded next-stage
integration item; the current UI transparently reports account fields as
unknown until it exists.

## Suggested next phase

Integrate the validated account/read, rate-limit, and usage snapshot producer
behind the existing runtime boundary, then replace the debug window/orb styling
with the approved production visual system. Do not alter the approval-resolution
contract unless Codex Desktop exposes a reliable source.
