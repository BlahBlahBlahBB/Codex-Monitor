# Final Blocker Closure Report

## Conclusion

**NOT READY**

The scoped code fixes and automated regressions pass, but the exit gate explicitly makes real packaged-app human evidence authoritative. The required four-background orb check, packaged menu-bar popover screenshot, and packaged WORKING three-light screenshot have not yet been supplied by human QA. They are therefore recorded as **FAIL**, rather than inferred from code or tests.

## Build under test

- Source commit: `9047d08abbc0b5ff37a78949b11af3cb6c48a981`
- New independent build: `QA Builds/Codex Monitor Blocker Closure QA.app`
- Bundle ID: `local.codex.monitor.blocker-closure-qa`
- The bundle is ad-hoc signed and passed `codesign --verify --deep --strict`.

## Required gate matrix

| Item | Result | Actual evidence / disposition |
| --- | --- | --- |
| SETTINGS LIFECYCLE | **PASS** | The app now has no SwiftUI Settings scene. One retained `SettingsWindowController` owns `NSWindow`, `NSHostingController`, root view, selection, and preferences. Packaged-app inspection opened Floating, switched to General, closed, and reopened the same non-empty General detail. Automated regression executes the complete seven-section path for 30 cycles plus 10 reopen cycles for each menu entry path. |
| ORB TRANSPARENCY | **FAIL** | The new panel/host contract is transparent and a packaged-app crop shows a circular orb without a rectangle, but the mandatory human four-background pixel check (white, black, orange, two-color boundary) has not been completed. |
| ORB LIQUID GLASS DEPTH | **FAIL** | The glass body now uses native regular Liquid Glass on macOS 26+ with a circular-only edge highlight, semantic ring separation, and a circular shadow. It still requires the mandatory human visual judgment on real desktop backgrounds. |
| CONTEXT MENU LOCALIZATION | **PASS** | A real zh-Hans LaunchServices instance displayed: `刷新`, `用量`, `打开 Codex`, `始终置顶（不可用）`, `锁定位置（不可用）`, `隐藏悬浮窗`, `设置`, and `退出 Monitor`. |
| POPOVER LOCALIZATION | **FAIL** | The packaged zh-Hans smoke resolved `刷新 / 用量 / 设置`, and all popover keys are localized and regression-tested, but a packaged menu-bar popover screenshot has not yet been captured through human QA. |
| THREE-LIGHT SEMANTICS | **FAIL** | Presentation mapping and regression now enforce one active dot for Working/Thinking, the middle breathing dot for Waiting Approval, and the red third dot for Failed/Interrupted; a real packaged WORKING three-light screenshot is still required by the gate. |
| USAGE HOVER TOOLTIP | **PASS** | In the packaged zh-Hans Usage window, the 30 calendar-day chart exposed native Help for every day, including zero days, with localized date, exact Token count, and `$--` cost. |
| INVALID EPOCH FILTER | **PASS** | Packaged zh-Hans Usage displayed `重置 不可用` rather than a 1970 date. Regression verifies epoch/default timestamps map to `Unavailable` / `不可用`. |
| QUICK VIEW | **PASS** | The frozen placement and task-title sanitization behavior remains unchanged; its existing placement regression passes and no unsafe transcript content was reintroduced. |
| RUNTIME REGRESSION | **PASS** | `swift build` passed. `swift test` passed: 128 tests, 0 failures; three existing opt-in installed-path probes remained skipped. A packaged zh-Hans smoke observed Desktop runtime-to-UI Working propagation without modifying the runtime architecture. |

## Implemented closure changes

- Removed the competing SwiftUI `Settings` Scene. The AppKit delegate now owns the app lifecycle and its Application Settings command routes only to the canonical native Settings controller.
- Retained the Settings `NSHostingController` and presentation model; title-bar close orders out rather than leaving a retained, invalid content root.
- Replaced `NavigationSplitView` lifecycle-sensitive detail routing with a retained sidebar/detail root. All six sections always render backed controls or an explicit unavailable explanation.
- Enforced a pure three-light presentation contract: Idle/Completed are three steady green dots; Working/Thinking only dot 1 breathes green; Waiting Approval only dot 2 breathes yellow; error states only dot 3 is steady red; unavailable/paused dots are muted neutral.
- Added per-day native Help and restrained hover feedback to the existing authoritative 30-day Usage buckets. No Usage source or data semantics changed.
- Suppressed invalid/default reset epochs at presentation time only.
- Centralized final locale resolution in `L10n`, including packaged `-AppleLanguages` QA launches. No view-level language branching was added.
- Kept orb material, ring highlight, and shadow strictly circular; no rectangular glass, material, overlay, or panel shadow was introduced.

## Verification

- `swift build` — **PASS**
- `swift test` — **PASS** (128 passed, 0 failures, 3 existing opt-in skips)
- `git diff --check` — **PASS**
- Scoped regressions — **PASS**:
  - Settings full navigation/reopen lifecycle;
  - transparent orb host;
  - zh-Hans/English presentation keys;
  - exact three-light mapping;
  - zero-day Usage help text;
  - invalid epoch suppression.

## Remaining human QA required before this gate can change

1. Place the new orb over white, black/dark, orange, and a two-color boundary; verify every pixel outside the circle is transparent and the circular glass/shadow has depth.
2. Capture the zh-Hans menu-bar popover showing all localized labels.
3. Capture the packaged app during a real WORKING state so the menu bar visibly shows only dot 1 active/breathing.

Do not enter Luna, release, signing, or distribution while any row above remains **FAIL**.
