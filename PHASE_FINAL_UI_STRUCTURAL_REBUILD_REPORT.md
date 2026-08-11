# Final UI Structural Rebuild Report

## Conclusion

**READY FOR STRUCTURAL VISUAL QA**

## Final implementation commit

`f8bb63181f8a045ff314f7ab5e5693aed2a0a408` — `feat: rebuild native monitor surfaces`

## Implemented and retained

### Replaced presentation / native host wiring

- Replaced the `MenuBarExtra` circle icon with one fixed-width `NSStatusItem` custom B capsule (48 × 22 pt, three 7 pt dots, retained light outline) and one transient `NSPopover`.
- Rebuilt the popover into the approved three blocks: runtime/activity/update; account/plan/quota/reset; Usage/Settings/Floating/Open Codex/Quit actions.
- Rebuilt Orb presentation as a transparent, borderless `NSPanel` with no panel shadow, circular native material, 90%-diameter state ring, and authoritative remaining quota (`--` when unavailable).
- Rebuilt Quick View content to the approved read-only hierarchy at 350 pt, while retaining the verified single-click, side selection, screen clamping, no-duplicate, and drag-close behavior.
- Added a real Orb `NSMenu` context menu in the approved grouping. Always on Top and Lock Position are explicitly disabled as unavailable because they do not have frozen backing preferences.
- Added reusable native `NSWindow` controllers for Usage, Settings, and secondary read-only Diagnostics. Usage and Settings use real traffic lights and hidden title text.
- Rebuilt Settings as a native sidebar/detail window. The four existing persisted preferences retain native switch/slider bindings; unsupported settings areas disclose unavailability rather than pretending to work.
- Moved the former dashboard role out of the primary app flow. Diagnostics is now an Advanced secondary window.
- Added semantic Light/Dark materials plus Reduce Motion/Reduce Transparency behavior without changing component topology.

### Retained functional baseline

- `MonitorRuntime`, State Engine, Desktop/Approval local adapters, snapshot-only UI data flow, and approval-resolution capability contract.
- Session Token attribution, Waiting Approval detection, state priority and completion retention.
- Existing monitor restart/reconnect/sleep-wake architecture.
- Floating window drag, direct resize, 72...180 pt clamp, display-edge clamp, persisted origin/size, app relaunch restoration, and Quick View placement algorithm.
- Existing normal `NSWorkspace` Open Codex behavior; Monitor exit does not manipulate Codex lifecycle.

## A–J structural parity self-check

| Area | Result | Implemented native structure |
|---|---|---|
| A. Menu Capsule | **PARITY PASS** | `NSStatusItem` custom outlined B capsule. |
| B. Menu Popover | **PARITY PASS** | One anchored `NSPopover` with the three approved blocks. |
| C. Floating Orb | **PARITY PASS** | Transparent `NSPanel` → circular material → state ring → remaining quota/`--`. |
| D. Quick View | **PARITY PASS** | No-arrow `NSPanel`, exact compact information order, no controls. |
| E. Context Menu | **PARITY PASS** | Real `NSMenu`; unsupported stateful entries disabled truthfully. |
| F. Usage | **PARITY PASS** | Reusable native `NSWindow`, ordered sections, 2×2 metrics, truthful history-empty chart state. |
| G. Settings | **PARITY PASS** | Reusable native sidebar/detail `NSWindow`, native toggles and slider. |
| H. Diagnostics | **PARITY PASS** | Secondary read-only native window, no primary dashboard role. |
| I. Light Mode | **PARITY PASS** | Same topology with semantic native material and contrast. |
| J. Dark Mode | **PARITY PASS** | Same topology with semantic native material and contrast. |

## Functional regression and targeted checks

- `swift build` — PASS.
- `swift test` — PASS: 120 tests passed; 3 existing local-path tests skipped only because their opt-in environment paths were not supplied.
- `git diff --check` — PASS before commit.
- Added high-value structural tests for fresh 90 pt Orb default, transparent/no-shadow host contract, 350 × 214 Quick View contract, and duplicate surface ownership.

## Real runtime smoke

The packaged QA build was launched against the real local monitor path with a bounded smoke exit. Observed output:

```text
runtime=WORKING
ui=WORKING
activity=tool
threads=12
desktop=available
token=26959084
usage=unknown
quota=unknown
reset=unknown
uiUpdates=3
```

This proves the real chain remained connected:

```text
Codex Desktop local source → MonitorRuntime → MonitorAppModel → native app surfaces
```

## Truthful unavailable capabilities

- Approval resolution remains **UNAVAILABLE**; no Approved/Declined/Cancelled UI was added.
- The smoke host exposed no authoritative Usage, Quota, or Reset values, so the product renders `UNKNOWN`/`UNAVAILABLE` and Orb center `--`, never `0` or fabricated metrics.
- Authoritative account identity/plan and 30-day history are not supplied by the current runtime snapshot and remain `UNKNOWN`/unavailable.
- Always on Top and Lock Position have no backed persisted feature in the frozen baseline and are disabled in the native context menu.

## QA application

[`Codex Monitor Structural QA.app`](QA%20Builds/Codex%20Monitor%20Structural%20QA.app)

The package is a real local app bundle containing the current executable, an accessory-app Info.plist, and an ad-hoc signature. It is for structural visual QA only, not a release build.

## Next step

Run manual structural visual QA against the approved v1.9 reference in Light/Dark and accessibility appearances. Do not enter visual-polish or release work until that review passes.
