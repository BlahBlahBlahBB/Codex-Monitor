# Final UI Structural Parity Blueprint

**Stage:** Structural parity analysis only  
**Decision:** The prior visual implementation (`1a1bec3`) is invalid as a visual source. It is not a patch target.  
**Code changes in this stage:** None. This document neither changes the runtime nor authorizes an implementation.

## 1. Authority, scope, and preservation contract

### 1.1 Source order used for this blueprint

1. Frozen product decisions and the current Hybrid runtime/capability contracts.
2. The verified functional baseline at `d823b05`:
   runtime, state engine, Desktop-local monitoring, Waiting Approval detection, session-token semantics, snapshot truthfulness, panel lifecycle, drag/resize, position persistence, Quick View placement, menu behavior, settings persistence, reconnect and sleep/wake recovery.
3. Approved visual reference `Codex-Monitor-Hybrid-Handoff-v2.0/00_APPROVED_VISUAL_REFERENCE_v1.9.html`.
4. `Codex-Monitor-Hybrid-Handoff-v2.0/LEGACY_REFERENCES/08_DESIGN_SYSTEM_AND_COMPONENT_SPEC_v1.0.md`.
5. `Codex-Monitor-Hybrid-Handoff-v2.0/LEGACY_REFERENCES/07_MACOS_SWIFTUI_APPKIT_ARCHITECTURE_v1.0.md`.
6. `Codex-Monitor-Handoff-v1.2/11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md`.
7. Earlier prototypes, then the failed V1 implementation last.

The product/runtime sources win whenever an older visual document proposes a capability that is not present in the verified local capability contract. In particular, approval *resolution* remains **UNAVAILABLE**. No view may infer or present Approved, Declined, or Cancelled.

### 1.2 Explicit non-goals of the structural rebuild

- Do not alter `MonitorRuntime`, `DesktopLocalAdapter`, source hierarchy, State Engine priority, or approval-resolution capability contract.
- Do not add polling, direct database/log/RPC access from UI, screen scraping, data estimation, or synthetic usage/quota/reset values.
- Do not change the verified behavior for panel restoration, clamping, single-click placement, settings persistence, reconnect, or sleep/wake recovery except where a native window host is needed to render the same behavior.
- Do not treat the failed V1 visual code as a design specification. Its pure presentation layer may be replaced wholesale in the later implementation stage.

### 1.3 Truthful presentation contract

| Runtime field | Permitted visual output | Prohibited output |
|---|---|---|
| Current state | The exact normalized runtime state, with source-unavailable fail-closed wording where applicable. | Locally inferred state, stale state represented as live, or an approval resolution. |
| Session/thread/title/model | Only attributed values in `MonitorRuntimeSnapshot`; omit unavailable optional metadata or show `UNKNOWN` where the reference requires a value slot. | A fabricated title, thread, model, or session association. |
| Session Token | Authoritative current-session value, otherwise `UNKNOWN` / `UNAVAILABLE` according to its snapshot availability. | Account-total Token use substituted for current-session Token use. |
| Quota | For an authoritative active rate-limit window, `remaining = clamp(100 - usedPercent, 0...100)`. The Orb uses the minimum remaining across authoritative active windows. Otherwise `--`. | Used percentage labeled as remaining; zero for absent data; quota inferred from Token use. |
| Usage / cost / history | Authoritative values; no authoritative fee is `$--`; unavailable aggregate/history is `UNKNOWN` / `UNAVAILABLE`. | Pricing estimates, fabricated 30-day bars, or a zero substituted for unknown. |
| Reset information | Authoritative count/time only. Reset action appears only when current capability/source makes it safely actionable. | A fabricated count, expiry, reset time, or optimistic local decrement. |
| Source health/capability | Explicit `AVAILABLE`, `STALE`, `UNAVAILABLE`, or `UNKNOWN` as supplied by the snapshot. | A cached/stale value presented as current after the source is unavailable. |

## 2. Cross-surface structural tokens

These are optical targets from v1.9, not a CSS-porting instruction. Native macOS control metrics win only when they preserve the frozen information hierarchy.

| Token | Structural target | Native implementation rule |
|---|---|---|
| Menu capsule | 48 × 22 pt; three 7 pt dots; approximately 5 pt dot gap; thin light/white outline. | Fixed-width custom `NSStatusItem` host view. A ±1–2 pt optical adjustment is allowed only after real menu-bar comparison. |
| Orb | Default 90 × 90 pt; ring diameter approximately 90% of orb diameter; 7 pt ring at 90 pt. | Transparent `NSPanel`; scalable SwiftUI drawing inside a circular content shape. Preserve verified user size range **72...180 pt** (the functional contract overrides the old 64 pt reference). A fresh installation default must migrate to **90 pt** without changing an existing saved user value. |
| Quick View | Approximately 340–360 pt wide (350 pt optical target); compact, height driven by the fixed hierarchy. | Borderless/nonactivating `NSPanel`, no arrow, not `NSPopover`. |
| Menu popover | Approximately 330–350 pt wide (340 pt optical target). | `NSPopover` hosting SwiftUI; no ordinary `NSMenu` list presentation. |
| Spacing scale | 4, 6, 8, 10, 12, 14, 16, 20, 24, 32 pt. | Use these as a sparse rhythm, not as dense card padding. |
| Popup spacing | 15–16 outer inset; 14 major divider margin; 8 row gap; 6 action gap; 8 action vertical padding. | Retain visible air between the three approved blocks. |
| Usage spacing | 20 content inset; 13 section-heading-to-content; 24 major section separation; 14 group padding; 17 metric-cell padding. | Native window content, not stacked glass cards. |
| Settings spacing | 20 content inset; 20 groups; 58 minimum setting row; approximately 15 × 16 row padding. | Native sidebar/list and native controls; do not imitate iOS cards. |
| Typography | System font only. Status 17 semibold; orb value 24 bold at 90 pt; section 15 semibold; body 13–14; metadata 12–13; usage metric 22. | Native controls retain their system type metrics; no rounded-display font substitution or bundled font. |
| Status motion | Working/Thinking: about 0.8 s brightness breathing only. | Reduce Motion disables breathing. Never scale, translate, pulse the center percentage, or add neon glow. |
| Transparency | Glass identity belongs to capsule, Orb, Quick View, and Menu Popover. | Honor Reduce Transparency; Usage and Settings stay primarily native and restrained. |

## 3. Approved-reference to native implementation map

## A. Menu Bar Status Capsule

| Required mapping | Approved v1.9 structure → native macOS implementation |
|---|---|
| 1. Original information structure | A compact B · Balanced status signal only: three status dots inside one outlined capsule. It is not a textual status label and not a generic app icon. |
| 2. Element order | Left-to-right: dot 1, dot 2, dot 3. Dot position, not color alone, communicates the state category. |
| 3. Hierarchy | The capsule is the persistent global-status glance layer. Dot 1 is normal activity, dot 2 is approval attention, dot 3 is error attention. It carries less information than the popover and Quick View. |
| 4. Approximate proportions | 48 × 22 pt optical target; each dot approximately 7 pt; approximately 5 pt inter-dot space; thin approximately 1.35 pt light/white outline; low-contrast transparent/dark capsule fill as appropriate to the system appearance. |
| 5. Spacing rhythm | Symmetric horizontal insets around the three dots; no added glyph, text, badge, or app icon. The outer capsule must remain visually lighter than an action button. |
| 6. Typography hierarchy | None visually. Provide a concise VoiceOver label that includes the exact textual state and source availability. |
| 7. Icon structure | Three circular indicators only; no SF Symbol replaces the capsule. State mapping: Idle/completed are all green constant; Working/Thinking uses dot 1 green brightness breathing; Waiting Approval uses dot 2 yellow brightness breathing; Failed/Interrupted/System Error uses dot 3 red constant; disconnected/source unavailable is gray fail-closed. |
| 8. Window type | `NSStatusItem` in the macOS menu bar, using a custom view at fixed optical width. |
| 9. Interaction | Left click toggles one `NSPopover`; click-away closes it. No hover information. No duplicate popover. |
| 10. Native component | AppKit `NSStatusBar.system.statusItem(withLength:)` + custom `NSView`/`NSHostingView`; `NSPopover` is owned separately by the status-item controller. SwiftUI renders only the capsule content. |
| 11. Allowed native deviation | ±1–2 pt only to compensate for real menu-bar optical alignment at 1×/2× and Light/Dark. Native menu-bar highlight behavior may occur on click. |
| 12. Forbidden deviation | `MenuBarExtra` default icon; a normal circular icon; removal of the white/light outline; a large pill; text inside the capsule; custom neon glow; a normal `NSMenu` as the primary left-click content. |

**Current V1 assessment:** `CodexMonitorApp.swift` creates `MenuBarExtra("Codex Monitor", systemImage: "circle.fill")`; the existing `MonitorStatusCapsule` is not the status-item host and has a different dot semantic (state/activity/source). **REBUILD.**

## B. Menu Bar Popover

| Required mapping | Approved v1.9 structure → native macOS implementation |
|---|---|
| 1. Original information structure | Exactly three blocks: (1) Codex state and current activity/update; (2) account, plan, quota, reset credit, and an immediate-reset action only when authoritative and safely available; (3) product actions. Open Codex is preserved as a product action without adding a fourth informational block. |
| 2. Element order | Block 1 state/current activity → divider and breathing room → Block 2 account/plan/quota/reset → divider and breathing room → Block 3 Usage, Settings, Show/Hide Floating Window, Open Codex, Quit. The approved action ordering remains dominant; Open Codex is inserted within Block 3, not promoted into a new header. |
| 3. Hierarchy | Current state is primary; concise activity/update is secondary; account/quota facts are supporting; actions are the final, visually quiet block. This is not a dashboard and does not duplicate Quick View's full session detail. |
| 4. Approximate proportions | 330–350 pt width, 340 pt target. Rows are content-led with no oversized header. |
| 5. Spacing rhythm | 15–16 outer inset; 8 within block rows; approximately 14 around dividers; approximately 6 between actions; each action has approximately 8 pt vertical touch padding. |
| 6. Typography hierarchy | State approximately 17 pt semibold; activity/update 12–13 pt secondary; account/quota rows 13–14 pt; action labels use native menu/popover body type. |
| 7. Icon structure | Block 3 action icons share one equal physical leading container: Usage `chart.bar`/system chart, Settings flat `gearshape`, Floating Window simple orb/circle, Open Codex `arrow.up.right.square`, Quit `power`. No colorful app icon set. |
| 8. Window type | Anchored `NSPopover`, transient behavior, one instance owned by the status-item controller. |
| 9. Interaction | Status capsule left click toggles it; click outside closes it. Actions invoke the existing usage/settings/orb/open-Codex/quit coordinators. Reset is absent or disabled with an honest reason unless the authoritative reset capability is live and passes its confirmation/idempotency contract. |
| 10. Native component | AppKit `NSPopover` + `NSHostingController`; SwiftUI `VStack` sections and buttons styled for a popover, not an `NSMenu`. Existing runtime arrives through `MonitorAppModel` only. |
| 11. Allowed native deviation | The native popover arrow, native focus behavior, and system typography may differ from the HTML reference. Optional account fields may be hidden when no authoritative identity exists; quota/reset slots then say `UNKNOWN`/`UNAVAILABLE` rather than invent values. |
| 12. Forbidden deviation | Replacing it with a standard `MenuBarExtra` `NSMenu`; extra dashboard cards/tabs; hiding Open Codex; raw SQLite/RPC reads; an enabled reset action without an authoritative capability, confirmation, and successful refresh. |

**Current V1 assessment:** The menu bar is a standard action-only `MenuBarExtra` menu and contains none of the approved state/account block structure. **REBUILD.**

## C. Floating Orb

| Required mapping | Approved v1.9 structure → native macOS implementation |
|---|---|
| 1. Original information structure | Transparent floating window → circular glass body → near-outer runtime-state ring → central remaining-quota value. The center is quota, never the runtime-state word. |
| 2. Element order | Outside-in: fully transparent panel exterior; circular glass body; ring at approximately 90% diameter; centered quota percentage or `--`. Runtime state remains encoded by the ring rather than a central label. |
| 3. Hierarchy | Central remaining quota is the numeric glance value. The ring is runtime state. State words belong in Quick View and accessibility, not the default Orb face. |
| 4. Approximate proportions | Fresh-install default 90 × 90 pt. Ring diameter approximately 81 pt (90%); stroke approximately 7 pt at 90 pt and scales proportionally with persisted size. Preserve current verified 72...180 pt user range; update only the fresh default from current 96 pt to frozen 90 pt during the later rebuild. |
| 5. Spacing rhythm | Center value has generous clearance from the 7 pt ring. The ring sits close to, but never clips into, the circular glass perimeter. There is no rectangular content margin or surrounding plate. |
| 6. Typography hierarchy | Center: approximately 24 pt bold at the 90 pt reference size, monospaced digits if necessary for optical stability. It does not animate scale. Optional accessibility text says both runtime state and quota availability/value. |
| 7. Icon structure | No icon and no state-word label on the face. Ring color is only the frozen runtime mapping: Idle/completed green constant; Working/Thinking green brightness breathing; Waiting Approval yellow breathing; Failed/Interrupted/System Error red constant; disconnected/source unavailable gray. Low quota does not recolor the ring. |
| 8. Window type | Transparent, borderless, nonactivating floating `NSPanel`, joining all spaces/full-screen auxiliary as the already verified lifecycle does. |
| 9. Interaction | Preserve verified drag, direct resize, position/size persistence, multi-display screen-edge clamp, app restart restoration, show/hide lifecycle, and single-left-click Quick View toggle. Right click invokes Section E native context menu. Starting a drag closes Quick View. No hover information. |
| 10. Native component | AppKit `NSPanel` owned by a single panel controller; SwiftUI `Circle` composition in an `NSHostingView`; system-native Liquid Glass APIs on macOS 26+ for the circular body. The view reads the immutable `MonitorAppModel.snapshot` and preferences only. |
| 11. Allowed native deviation | Native liquid-glass rendering, native shadow handling, and point-level ring antialiasing may differ from HTML. With Reduce Transparency, use a system-approved opaque material inside the *circle* while keeping the panel exterior transparent. If no quota is authoritative, center `--`; that is required fail-closed behavior, not a deviation. |
| 12. Forbidden deviation | A square/gray/background rectangle, panel border, corner artifact, green filled disk plus thick outline, state label (`IDLE`, `WORKING`, `FAILED`, etc.) as the center value, used-percent mislabeled as remaining, a quota-derived ring color, hover card, or visual state inferred outside the snapshot. |

**Current V1 assessment:** The transparent panel and restored-frame mechanics are useful functional assets, but `MonitorOrbView` renders runtime text in the center and the existing visual layer is not the approved circular glass/quota hierarchy. The fresh default is 96 pt rather than 90 pt. **REBUILD the presentation while preserving the controller/lifecycle behavior.**

## D. Single-click Quick View

| Required mapping | Approved v1.9 structure → native macOS implementation |
|---|---|
| 1. Original information structure | A pure information sheet with this exact hierarchy: `Codex` + current state + update/time; task/session title + concise current activity; divider; model + runtime; session token + remaining quota. It is intentionally not an account/source-health dashboard. |
| 2. Element order | Header identity/time → state line → task/session title → one-line activity → divider → model/runtime metadata → token/quota metadata. For disconnected/source-unavailable, header/state becomes the explicit fail-closed condition while optional unavailable values remain honest. |
| 3. Hierarchy | State is primary, task title is next, activity is concise supporting text, then technical/session metadata. The panel has no controls: it is a glance surface, not an action menu. |
| 4. Approximate proportions | 340–360 pt width (350 target); compact vertical fit based on the above rows. The existing 320 × 330 fixed list is not the reference proportion. |
| 5. Spacing rhythm | Approximately 15–16 horizontal and 14–16 vertical outer insets; 4–6 internal header/text gaps; 10–12 task-to-metadata cadence; approximately 14 around divider. Avoid an oversized card or large blank list regions. |
| 6. Typography hierarchy | `Codex` and current state around 17 pt semibold; time/update 12–13 pt secondary; task title 13–14 pt medium; activity 12–13 pt; metadata 12–13 pt secondary. Long titles/actions truncate to one line in this compact surface. |
| 7. Icon structure | A restrained state dot beside textual state is allowed; no action icons or giant status capsule. Metadata uses text with minimal SF Symbol support only if it preserves scan order. |
| 8. Window type | Borderless, nonactivating, no-arrow `NSPanel`, separate from `NSPopover`. |
| 9. Interaction | A single Orb left click toggles it. No hover, buttons, switches, approval controls, Open Codex action, or pointer triangle. Preserve the QA-passed placement: left half → right side, right half → left side; vertically center to Orb then clamp to `NSScreen.visibleFrame`; use opposite side before clamp if preferred side does not fit. Close on Orb drag and never create duplicate panels. |
| 10. Native component | AppKit `NSPanel` with `NSHostingView<QuickView>`; existing `FloatingPanelLayout.quickViewFrame` remains the placement authority. SwiftUI content consumes only `MonitorAppModel.snapshot`. |
| 11. Allowed native deviation | Native glass/material rendering and a dynamic height for legitimately omitted unavailable optional fields. The captured/update time is shown only when it represents a current source-backed snapshot; otherwise show explicit source condition and do not give a stale time a live meaning. |
| 12. Forbidden deviation | Buttons, Toggle, native menu rows, pointer arrow, Hover presentation, an account/source-health multi-section list as the primary structure, status capsule substitution for text state, stale data labeled as live, or loss of the existing placement/clamping behavior. |

**Current V1 assessment:** Current Quick View correctly uses a borderless nonactivating panel and preserved placement logic, but its content is a 320 × 330 Session/Account/Source Health list with a status capsule and animation. That is structurally different from the frozen compact hierarchy. **REBUILD the content presentation; preserve panel/placement lifecycle.**

## E. Orb Right-click Menu

| Required mapping | Approved v1.9 structure → native macOS implementation |
|---|---|
| 1. Original information structure | Native contextual command surface, not information display. Approved order: Refresh; Usage; Open Codex; separator; Always on Top; Lock Position; Hide Floating Window; separator; Settings; Quit Monitor. |
| 2. Element order | Keep the three command groups and separators exactly. Existing supported commands map into their approved slots. Commands without a real frozen backing preference/service must not claim working behavior. |
| 3. Hierarchy | Immediate observation/navigation first, placement/window controls next, app configuration/termination last. The menu does not replace Quick View or the menu-bar popover. |
| 4. Approximate proportions | Native `NSMenu` item height, indentation, separator, keyboard-equivalent, and checkmark geometry. No custom width, pills, or cards. |
| 5. Spacing rhythm | System menu spacing; separators create the only major rhythm. |
| 6. Typography hierarchy | Native `NSMenu` type; no custom display hierarchy. |
| 7. Icon structure | SF Symbols may be supplied only where native context-menu rendering supports them; stateful entries use native checkmarks, never custom Toggle controls. |
| 8. Window type | AppKit `NSMenu` anchored to the Orb panel event location. |
| 9. Interaction | Right click only. `Usage`, `Open Codex`, `Hide Floating Window`, `Settings`, and `Quit` call existing product behaviors. `Refresh` must request the existing safe monitor reconciliation path only if such a public coordinator entry point exists; it must not read sources in UI or add busy polling. `Always on Top` and `Lock Position` require real persisted preferences and controller behavior before they can be enabled. |
| 10. Native component | An `NSMenu` built/owned by the floating-panel/window coordinator; SwiftUI has no custom context-menu Toggle UI. |
| 11. Allowed native deviation | Where current frozen functionality has no actual backing setting (currently Always on Top and Lock Position), the later implementation must either omit the command pending explicit product authority or render it disabled with a truthful unavailable explanation. This preserves command grouping without fabricating an ON/OFF state. |
| 12. Forbidden deviation | Pretending that an unimplemented placement preference works; custom web-style context sheet; a Quick View on right click; action controls inside Quick View; approval-resolution commands; commands that kill/control Codex Desktop lifecycle. |

**Current V1 assessment:** No Orb right-click native context menu exists. **REBUILD.** Its native menu surface can be added in the structural rebuild only with the capability/persistence constraints above; it must not widen monitoring architecture.

## F. Usage Window

| Required mapping | Approved v1.9 structure → native macOS implementation |
|---|---|
| 1. Original information structure | One true content window with four vertically ordered sections: Account, Session, Reset Credit, Token Usage. Token Usage contains a top 2 × 2 metric grid then a 30 natural-local-calendar-day bar chart. |
| 2. Element order | Account → Session → Reset Credit → Token Usage → metric grid (Today cost, Last 30 days cost, Today Token, Last 30 days Token) → 30-day bar chart. No in-window tabs or duplicate dashboard header. |
| 3. Hierarchy | Account/session/reset facts establish attribution and limits; Token Usage is the detailed lower section. Metrics are larger than labels but remain subordinate to the window's section structure. |
| 4. Approximate proportions | Standard sizeable native window; approximately 20 pt content inset; a two-column, two-row metric area with approximately 17 pt cell padding; 30 evenly spaced calendar positions across the chart. No individual floating/glass cards. |
| 5. Spacing rhythm | 13 from heading to section content; 24 between major sections; 14 inside a logical group. Chart has enough x-axis room for 30 fixed day slots, including authoritative zero-use days. |
| 6. Typography hierarchy | Section headings approximately 15 pt semibold; metric values approximately 22 pt; body 13–14 pt; chart/metadata 12–13 pt. Use system font and real currency/token formatting only for present data. |
| 7. Icon structure | Primarily text/data. If a section icon is retained it must be a restrained SF Symbol, not colorful app art; icons cannot replace section labels. |
| 8. Window type | One reusable real AppKit `NSWindow` with real traffic lights and no visible title text (“Usage” must not be repeated in titlebar). Closing the red traffic light closes/focuses this window only, never quits Monitor. |
| 9. Interaction | Menu/popover/context action opens or focuses one existing usage window. Bar hover may show date, exact authoritative Token count, and authoritative fee or `$--`. No chart data means a truthful unavailable chart state, not made-up low bars. |
| 10. Native component | `NSWindowController` + `NSWindow` + `NSHostingController`; SwiftUI stacked sections; `LazyVGrid`/custom native drawing only for the 2 × 2 metrics and 30 fixed chart slots. Runtime data is passed from `MonitorAppModel`, never read by the view. |
| 11. Allowed native deviation | Native traffic lights, resizing, titlebar margins, and chart accessibility behavior. Unsupported email/plan/history fields are hidden or labeled `UNKNOWN`; unavailable cost is `$--`. When there is no authoritative 30-day history, show a clear unavailable chart state rather than invented 30 bars. |
| 12. Forbidden deviation | Routing Usage to the generic main window; title text “Usage” in the titlebar; fake traffic lights; tabs; account switching/credentials; Token-to-cost calculation; Session Token substituted for account history; all-glass card composition. |

**Current V1 assessment:** The Usage menu item focuses the main `WindowGroup`, whose content is a glass dashboard/diagnostics view. It is not a separate native Usage window and does not implement the required ordered data structure. **REBUILD.**

## G. Settings Window

| Required mapping | Approved v1.9 structure → native macOS implementation |
|---|---|
| 1. Original information structure | A true macOS settings window: sidebar on the left and selected detail on the right. Frozen sidebar sections are General, Floating, Notifications, Privacy, Advanced, About. |
| 2. Element order | Sidebar order: General → Floating → Notifications → Privacy → Advanced → About. The detail panel places a section heading first, then native setting rows/groups. Existing frozen preferences belong in Floating: Show Floating Window, Orb Size slider, Show Usage in Menu, Show Settings in Menu. |
| 3. Hierarchy | Sidebar selects a domain; detail holds only settings supported by an actual persisted/service-backed capability. General is not a marketing dashboard. Floating is the current functional preference domain. |
| 4. Approximate proportions | Approximately 200 pt sidebar with a flexible native detail pane; content inset around 20; rows at least 58 pt where a title/description pair exists. |
| 5. Spacing rhythm | Approximately 20 between groups; 15 × 16 row padding; 4 between title and secondary description. Avoid compressed forms and card stacks. |
| 6. Typography hierarchy | Native sidebar text; detail heading around 15 pt semibold; setting label/body uses native system text. Orb size value uses system monospaced digits when useful. |
| 7. Icon structure | Sidebar uses restrained standard SF Symbols in a consistent leading column. Binary controls are native switch Toggles; size uses a native Slider. No literal ON/OFF text or custom web switches. |
| 8. Window type | Reusable real `NSWindow` with real traffic lights and no visible title text (“Settings” must not be repeated in titlebar). Closing it leaves Monitor running. |
| 9. Interaction | Menu/popover/context action opens or focuses one settings window. Existing preferences apply and persist immediately; the Orb size slider remains synchronized with direct resize. Sections without a current backed feature must be omitted from their detail or visibly explain that no setting is available—never display a fake working Toggle. |
| 10. Native component | AppKit `NSWindowController` + `NSWindow` + `NSHostingController`; SwiftUI `NavigationSplitView` or AppKit split/sidebar hosting; native `List(selection:)`, `Toggle(...).toggleStyle(.switch)`, and `Slider`. |
| 11. Allowed native deviation | Native sidebar row height/selection/material and traffic lights. The frozen functional baseline currently exposes only four persisted preferences; unbacked PRD-era controls (Launch at Login, Always on Top, Lock Position, Pause Monitoring, notifications, Hide Account Info) remain absent, disabled with an honest unavailable explanation, or require a separate approved feature phase. |
| 12. Forbidden deviation | Existing glass `Form` as the settings window, iOS Settings appearance, dashboard cards, fake Toggle/Slider, an enabled control without a backing preference/service, or breaking real-time resizing/persistence. |

**Current V1 assessment:** The current SwiftUI `Settings` scene is a single glass form with four controls and no native sidebar/detail structure or controlled reusable `NSWindow`. **REBUILD.** Existing four preferences are preservation requirements, not an invitation to invent the other settings.

## H. Main / Diagnostics Presentation

| Required mapping | Approved v1.9 structure → native macOS implementation |
|---|---|
| 1. Original information structure | The approved product is a menu-bar utility. Its primary user-facing surfaces are the capsule, popover, Orb, Quick View, Usage, and Settings. It does **not** approve a permanent dashboard as the primary app surface. Diagnostics are advanced/support information, not the everyday information hierarchy. |
| 2. Element order | If diagnostics remain exposed, use: snapshot/source-health summary → session/thread attribution → capability availability. Keep it outside the normal Usage information order and do not prepend it to every launch. |
| 3. Hierarchy | Primary product surfaces first. Diagnostics are a deliberately secondary, advanced presentation for troubleshooting; they never replace Usage or Quick View. |
| 4. Approximate proportions | A standard native utility/document-style diagnostic window only if opened intentionally; no mandated hero Orb, oversized card, or 560 × 600 glass dashboard is present in the approved reference. |
| 5. Spacing rhythm | Native grouped inspection spacing; compact but readable rows. It follows the cross-surface spacing scale, without decorative glass nesting. |
| 6. Typography hierarchy | Native headings/body/metadata; raw identifiers use monospaced or selectable system text where needed. `UNAVAILABLE` must be explicit. |
| 7. Icon structure | Minimal SF Symbols only for source/capability health. No prominent decorative app icon or status capsule duplicate. |
| 8. Window type | Optional reusable `NSWindow`/window-controller diagnostic presentation, hidden by default. It is not the `WindowGroup` target used for Usage. |
| 9. Interaction | Reached only through an explicitly named Advanced/Diagnostics path; read-only. It may show snapshot age/source state/capability state but cannot invoke approval resolution or raw source operations. |
| 10. Native component | AppKit `NSWindowController` + SwiftUI `Form`/`List`/`DisclosureGroup` content. It consumes the same `MonitorAppModel.snapshot`; no adapter/data-source access. |
| 11. Allowed native deviation | Because v1.9 does not prescribe a visual diagnostics window, native restraint, selectable IDs, and developer-only grouping are allowed. The existing diagnostic data may remain available but must no longer define the primary app visual architecture. |
| 12. Forbidden deviation | Presenting the current giant glass `MonitorMainView` as the primary Usage/main experience; a new dashboard, analytics surface, or controls that re-open protocol work; leaking private raw data/credentials. |

**Current V1 assessment:** The launched `WindowGroup` is a large glass dashboard that combines status, Orb, account, and diagnostics and is also incorrectly used for Usage. It has no approved primary-surface parity. **REBUILD its presentation role; retain read-only diagnostics data as an advanced route only.**

## I. Light Mode

| Required mapping | Approved v1.9 structure → native macOS implementation |
|---|---|
| 1. Original information structure | Identical information and interaction order to Dark Mode. Appearance cannot add, hide, or reinterpret data. |
| 2. Element order | Capsule, popover blocks, Orb layers, Quick View hierarchy, Usage sections, Settings sidebar/detail all retain their respective frozen orders. |
| 3. Hierarchy | Semantic type contrast and separator contrast preserve the same glance → detail relationship; source/capability truthfulness is unaffected by color scheme. |
| 4. Approximate proportions | All geometry tokens remain unchanged: 48 × 22 capsule, 90 pt default Orb, 340-ish compact popover/Quick View targets, and native Usage/Settings windows. |
| 5. Spacing rhythm | The same sparse system spacing; Light Mode never needs extra cards or darker rectangles to establish grouping. |
| 6. Typography hierarchy | Use semantic primary/secondary/tertiary system colors and system font. Meet contrast without a hard-coded white-on-black treatment. |
| 7. Icon structure | Same SF Symbol/dot positions. The capsule keeps its approved light outline but uses a system-appropriate translucent fill and contrast rather than a permanently black web-style badge. |
| 8. Window type | Same AppKit hosts and activation behavior as Dark Mode. |
| 9. Interaction | Same left click, right click, native controls, accessibility, and Reduced Motion behavior. |
| 10. Native component | `NSAppearance`/SwiftUI semantic `Color` and macOS 26 native glass APIs where available; `NSVisualEffectView`/system material only as a documented compatibility decision, never as a hand-painted fake. |
| 11. Allowed native deviation | System-managed material tint, traffic-light coloration, native selection highlight, and readability adjustment for Reduce Transparency. |
| 12. Forbidden deviation | Hard-coded black card background; white text assumed for every context; relying on ring color alone; square panel artifacts; a different information architecture from Dark Mode. |

**Current V1 assessment:** Current V1 applies hand-composed glass/dark-oriented presentation across primary windows and has not established the required semantic Light Mode structural matrix. **REBUILD.**

## J. Dark Mode

| Required mapping | Approved v1.9 structure → native macOS implementation |
|---|---|
| 1. Original information structure | Identical to Light Mode, with the same capability availability and unavailable wording. Dark Mode is an appearance variant, not an alternate dashboard. |
| 2. Element order | Retain the exact per-surface sequences specified in A–H. |
| 3. Hierarchy | Semantic primary/secondary text and restrained state ring/dot color maintain readability; status text and dot position keep information accessible without relying on saturation. |
| 4. Approximate proportions | No dark-only scale, glow, heavier outline, or changed panel/window dimensions. |
| 5. Spacing rhythm | Same 4–32 scale and airy three-block/compact Quick View structures. Dark space is not filled with extra gradients or cards. |
| 6. Typography hierarchy | System font and semantic macOS text colors; no custom rounded headline treatment. |
| 7. Icon structure | Same aligned SF Symbols; capsule retains a thin light outline, and Orb has one restrained state ring—not multiple neon/glowing rings. |
| 8. Window type | Same `NSStatusItem`, `NSPopover`, `NSPanel`, `NSMenu`, and `NSWindow` topology. |
| 9. Interaction | Same native behavior; breathing remains brightness-only and is disabled by Reduce Motion. |
| 10. Native component | macOS-native material/glass and system colors selected by the effective appearance. |
| 11. Allowed native deviation | System material translucency/shadow rendering and native window chrome may be darker than the HTML sample while preserving contrast and hierarchy. |
| 12. Forbidden deviation | Neon/game HUD effects, black glass cards everywhere, opaque gray Orb surround, state-text center label, color-only status communication, or a different Dark Mode component tree. |

**Current V1 assessment:** Current V1's dark material styling does not repair its wrong surface topology or information hierarchy. **REBUILD.**

## 4. Native host topology for the later structural rebuild

This is a composition plan, not an instruction to change runtime architecture.

```text
MonitorRuntime snapshot
        ↓ (existing observable model; duplicate suppression retained)
MonitorAppModel
        ├── StatusItemController
        │     ├── NSStatusItem → StatusCapsuleView
        │     └── NSPopover → MenuPopoverView
        ├── FloatingOrbWindowController
        │     ├── transparent NSPanel → FloatingOrbView
        │     ├── transparent NSPanel → QuickView
        │     └── NSMenu → Orb Context Menu
        ├── UsageWindowController
        │     └── NSWindow → UsageView
        ├── SettingsWindowController
        │     └── NSWindow → SettingsSplitView
        └── DiagnosticsWindowController (advanced/read-only only)
              └── NSWindow → DiagnosticsView
```

### 4.1 Coordinator boundaries

- **UI consumes `MonitorAppModel.snapshot` only.** It does not import database, rollout, logs, RPC, `DesktopLocalAdapter`, or `ApprovalLocalAdapter`.
- The status-item, panels, popover, usage/settings windows, and context menu must be owned by a small window/surface coordinator so repeated actions focus/toggle a single host rather than create duplicates.
- Existing `FloatingStatusPanelController` frame restore, clamping, restart, drag, resize, quick-view placement, show/hide, and current `MonitorPreferences` bindings are functional assets. Refactor only its host/presentation boundary when necessary; preserve its observed contract and tests.
- Existing `MonitorPreferences` data remains the single source for current persisted settings. A visual sidebar is not permission to add unsupported persisted settings or default them to apparent ON/OFF states.
- `Open Codex` continues to use the existing normal `NSWorkspace` launch path. It must not add lifecycle manipulation or terminate/restart Codex.

### 4.2 Availability-specific rendering decisions

| Surface | Available | Stale / unknown / unavailable |
|---|---|---|
| Capsule | Frozen state dot mapping. | Gray/fail-closed condition, accessible textual label names source condition. |
| Orb | Central authoritative minimum remaining percentage. | Central `--`; ring gray if runtime source unavailable/disconnected. |
| Quick View | Show current state/title/activity and authoritative metadata. | State says source unavailable/disconnected; time is not presented as a live update; individual optional metadata is `UNKNOWN`/`UNAVAILABLE` or omitted per fixed row. |
| Popover | Account/plan/quota/reset rows where authoritative. | Hide absent identity fields; label fixed informational slots honestly; do not enable reset. |
| Usage | Values/history actually supplied by runtime/storage capability. | `$--`, `UNKNOWN`, / `UNAVAILABLE`; no fee or chart fabrication. |
| Settings / Diagnostics | Controls/values with a real backing preference/capability. | Omit unavailable controls or show disabled truthful explanation; diagnostics shows the capability state. |

## 5. Current V1 structural delta inventory

The following are deliberate rebuild targets. They are not visual-polish tasks.

| Current implementation | Structural mismatch | Later rebuild direction | Frozen behavior to retain |
|---|---|---|---|
| `MenuBarExtra` with `circle.fill` | No B capsule `NSStatusItem`, no custom popover, no state/account blocks. | Replace the visual host with `NSStatusItem` + `NSPopover`; bind existing actions. | Usage/settings visibility choices, Orb show/hide, Open Codex, Quit. |
| `MonitorStatusCapsule` | Dot semantics are state/activity/source rather than frozen positional status grammar; it is not the menu-bar item. | New capsule component exactly matching A. | Snapshot state/source truthfulness. |
| `MonitorOrbView`/current visual layer | Central runtime labels and V1 material do not meet quota-center Orb contract. | Rebuild only circular presentation/layering and authoritative remaining formatter. | Transparent panel, drag/resize/clamp/persistence/tap, duplicate prevention. |
| Current Quick View | Session/account/source-health list, status capsule, fixed tall layout. | Rebuild into compact frozen read-only hierarchy. | Borderless nonactivating panel and tested placement. |
| No right-click menu | Approved contextual command surface absent. | Native `NSMenu`, with only backed commands enabled. | Never control/quit Codex; no approval resolution. |
| Main `WindowGroup` used as Usage | Unapproved glass dashboard takes primary role; no Usage window. | Separate reusable native Usage window; diagnostics separately advanced. | Read-only current snapshot data. |
| SwiftUI `Settings` glass form | No native sidebar/detail or controlled Settings window. | Native sidebar/detail window; preserve four real preference bindings. | Persistence and live Orb-size updates. |
| Current default orb preference 96 pt | Violates frozen 90 pt fresh-install visual default. | Migration/default correction only; do not overwrite saved non-default user size. | 72...180 clamp and remembered current user choice. |

## 6. Structural parity scorecard

| Component | Approved structure understood? | Native mapping defined? | Current V1 matches? | Requires rebuild? |
|---|---:|---:|---:|---:|
| Menu Capsule | Yes | Yes — `NSStatusItem` custom capsule | No | **REBUILD** |
| Menu Popover | Yes | Yes — `NSPopover` + SwiftUI three blocks | No | **REBUILD** |
| Orb | Yes | Yes — transparent `NSPanel` + circular glass/ring/quota | No | **REBUILD** |
| Quick View | Yes | Yes — no-arrow `NSPanel` + compact read-only hierarchy | No | **REBUILD** |
| Context Menu | Yes | Yes — real `NSMenu` | No | **REBUILD** |
| Usage | Yes | Yes — reusable native `NSWindow` | No | **REBUILD** |
| Settings | Yes | Yes — reusable native sidebar/detail `NSWindow` | No | **REBUILD** |
| Diagnostics | Yes — secondary only | Yes — advanced read-only native window | No | **REBUILD** |
| Light Mode | Yes | Yes — semantic native colors/material | No | **REBUILD** |
| Dark Mode | Yes | Yes — semantic native colors/material | No | **REBUILD** |

## 7. Later implementation acceptance gates

The implementation phase may begin only after treating the following as non-negotiable structural checks:

1. The status item is the fixed B capsule, not `MenuBarExtra`'s circle icon; its left click produces one three-block `NSPopover`.
2. The Orb outer panel is fully transparent. The body is circular glass; the ring carries runtime state; the center is authoritative remaining quota or `--`.
3. The existing QA-passed floating window behavior remains: one Orb, one Quick View, drag/resize/persist/clamp/relaunch, correct left/right Quick View placement, no hover.
4. Quick View is information-only and follows the approved state/task/metadata order.
5. Usage and Settings each own one real native `NSWindow` with real traffic lights and no duplicate title text; they do not become glass-card dashboards.
6. No control whose backend/persistence is not present is made to look operational. Approval resolution remains explicitly unavailable.
7. Light/Dark/Reduce Motion/Reduce Transparency preserve this exact component topology and truthful availability behavior.

## 8. Implementation-stage scope boundary

The later structural rebuild is allowed to replace V1 presentation and window-host wiring, while retaining the verified runtime model and user-visible functional contracts. It must not begin new protocol research, approval-resolution work, usage estimation, or unapproved feature development. Any new control that would require a new persisted setting or system integration is outside this structural parity task until explicitly authorized.

**Stage result:** The approved v1.9 structure is fully mapped to native macOS components, the invalid V1 gaps are identified as rebuild work, and frozen V3-5 behavior/capability truthfulness is explicitly protected.
