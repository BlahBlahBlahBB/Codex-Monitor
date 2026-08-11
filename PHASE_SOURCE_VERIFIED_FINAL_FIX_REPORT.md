# Source-Verified Final Fix

Date: 2026-08-11

Scope: only the frozen final-fix items. No adapter/protocol/OAuth/approval-resolution work was performed. This is not Luna, Release, signing, or distribution work.

| Area | Root cause | Code change | Automated evidence | Packaged app evidence | Result |
| --- | --- | --- | --- | --- | --- |
| STATE DELIVERY | `MonitorAppModel` read `runtime.snapshot()` on a one-second loop. | Added `MonitorRuntimeStore.snapshots()` with immediate current-snapshot yield and post-mutation publication; app model now consumes `for await`. | `testSnapshotStreamImmediatelyYieldsThenDeliversMutation`; full suite 136 passed. | Real app moved between Thinking/Working without a manual refresh. | Fixed. |
| STALE THREAD HEALTH | Desktop health used aggregate historical freshness as a presentation veto. | Current representative thread freshness now owns desktop presentation health; lane health is used only with no current thread. Current unknown freshness remains fail-closed unavailable. | `testOldUnavailableThreadDoesNotPoisonFreshRepresentativeIdleThread` and steady-idle presentation regression. | Runtime remained truthfully Working/Thinking while current source was live. | Fixed. |
| IDLE BREATHING | A retained `repeatForever` state could outlive a state transition. | Existing presentation-only `TimelineView` remains instantiated only while `presentation.breathes`; no View stores breathing state. | Exact idle matrix regression passes. | Live working Orb uses only opacity breathing; idle requires the same tested zero-timeline branch. | Fixed; final human QA checks the real idle frame. |
| TRANSIENT RED | A stale visual animation could survive a terminal-to-new-turn transition. | All state surfaces read the app model’s one `VisualStatePresentation`; no retained red visual state exists. | Existing engine new-turn override plus product matrix regression pass. | Working/Thinking appeared blue/green, without an observed red transition during QA. | Fixed. |
| WORKING BLUE ORB / STATUS DOT MATRIX | Views previously derived presentation independently. | Model now exposes one presentation projection used by Orb, Capsule, Popover, Quick View, and Diagnostics. | `testVisualStatePresentationIsTheExactSingleSurfaceMatrix` and idle/working tests pass. | Packaged Orb was blue for real Working/Thinking. | Fixed. |
| ORB COMPOSITOR | Rectangular root clipping/shadow could force offscreen rectangular composition. | Removed root `clipShape`/shadow; shadow belongs only to the circular glass body. Existing transparent panel/host alpha diagnostics remain active. | Orb transparency and four-background rendered-corner probe tests pass. | Packaged app visual observation showed no rectangular backing. | Fixed with native Circle glass path (A); AppKit-material fallback was not needed. |
| ORB GLASS DEPTH | The root effect had unnecessary rectangular compositing risk. | Glass remains directly on `Circle`; circular-only restrained shadow separates the body without a panel-bound shadow. | Layer-tree and alpha probe contracts pass. | Circular glass object remained distinct from the desktop with no square material. | Fixed. |
| LOCALIZATION COLD LAUNCH | Surface-local locale copies could start before synchronized resolution. | `LocalizationController` normalizes Follow System Chinese variants to `zh-Hans`, resolves before UI creation, and owns every SwiftUI root via `LocalizedRoot`. | zh-Hans/zh-CN/zh-SG resolution tests pass. | Fresh `zh-Hans` app launch: Settings sidebar/detail, context menu, and Usage were Chinese on first open. | Fixed. |
| LOCALIZATION LIVE CHANGE | AppKit and SwiftUI roots did not share a live observable owner. | All surface roots bind one controller and reset identity on resolved-language change; AppKit menu rebuild remains controller-fed. | Localization contracts and 30-cycle Settings lifecycle pass. | Cold-launch evidence above; language-toggle change is left to final human QA, not fabricated. | Ready for final human QA. |
| POPOVER POSITION | Code mixed native popover placement with manual internal-window `setFrame`. | Removed manual frame override; `NSPopover.show` exclusively owns anchoring and edge avoidance. | 50-cycle geometry/reopen regression remains green. | No source-side stale-origin mutation remains. | Fixed. |
| SLIDER | `step: 1` created dense native ticks and non-continuous tracking. | Slider is continuous; display rounds only the label. Existing preferences debounce disk persistence and preserve panel center. | Slider single-track and center-preservation tests pass. | Packaged Floating Settings displayed one native Slider and value row. | Fixed. |
| ORB RESIZE | Must preserve center and avoid rebuilding the panel. | Existing center-preserving `applyPreferences` path is retained; size persistence remains debounced. | Center-preserving layout test passes. | Existing floating host is retained on preference changes. | Preserved. |
| USAGE TOOLTIP | Clamp assumed 132 pt while fixed-size text could exceed it. | Tooltip has one bounded 188×62 rendered frame, no horizontal `fixedSize`; clamp uses that actual frame. | Far-left/far-right/top/bottom clamp regression passes. | Usage opens with real data; per-bar hover remains a final human QA check. | Fixed. |
| USAGE DATE AXIS | Must remain derived from the current 30-day buckets. | Existing first/last bucket axis and pointer `chartOverlay` mapping retained. | Pointer mapping and zero-day selection tests pass. | Usage UI exposes real 30-day history. | Preserved. |
| SETTINGS | Need one canonical controller and stable sections. | Shared localization root wraps the existing single retained Settings controller; no new Settings owner was introduced. | 30 section/reopen cycles and popover/context routes pass. | First-open Chinese sidebar/detail observed. | Preserved. |
| QUICK VIEW | Must consume snapshot/presentation and never expose raw content. | Quick View now consumes `model.presentation` and live localization root; title sanitizer remains unchanged. | Quick-view placement and unsafe-title tests pass. | Native click route remains present; accessibility automation could not expand the panel, so no false visual assertion is made. | Ready for final human QA. |
| RESET SEMANTICS | Zero and unavailable must remain distinct. | No data-source change; UI retains only authoritative `count` and separately displays unavailable reset details/time. | Account mapping and stale-data tests pass. | Packaged Usage showed reset credit `0` and reset time `不可用` simultaneously and correctly. | Preserved. |
| RUNTIME REGRESSION | Event delivery and presentation changes risked frozen behavior regressions. | All changes remain above validated adapters/state evidence; approval resolution remains unavailable. | `swift build`, `swift test`: 136 passed, 0 failed, 3 existing opt-in local probes skipped; `git diff --check` passed. | Real packaged runtime observed localized Working/Thinking and live quota. | No regression found. |

## QA artifact

- New local QA package: `QA Builds/Codex Monitor Source Fix QA.app`
- Existing structured diagnostics categories remain: state, presentation, localization, settings, popover, usageChart, orbHost.
- Diagnostics continue to omit OAuth/API keys/auth tokens/email/prompts/transcripts/system and developer messages.

## Conclusion

READY FOR FINAL HUMAN QA

No Luna or Release work was entered.
