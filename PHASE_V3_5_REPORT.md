# V3-5 Full Product Functional Integration

## Result

PASS — scoped product integration completed. The existing local-first,
read-only monitor snapshot is now consumed by a usable macOS product shell.
No V3-1 through V3-4 monitoring contract was reopened.

## Implemented

- A persistent, floating NSPanel status orb driven only by
  MonitorAppModel.snapshot.
- Dragging through the native floating panel, user-configurable 72–180 pt
  size, persisted size and origin, screen-edge clamping, and basic
  multi-display recovery.
- Click-to-toggle read-only quick view. It places itself beside the orb
  (right on the left half of a display, left on the right half), vertically
  centers where possible, and remains inside the visible frame.
- Menu bar actions for Usage, Settings, show/hide floating window, Open
  Codex, and Quit. The Usage and Settings entries are independently
  user-configurable.
- A basic Settings scene for floating-window visibility, size, and menu
  entry visibility. All four settings persist in UserDefaults; size applies
  immediately.
- Main window and quick view now show state, session/thread attribution,
  Session Token, Usage, Quota, Reset, source health, and capability
  availability. Missing values are rendered as UNKNOWN or UNAVAILABLE;
  they are never rendered as zero, empty success, or completed.

## Capability outcome

- Available when observed locally: Desktop state/activity, session/thread
  attribution, Working/Thinking/terminal state mapping, Session Token, and
  source health.
- Waiting Approval remains wired into the orb, main view, quick view, and
  snapshot presentation. Its existing detection contract is retained.
- Approval resolution remains explicitly UNAVAILABLE with its existing
  external-Codex-Desktop capability reason. No resolution value is inferred
  or fabricated.
- Usage, Quota, and Reset are currently UNKNOWN in the real local runtime.
  The project has account transport contracts but no currently validated,
  reusable read-only account producer in the app runtime. This phase did not
  extend private-protocol work or invent percentages/reset times.

## Real local smoke

The app was launched with a six-second automatic exit. It observed the active
Codex Desktop session through the real local source:

    CODEX_MONITOR_SMOKE runtime=WORKING ui=WORKING activity=tool threads=12
    desktop=available token=13769538 usage=unknown quota=unknown reset=unknown
    uiUpdates=5

This confirms the live Codex Desktop → local source → MonitorRuntime →
MonitorAppModel → SwiftUI path and the honest account-field presentation.
The app was also launched without auto-exit for a native-window check.

The V3-5 persistence and geometry tests cover restored position/size,
edge-safe placement, left/right quick-view placement, and settings
restoration. Pointer-driven dragging and a physical Codex Desktop restart
were not automated in this active Codex Desktop session: restarting it would
interrupt the task itself, and the unbundled SwiftPM executable is not
discoverable by the available desktop accessibility driver. Existing runtime
reconnect/pause-resume regressions remain passing. These are release-QA
follow-ups, not a new monitoring capability blocker.

## Validation

- swift build — passed.
- swift test — passed: 118 tests, 0 failures, 3 environment-gated local
  production probes skipped.
- git diff --check — passed.
- New high-value product tests:
  - preferences persistence and size clamping;
  - restored floating-window edge constraint;
  - quick-view side selection and clipping protection.
- Existing UI-model tests still cover runtime changes, duplicate snapshot
  suppression, Waiting Approval, source unavailability, capability
  unavailability, and state presentation.

## Performance / lifecycle

The UI reads the runtime snapshot on a one-second actor cadence and suppresses
presentation-equivalent updates. The local driver remains the existing
bounded two-second read-only source cadence; no source I/O is performed on
the main actor and no per-refresh timers/tasks are added. Driver start is
idempotent, and the existing restart/reconciliation behavior remains in the
runtime layer.

## Blockers and next phase

There is no implementation blocker for this scope. The only unavailable
product data is Usage/Quota/Reset until a separately validated read-only
account source is deliberately added; approval resolution remains intentionally
unavailable.

Next phase recommendation: conduct normal manual release QA for drag/resize,
app restart, and a user-controlled Codex Desktop restart, then move to the
separate visual-design phase. Do not reopen the approval-resolution work.
