# Source Verified Blocker Fix v2

## Scope and result

This pass changed only the source-identified blockers in commit
`3712a5445a6ca8e41effbdfcf89bf6a154a576f6`. It did not reopen the monitoring
adapter/account/approval architecture, enter Luna, or perform Release work.

### Implemented source fixes

| Blocker | Implemented change | Verification state |
| --- | --- | --- |
| Orb rectangular backing | The Orb now uses `CircularVisualEffectView`, whose transparent host contains one `NSVisualEffectView` with a circular Core Animation mask, `.behindWindow`, and `.active`. The Orb no longer uses `glassEffect`, `GlassEffectContainer`, a rectangular material, or a root shadow. | Source + structural regression verified; desktop-background screenshot **NOT VERIFIED**. |
| Fixed-height Popover | `MonitorStatusItemController` measures the actual hosted content before every show, sets `NSPopover.contentSize` from that measured size, and replaces only the interior with a `ScrollView` when the visible screen height cannot fit it. AppKit remains the only placement owner. | Source + build verified; 50 real open/close frame observations **NOT VERIFIED**. |
| Double Popover glass | `MenuBarPopoverView` is now ordinary SwiftUI content inside the native `NSPopover`; it no longer adds `GlassSurface` or an inner shadow. | Source + build verified; visual chrome inspection **NOT VERIFIED**. |
| Fake geometry/alpha gates | Removed unused `PopoverAnchorLayout` and its geometry-only test. Removed `OrbTransparencyProbe` and its copied white/black/orange/split-colour alpha result. | Verified by source search and full tests. |
| Status tooltip | The status-item button is configured with `toolTip = nil`; no close callback restores it. | Source + build verified; live tooltip absence **NOT VERIFIED**. |
| Terminal expiry | `RuntimeStateEngine.nextPresentationTransitionDeadline()` supplies one next terminal deadline. `MonitorRuntimeStore` owns at most one cancellable sleeping task, republishes at expiry, and cancels/recomputes on every later mutation. A source-unavailable transition removes the deadline. | Deterministic no-new-event stream regression verified. |
| Reset epoch decode | Account rate-limit reset values now keep 10-digit Unix seconds and divide only 13+ digit millisecond values. | Fixture regression verified: `1_725_000_500` remains 2024-era Unix time. |
| Reset presentation | Reset count remains independent of reset time; zero remains `0`. Reset dates now use the resolved language locale. | Unit formatting verified; packaged rendered reset-date text **NOT VERIFIED**. |
| Usage formatting | Summary metrics use compact Chinese 万/亿 or English K/M/B values; chart tooltips retain exact decimal integer Token values. Usage axes omit the year and use the resolved language. | Unit regression verified. |
| Breathing | Active state indication has a 2.4-second opacity-only cycle. Idle/completed/error remain steady. | Mapping/source verified; visual cadence inspection **NOT VERIFIED**. |

The frozen approval-resolution capability remains `UNAVAILABLE`. No Approved,
Declined, or Cancelled state was synthesized.

## Test results

```text
swift build  PASS
swift test   PASS — 137 executed, 0 failures, 3 pre-existing opt-in local probes skipped
git diff --check  PASS
```

Focused new regressions cover:

- completed terminal → one-shot deadline → `IDLE` without another source event;
- completed deadline (5 seconds) and error deadline (15 seconds) derivation;
- cancellation of an outstanding terminal deadline on source unavailability;
- circular AppKit material host/mask contract;
- 10-digit reset timestamp preservation;
- reset localization, compact summary tokens, exact tooltip tokens, and year-free axes.

## Packaged QA artifact and real observations

Local ad-hoc-signed QA bundle (not Release/distribution):

`QA Builds/Codex Monitor Blocker Fix v2 QA.app`

`codesign --verify --deep --strict` passed.

The packaged executable was launched twice with its built-in smoke exit:

| Fresh launch | Packaged observation |
| --- | --- |
| System Chinese | `locale=zh-Hans`; localized `刷新 / 用量 / 设置`; runtime and UI both `COMPLETED`; desktop, usage, quota, and reset availability were all `available`. |
| English override | `locale=en`; localized `Refresh / Usage / Settings`; runtime and UI both `IDLE`; desktop, usage, quota, and reset availability were all `available`. |

These are real packaged-app startup and runtime-chain observations, not fixture
output. They do not establish visual appearance.

## Required visual QA status

The Computer Use service timed out repeatedly when attaching to this
LSUIElement app. Therefore the following are intentionally **NOT VERIFIED**,
not claimed fixed:

- Orb against white, black, orange, and split-colour desktops;
- complete Popover content and 50 real AppKit open/close frame checks;
- 5-second completed and 15-second error transitions as visually observed in
  the packaged UI (the runtime regression does verify the scheduler);
- idle/working dot and Orb breathing appearance;
- rightmost chart-tooltip clipping;
- live Chinese → English → Follow System updates across already-open surfaces.

The next human QA should exercise those items with the v2 QA bundle. In
particular, inspect actual desktop pixels rather than relying on the removed
corner-alpha probe.

## Status

No new P0/P1 source blocker was found in this constrained pass. Visual gates
listed above remain pending human/package observation, so this report does not
authorize Luna or Release.
