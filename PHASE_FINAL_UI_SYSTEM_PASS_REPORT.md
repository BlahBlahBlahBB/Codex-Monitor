# Final UI System Pass Report

## Conclusion

**READY FOR GLOBAL VISUAL & INTERACTION QA**

## Implementation commit

`ff9c89f1651d3fb2abc433f211d2c2ca42fc4cfd` — `feat: add liquid glass ui system pass`

## UI-system audit and fixes

| Area | Finding | Result |
|---|---|---|
| Liquid Glass | Previous surfaces used `NSVisualEffectView` with manual opacity, border, and shadow as the primary material. | macOS 26+ now uses real `glassEffect(_:in:)`, `Glass.clear` / `Glass.regular`, and `GlassEffectContainer`. |
| Compatibility | The package still supports macOS 13. | macOS 13–25 uses one restrained `NSVisualEffectView` fallback; it does not lower the macOS 26 path. Reduce Transparency uses a solid semantic system background. |
| Orb | The former body read as a filled/material button. | Neutral circular system glass, separate restrained state ring, authoritative remaining value or `--`, and only circular content shadow. |
| Quick View / Popover | Floating panels had an opaque/custom-card feel. | Both use the level-2 Liquid Glass system with preserved information structure. |
| Popover action affordance | Plain action-only buttons made rows hard to recognize as clickable. | A shared `PopoverActionRow` now owns full-row hit target, hover, pressed, focusable, disabled, and accessibility behavior. Information rows intentionally have no hover treatment. |
| Context menu | User-visible labels were hard-coded English. | Real AppKit `NSMenu` now obtains titles from the shared localization source; disabled rows remain disabled and use native AppKit behavior. |
| Settings P0 blank window | SwiftUI's required `Settings { EmptyView() }` scene opened a genuinely blank system Settings window; optional route selection also made the first detail route fragile. | The system scene now hosts the real settings root and the app-owned controller uses the same root. Sidebar routing has a non-optional `.floating` default and all six sections have non-empty detail. |
| Usage density | The window was too sparse and metric cells appeared as separate floating cards. | Compact native inspector rhythm, one grouped 2×2 metric grid, compact unavailable chart state, unchanged Account → Session → Reset Credit → Token Usage order. |

## Localization

- Added `Localizable.strings` for English and Simplified Chinese, with system-following bundle resolution.
- Added packaged-app resource lookup (`Contents/Resources` first, SwiftPM module fallback) so the QA `.app` uses the same resources as local builds.
- Localized normal user-facing labels, settings sidebar/detail, user-visible availability values, status/activity copy, Popover actions, Usage labels, and AppKit context-menu titles.
- Codex, Token, model identifiers, and technical Diagnostics capability names remain intentionally unmodified where they are product/protocol identifiers.

## Interaction and accessibility

- Status Capsule remains an `NSStatusItem` control and is not given decorative hover motion.
- Popover actions have 36 pt full-row targets, rounded native-style hover/pressed selection, keyboard focusability, and VoiceOver labels.
- Disabled actions use `.disabled`, reduced opacity, no hover state, and native non-action semantics.
- Quick View and normal information rows do not receive button hover states.
- Settings remains native `List` sidebar selection plus native Toggle/Slider; the slider continues to drive Orb size immediately.
- Working/Thinking/Waiting Approval retain the only continuous motion: 0.8 s brightness/opacity state indication. Reduce Motion disables it; no state surface scales or moves.

## Light / Dark / material hierarchy

- Persistent glance surfaces: `Glass.clear` capsule and Orb body.
- Floating information surfaces: `Glass.regular` Quick View and Popover.
- Usage, Settings, and Diagnostics remain native content windows using semantic system backgrounds and controls, not large glass cards.
- The same component topology is used in Light and Dark; system materials and semantic colors determine contrast.

## Verification

- `swift build` — PASS.
- `swift test` — PASS: 122 tests passed; 3 pre-existing opt-in local-path tests skipped because their environment paths were not supplied.
- `git diff --check` — PASS before commit.
- Added targeted regression coverage for stable Settings default detail route, six-section sidebar contract, bilingual localization existence, action-row sizing/disabled contract, and existing single-surface ownership.

## Real runtime smoke

The packaged UI System QA app was launched against the real local monitoring source with a bounded smoke exit:

```text
runtime=WORKING
ui=WORKING
activity=tool
threads=12
desktop=available
token=34297572
usage=unknown
quota=unknown
reset=unknown
uiUpdates=3
```

The real chain remains intact:

```text
Codex Desktop local source → MonitorRuntime → MonitorAppModel → native macOS surfaces
```

Usage, quota, and reset are still displayed truthfully as unknown on this host. Approval resolution remains unavailable and no resolution UI was introduced.

## QA application

[`Codex Monitor UI System QA.app`](QA%20Builds/Codex%20Monitor%20UI%20System%20QA.app)

This is a signed local QA build with the executable and its localization resource bundle. It is not a release build.
