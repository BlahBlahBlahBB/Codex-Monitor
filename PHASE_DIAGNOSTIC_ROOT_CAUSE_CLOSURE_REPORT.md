# Diagnostic Root-Cause Closure

Date: 2026-08-11

Scope: diagnostic observation and correction only. This is **not** a Luna or Release authorization.

## Diagnostic boundary

`MonitorDiagnostics` writes structured `os.Logger` records with a monotonic timestamp, sequence number, and build revision in these categories: `state`, `presentation`, `localization`, `settings`, `popover`, `usageChart`, and `orbHost`.

The exporter deliberately has no source-payload input. Runtime thread/turn identifiers are one-way FNV values; the export records no OAuth data, API keys, raw auth tokens, email, prompts, transcripts, or system/developer messages.

The QA-only Advanced action creates `/Users/shouchen.nsc/Downloads/CodexMonitor-Diagnostics.zip` with the required JSONL files, view/layer tree, sanitized preferences, and build metadata. The final package inspection found all required files and a privacy scan found none of the prohibited classes of data.

## 1. Idle continued to breathe

**OBSERVED** — The former Orb and status-capsule implementations retained a local `breathing` state and attached `repeatForever` to it. That animation instance could outlive a transition into an otherwise steady presentation.

**ROOT CAUSE** — Animation eligibility was stored independently of `VisualStatePresentation.breathes`; it was therefore not an exact function of the runtime presentation.

**FIX** — Replaced both retained animation states with `PresentationBreathing`. Its `TimelineView` exists only while the current presentation has `breathes == true`; idle, completed, errors, paused, and unavailable render a fixed opacity with no running animation timeline.

**EVIDENCE** — `testIdlePresentationCannotCarryBreathingFromWorkingOrTerminalState` asserts idle = three green steady dots and green steady Orb. The exported real presentation records show source-unavailable = gray/steady and working/thinking = blue/green breathing, exactly matching the matrix.

**RESULT** — Fixed in the presentation layer. A fully independent live `IDLE` sample could not be captured while this Codex task was actively producing work; it remains explicitly covered by the regression test rather than claimed as manually observed.

## 2. Transient red at new Working turn

**OBSERVED** — A retained terminal visual animation could briefly present stale red while a new turn had already become Working/Thinking.

**ROOT CAUSE** — This was presentation-state retention, not a re-opened runtime/state-engine issue. The state engine already supplies the new active turn as authoritative.

**FIX** — The visual surface now derives dots and Orb directly from the current `VisualStatePresentation`; no red animation state is retained across a new snapshot. State diagnostics record the previous/next runtime state plus `terminalRetention=cancelledByNewTurn` when applicable.

**EVIDENCE** — Existing `V3StateEngineTests.testRedRetentionAndImmediateNewTurnOverride` remains green; the new presentation regression asserts Thinking has green breathing dot 1, blue Orb, and no red dot.

**RESULT** — Fixed; no terminal presentation can persist independently of the current snapshot.

## 3. Rectangular gray/translucent Orb backing

**OBSERVED** — The rectangular host had not explicitly reset every compositing-affecting layer property, so panel clear-color checks alone were insufficient evidence.

**ROOT CAUSE** — Incomplete host compositor contract: `cornerRadius`, masking, and layer shadow were not explicitly cleared and no rendered-corner observation existed.

**FIX** — The Orb keeps glass directly on `Circle`, never wraps the rectangular host in `GlassEffectContainer`, and explicitly clears the host background, opacity, corner radius, masks, and shadow. Added recursive panel/view/layer export plus rendered-corner alpha probing.

**EVIDENCE** — The final diagnostics export records `layerContract=true` and `white=pass`, `black=pass`, `orange=pass`, `splitColor=pass`. The recursive tree records a non-opaque clear NSPanel and OrbHostingView with zero shadow. App-scoped packaged visual observation showed only the circular Orb with no rectangular backing.

**RESULT** — Fixed and verified by both alpha/background probe and packaged visual observation.

## 4. Follow System first-open English / mixed locale

**OBSERVED** — The old localizer resolved from independent call sites and could default to English before the stored preference/system language was applied.

**ROOT CAUSE** — There was no single, synchronous localization owner spanning AppKit menus and SwiftUI roots.

**FIX** — Added `LocalizationController`, constructed before application menu setup. It synchronously resolves stored preference plus launch/system preferred languages (including AppKit `-AppleLanguages`) and drives `L10n`, AppKit menu rebuilds, and every SwiftUI root locale environment.

**EVIDENCE** — Cold isolated QA launch used `zh-Hans` with Follow System. The first Settings sidebar/detail and Advanced export UI were Chinese; the first orb context menu was Chinese; the first Usage window was Chinese. `localization.jsonl` records `preference=system` and `resolvedLocale=zh-Hans` before Popover creation. Localization and product integration tests pass.

**RESULT** — Fixed for the observed first-open surfaces. The menu popover root is created from the same controller before it can open; the final human gate can directly exercise that already-instrumented surface without a language toggle.

## 5. Rightmost Usage tooltip overflow

**OBSERVED** — Tooltip positioning used only an X offset, with no final frame clamp.

**ROOT CAUSE** — The tooltip did not have a bounded geometry contract for its full width and height.

**FIX** — Added `UsagePresentation.tooltipFrame`, clamping both axes to padded chart bounds. The chart applies that resolved frame after real hover selection; it does not change the existing hover-to-bucket mapping.

**EVIDENCE** — `testUsageChartPointerMappingAndZeroDayTooltip` verifies both far-right and far-left/top placements stay inside all padded bounds. Usage was also opened in the zh-Hans QA app with authoritative display values preserved.

**RESULT** — Fixed by deterministic geometry regression. A live rightmost-bar hover was not separately asserted because the observed chart accessibility surface exposes no individual bars; no visual success is fabricated.

## 6. Floating Settings dashed line

**OBSERVED** — Source search found no custom Slider track, ticks, Canvas, or dashed drawing. It did find a generic `SettingsRow` bottom separator underneath every row, including the native Slider row.

**ROOT CAUSE** — The generic separator was the only extra line in the Floating size row.

**FIX** — Removed that overlay. The row now contains one native Slider and its value label only; the layout contract records `hasCustomSliderDecoration=false`.

**EVIDENCE** — `testOrbHostTransparencyAndSettingsSingleTrackContracts` passes. Packaged QA visual inspection shows one native Slider control and no app-provided second/dashed/tick line.

**RESULT** — Fixed.

## 7. Snapshot, source, and capability truthfulness

**OBSERVED** — During QA the real local source alternated between Working/Thinking and temporary unavailable.

**ROOT CAUSE** — This is expected external-source availability behavior, not a terminal/completion inference.

**FIX** — No capability contract was changed. The new diagnostics make the transition auditable while current `VisualStatePresentation.forSnapshot` remains fail-closed when desktop health is unavailable.

**EVIDENCE** — Exported records show real `THINKING` / `WORKING` entries, corresponding breathing presentation, temporary `state.sourceUnavailable` with gray steady visuals, then subsequent live Working/Thinking entries. The visible QA accessibility label likewise reported `Codex 来源不可用` rather than stale work/idle data during loss.

**RESULT** — Fail-closed behavior remains intact. Approval resolution was not inspected or changed and remains unavailable.

## Verification

- `swift build` — PASS.
- `swift test` — PASS: 133 executed, 0 failures, 3 pre-existing opt-in local probes skipped.
- Focused `MonitorProductIntegrationTests` — PASS: 18 executed, 0 failures.
- `git diff --check` — PASS.
- New isolated signed QA app: `QA Builds/Codex Monitor Diagnostic Closure QA.app`.
- Diagnostic package: `/Users/shouchen.nsc/Downloads/CodexMonitor-Diagnostics.zip`.

## Result

Diagnostic root-cause closure is complete for the identified presentation, compositor, localization, tooltip, and Slider defects. No monitoring architecture, capability contract, approval-resolution behavior, Luna work, or Release work was entered.
