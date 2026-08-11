# FINAL UI STABILIZATION & PARITY CLOSURE

## Conclusion

**NOT READY**

The targeted source repair, packaged localization smoke, and full automated
suite pass. However, the required interactive Settings close/reopen loop was
interrupted by a concurrent human change after 15 successful cycles; the
remaining five cycles must not be inferred as passed. No P0/P1 defect was
observed in those 15 cycles, but the required 20/20 evidence is incomplete.

## Closure work completed

1. **Orb rectangular backing — root cause and fix.** The transparent panel
   contract was correct, but its `NSHostingView` could still be treated as an
   opaque layer-backed rectangular host by AppKit compositing. `OrbHostingView`
   now explicitly reports `isOpaque == false` and forces a transparent layer
   background after attachment. The panel remains non-opaque, clear, and has
   no panel shadow; the only visible material/shadow is the circular SwiftUI
   orb.
2. **Centre-anchored resize and smoothness.** Resizing previously reused a
   stored origin. New size now derives from the old screen-space centre and is
   clamped only after that calculation. Size persistence is debounced for
   slider tracking and flushed on termination, preventing synchronous defaults
   writes from participating in every live resize tick.
3. **Settings P0 — canonical ownership.** The SwiftUI `Settings` scene could
   retain accessibility content while its actual rendered detail was blank
   after reopen. The app now has one retained `SettingsWindowController`; it
   owns the native window and ordered-out/reopen lifecycle. The system
   Settings menu is explicitly rerouted to the same controller, as are menu
   popover and context-menu actions. The inert SwiftUI scene is never used as
   a presentation owner.
4. **Stray slider separator.** The Floating settings detail no longer uses a
   grouped `Form`; a normal native SwiftUI stack preserves the Toggle/Slider
   controls without Form row separators.
5. **Packaged localization P0.** SwiftPM emits `zh-hans.lproj`, while the
   system locale reports `zh-Hans`. The resolver now matches `.lproj`
   directories case-insensitively for the preferred system locale. Packaged
   startup smoke printed `refresh=刷新 usage=用量 settings=设置` under zh-Hans
   and English values under en.
6. **Popover focus treatment.** The always-on `.focusable` modifier was
   creating a mouse-rest blue focus outline. It was removed; the shared style
   now only paints restrained 150 ms hover/pressed feedback, while the native
   Button still retains keyboard accessibility semantics.
7. **Quick View truthfulness.** Known internal prompt/history markers are
   replaced by localized `Current task` / `当前任务`; normal user-facing titles
   remain intact. Quota has no authoritative source in this environment, so
   Quick View now displays `--`, not a truncated `Unknown`.
8. **Usage density.** The default/minimum window and content width were
   reduced, section spacing tightened, and fact values constrained to one
   meaningful line so internal or unavailable data cannot spread across the
   page.

## Packaged QA evidence

- QA app: `QA Builds/Codex Monitor Closure QA.app`
- QA build source commit: `8ffc8f9cfc0ed81b9bdf38793e53a12e1d8d58cb`
- Debug startup prints the commit, build timestamp, and resolved locale.
- `zh-Hans` packaged smoke: locale `zh-Hans`; Refresh/Usage/Settings printed
  as `刷新` / `用量` / `设置`.
- `en` packaged smoke: locale `en`; values printed as `Refresh` / `Usage` /
  `Settings`.
- A pre-fix packaged inspection reproduced the actual blank Settings render
  despite a populated accessibility tree. After the single-owner repair, the
  packaged screenshot showed the sidebar, default **Floating** detail, and all
  four functional controls.
- Settings interactive lifecycle: 15/20 close → system Settings menu → reopen
  cycles passed, each checking visible sidebar plus `Floating Window Size`.
  A concurrent user modification interrupted cycles 16–20; they remain
  unverified rather than marked as passing.

## Validation

- `swift build`: PASS
- `swift test`: PASS — 124 tests, 0 failures, 3 pre-existing environment-gated
  local probes skipped
- `git diff --check`: PASS
- Added focused regression coverage for centre-preserving resize and
  task-title sanitization. Existing persistence, placement, unavailable, and
  localization contracts remain passing.

## Remaining gate work

Run the remaining five Settings close/reopen cycles after the active human QA
session is finished, then complete the required human visual pass for orb
backing across contrasting backgrounds, slider smoothness, context/popover
focus states, Quick View, and Usage. This is an evidence gap, not a discovered
new monitoring/runtime blocker. No release or further visual-polish phase was
entered.
