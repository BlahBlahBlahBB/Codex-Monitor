# Visual Host Fix v3

## Scope

This is a constrained visual-host closure from
`39a290ffc65e5598f6063df178bb0d15b312154e`. It does not alter runtime
adapters, account, approval, state architecture, Luna, or Release behavior.

## SOURCE VERIFIED

| Area | Source change |
| --- | --- |
| Orb material | `CircularVisualEffectHost` no longer has a `CAShapeLayer`, `layer.mask`, `masksToBounds`, or a material corner-radius clipping path. On every layout, it creates a transparent `NSImage` with an opaque white circle and assigns it to `NSVisualEffectView.maskImage`. The effect remains `.hudWindow`, `.behindWindow`, and `.active`. |
| Orb shadow | Removed the last SwiftUI Orb shadow. The panel remains non-opaque, clear, and shadow-free; the hosting view remains clear and has zero layer shadow. |
| Popover host | Removed the retained `popoverHost`, `setFrameSize(height: 1)`, and `fittingSize` measurement path. Every show now creates a new normal host, measures it with `sizeThatFits`, then installs either that host or a new scroll host. |
| Popover bounds | Maximum content height now derives from the status button's actual screen rectangle, the current `NSScreen.visibleFrame`, and a 32pt native arrow/chrome reserve. No popover window frame is manually set. |
| Popover scroll origin | Scrollable content is explicitly top-leading, including its outer fixed frame, so a new scroll host starts at the top on every open. |
| Usage date | Bucket dates are parsed as Gregorian calendar components and formatted in the same fixed UTC calendar/timezone. They are no longer converted through a UTC instant into the host timezone. |
| QA packaging | Added `Tools/package_visual_host_qa.sh`. It builds the executable, copies `CodexMonitorContracts_CodexMonitorApp.bundle` into `Contents/Resources`, creates the app plist, then ad-hoc signs and verifies the bundle. It refuses to overwrite an existing QA app. |

## AUTOMATED VERIFIED

| Check | Result |
| --- | --- |
| `swift build` | PASS |
| `swift test` | PASS — 137 executed, 0 failures, 3 pre-existing opt-in local probes skipped |
| `git diff --check` | PASS |
| Mask regression | PASS — a 90pt and then 180pt native effect host both receive a same-size `maskImage`; CALayer masking remains absent. |
| Calendar-date regression | PASS — the 2026-08-11 Chinese axis remains day 11 while the process default timezone is set to Asia/Shanghai, America/Los_Angeles, and America/New_York. |
| Package syntax | PASS — `zsh -n Tools/package_visual_host_qa.sh`. |
| Resource bundle | PASS — the generated QA app contains `Contents/Resources/CodexMonitorContracts_CodexMonitorApp.bundle/{en.lproj,zh-hans.lproj}`. |
| External package smoke | PASS — a `ditto` copy in `/private/tmp` launched with Chinese and English overrides and resolved `刷新 / 用量 / 设置` and `Refresh / Usage / Settings` respectively. |
| No-development-bundle smoke | PASS — the workspace `.build` was moved to an isolated temporary directory for the duration of one packaged Chinese smoke run, then restored. The copied app still resolved Chinese resources and the local runtime/model chain. |
| Current Orb screenshot | An actual UI-automation capture on the current white desktop showed only the circular Orb boundary; no rectangular backing was visible in that one environment. This is automated evidence only, not the required multi-background human gate. |

## HUMAN NOT VERIFIED

The following are intentionally not marked fixed or passed:

- Orb screenshots on pure white, pure black, pure orange, and split black/white
  desktops, with visual confirmation that all four outside corners equal the
  untouched desktop;
- Status Popover open/close at iterations 1, 2, 3, 5, 10, and 20, with the
  header at the top, account block visible, all actions visible, and no large
  top blank region;
- actual `NSPopover` window-frame recordings proving each frame is contained
  in the current `visibleFrame`.

The automated UI service can inspect the LSUIElement Orb but does not expose a
reliable status-item/NSPopover attachment surface for the required 20-cycle
exercise. These remain manual packaged-App QA obligations.

## QA Artifact

Local ad-hoc-signed artifact (not Release/distribution):

`QA Builds/Codex Monitor Visual Host Fix v3 QA.app`

Use this exact bundle for the remaining human visual gate. Do not use the
previous v2 bundle.

## Status

No new source-level blocker was found in the restricted v3 scope. The remaining
visual host acceptance is deliberately pending human QA; this report does not
authorize Luna or Release.
