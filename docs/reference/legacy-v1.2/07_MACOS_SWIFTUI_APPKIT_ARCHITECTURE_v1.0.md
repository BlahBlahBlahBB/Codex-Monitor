# Codex Monitor — macOS SwiftUI + AppKit Architecture v1.0

> Status: **Architecture Draft — Ready for implementation review**  
> Platform: macOS  
> Recommended deployment target: **macOS 26.0+** for native Liquid Glass APIs  
> UI stack: SwiftUI + AppKit  
> Depends on:
> - `04_STATE_ENGINE_AND_EVENT_MAPPING_v1.1_FROZEN.md`
> - `05_ACCOUNT_USAGE_QUOTA_AND_RESET_MODEL_v1.0.md`
> - `06_LOCAL_DATABASE_AND_SWIFT_DATA_LAYER_v1.0.md`

---

## 1. Architecture Goal

Codex Monitor is a native macOS menu-bar utility with a persistent optional Floating Orb.

The production app must not look like a web dashboard wrapped in a desktop shell.

Primary product surfaces:

```text
Menu Bar status capsule
Menu Bar popup
Floating Orb
Single-click Quick View
Right-click Orb context menu
Usage window
Settings window
Native notifications
```

There is **no Hover feature**.

The app is read-first:

```text
observe Codex
display status
display account / quota / token usage
consume an explicit reset credit only after confirmation
```

v1 does not approve/decline Codex task authorization requests.

---

## 2. Native Framework Responsibility

### SwiftUI owns

```text
Menu popup content
Floating Orb visual content
Quick View content
Usage content
Settings content
native Toggle / Slider / Picker controls
charts
formatting-driven presentation
```

### AppKit owns

```text
NSStatusItem
NSPopover
NSPanel
NSWindow
window levels
screen placement
dragging / resizing
context menus
traffic-light titlebar behavior
activation policy
focus / key-window behavior
```

### Foundation / system frameworks

```text
Swift Concurrency
ServiceManagement
UserNotifications
OSLog
SQLite / GRDB
```

Rule:

> Use SwiftUI for view composition and AppKit where macOS windowing behavior requires precise control.

---

## 3. Why macOS 26+ Is Recommended

The product requires genuine Apple Liquid Glass rather than a CSS/material imitation.

For macOS 26+:

```text
View.glassEffect(_:in:)
Glass
GlassEffectContainer
system Liquid Glass buttons / toolbars / controls
```

can be used directly.

Therefore the recommended v1 target is:

```text
macOS 26.0+
```

Do not manually reproduce Liquid Glass with stacked gradients, fake blur layers, white borders and arbitrary shadows when a system Liquid Glass API exists.

If support for macOS 15 or earlier is requested later, that becomes a separate compatibility project with a material fallback.

---

## 4. Liquid Glass Design Principle — FROZEN DIRECTION

Liquid Glass is a **system functional layer**, not a decoration applied to every card.

Use it for:

```text
Floating Orb body
Quick View floating panel
menu-bar popup controls where native system rendering applies
small custom floating controls
interactive custom surfaces that benefit from pointer response
```

Do not turn every Usage or Settings section into an independent glass card.

Usage and Settings should rely primarily on:

```text
native window backgrounds
system groupings
system dividers
native controls
standard typography
```

Custom glass:

```swift
.glassEffect(.regular, in: ...)
```

should only be added when the component is genuinely a floating/custom control.

When several adjacent glass shapes must visually interact:

```text
GlassEffectContainer
```

may be used.

---

## 5. App Process Model

Recommended app type:

```text
menu-bar utility / accessory application
```

Info.plist:

```text
LSUIElement = true
```

Effect:

- no permanent Dock icon
- no normal app switcher presence
- status item remains the primary entry point
- Usage / Settings can still be presented as native windows

The app process stays alive while:

```text
menu-bar item exists
OR app has not been explicitly quit
```

Do not terminate merely because all windows are closed.

---

## 6. Top-Level App Composition

Recommended entry:

```swift
@main
struct CodexMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

AppKit coordinates the actual utility surfaces.

Reason:

The product requires exact control over:

```text
custom menu-bar status capsule
floating nonactivating orb panel
no-arrow Quick View panel
native Utility windows
right-click menu
window levels
```

These are easier to keep deterministic through AppKit window controllers than by forcing every surface into a SwiftUI Scene.

---

## 7. AppEnvironment

Create one dependency container at process launch:

```swift
@MainActor
final class AppEnvironment {
    let presentationStore: AppPresentationStore

    let monitorCoordinator: MonitorCoordinator
    let database: DatabaseActor
    let codexConnection: CodexConnectionActor

    let statusItemController: StatusItemController
    let orbWindowController: OrbWindowController
    let quickViewController: QuickViewWindowController
    let usageWindowController: UsageWindowController
    let settingsWindowController: SettingsWindowController

    let notificationCoordinator: NotificationCoordinator
    let launchAtLoginService: LaunchAtLoginService
}
```

Avoid global mutable singletons.

---

# PART A — MENU BAR

## 8. Menu Bar Status Item

Use:

```text
NSStatusBar.system.statusItem(withLength: ...)
```

Controller:

```swift
@MainActor
final class StatusItemController
```

Reason for AppKit rather than a generic template icon:

The status element is a frozen custom three-dot capsule:

```text
B · Balanced
48 × 22
dot diameter ≈ 7
white capsule outline retained
```

It must support realtime state animation.

The button hosts a custom SwiftUI/AppKit status view.

---

## 9. Frozen Status Capsule Mapping

```text
IDLE
  dot1 green constant
  dot2 green constant
  dot3 green constant

THINKING / WORKING
  dot1 green brightness breathing
  dot2 inactive
  dot3 inactive

WAITING_APPROVAL
  dot1 inactive
  dot2 yellow brightness breathing
  dot3 inactive

FAILED / INTERRUPTED / SYSTEM_ERROR
  dot1 inactive
  dot2 inactive
  dot3 red constant

DISCONNECTED / PAUSED
  all inactive / system gray
```

Animation:

```text
~0.8 seconds
brightness only
no scaling
no glow
```

When Accessibility Reduce Motion is enabled:

```text
do not animate
retain the same dot position + state color
```

---

## 10. Menu Bar Popup

Use:

```text
NSPopover
+
NSHostingController<MenuPopupView>
```

Behavior:

```text
left click status capsule
→ toggle popup
```

Popup structure:

```text
Block 1 — Codex runtime state
Block 2 — account / plan / quota / reset credit
Block 3 — four shortcut actions
```

Actions:

```text
Usage
Settings
Show/Hide Floating Window
Quit
```

Additional reset action remains inside quota/account block if reset credit is available.

Use native system spacing and controls.

No web-style dashboard navigation.

---

## 11. Popup Closing

Native behavior:

```text
click outside
→ close popover

click status item again
→ close popover

open Usage or Settings
→ close menu popup
→ open requested window
```

The popup should not become a second persistent app window.

---

# PART B — FLOATING ORB

## 12. Floating Orb Window

Use a custom:

```text
NSPanel
```

Suggested style:

```swift
styleMask: [
    .borderless,
    .nonactivatingPanel
]
```

Configuration:

```text
isOpaque = false
backgroundColor = .clear
hasShadow = false
hidesOnDeactivate = false
collectionBehavior includes:
  canJoinAllSpaces
  fullScreenAuxiliary
```

The panel must accept pointer events even though it is nonactivating.

---

## 13. Floating Orb Visual

Default:

```text
90 × 90 pt
```

All visible content scales proportionally as the panel is resized.

Frozen relationship:

```text
outer orb
  ↓
state ring ≈ 90% of orb diameter
  ↓
center quota remaining %
```

State ring:

```text
green / yellow / red / gray
```

Center:

```text
most constrained authoritative quota remaining
```

Do not use quota percentage to recolor the state ring.

---

## 14. Native Liquid Glass Orb

On macOS 26+:

- use a custom SwiftUI Orb surface
- apply system Liquid Glass using the native glass API
- use `Circle()` for the main orb geometry
- use real SwiftUI drawing for the state ring

Do not recreate the system material by manually drawing:

```text
frosted white gradient
fake inner border
fake glass lens
neon outer glow
```

The status ring can use controlled custom highlights/shading only to communicate material depth without competing with the system glass material.

---

## 15. Orb Window Level

Setting:

```text
Always on Top
```

Behavior:

```text
ON  -> NSWindow.Level.floating
OFF -> normal accessory panel level
```

Do not use extreme levels such as screenSaver unless technically required by a future feature.

---

## 16. Orb Dragging

When `Lock Position = OFF`:

```text
drag body
→ move Orb panel
```

When `Lock Position = ON`:

```text
drag does not move panel
```

On drag end:

```text
save screen identifier
save normalized X/Y
```

Clamp the orb inside:

```text
NSScreen.visibleFrame
```

not the full frame, so it avoids the menu bar and Dock.

---

## 17. Orb Resizing

Two synchronized input methods:

```text
1. direct resize interaction
2. Settings size Slider
```

Single source of truth:

```text
AppSettings.orbSize
```

Default:

```text
90 pt
```

Current prototype range:

```text
64 ... 180 pt
```

This range is an implementation safety range, not a visual breakpoint system.

All content remains visible and proportionally scaled at every allowed size.

No “small mode” that hides the center percentage.

---

## 18. Orb Click

Frozen:

```text
single left click
→ open / close Quick View
```

Do not open:

```text
Usage
Codex Desktop
menu popup
```

from normal left click.

---

## 19. Orb Right Click

Show a native:

```text
NSMenu
```

Entries:

```text
刷新
用量
打开 Codex
────────
始终置顶
锁定位置
隐藏悬浮窗
────────
设置
退出监控
```

Stateful entries:

```text
Always on Top
Lock Position
```

use native checkmark state.

Do not recreate a custom HTML-like context menu.

---

# PART C — QUICK VIEW

## 20. Quick View Window

Because the product explicitly avoids a pointed bubble/triangle, do not use an arrowed popover.

Use:

```text
borderless nonactivating NSPanel
+
NSHostingController<QuickView>
```

Characteristics:

```text
rounded floating surface
no titlebar
no arrow
read-only
no buttons
no switches
```

---

## 21. Quick View Content

Frozen structure:

```text
Codex
● 工作中                        time

Task title
One-line current action

Model · runtime
Session Token · remaining quota
```

Other states:

```text
Completed
Waiting Approval
Idle
Disconnected
Paused
Failed
Interrupted
System Error
```

No approval controls.

---

## 22. Quick View Placement

Use the orb's actual window frame plus:

```text
NSScreen.visibleFrame
```

Preferred side:

```text
orb on left half
→ Quick View to the right

orb on right half
→ Quick View to the left
```

Vertical origin:

```text
orb.midY - quickView.height / 2
```

Then clamp vertically to `visibleFrame`.

Horizontal fallback:

If preferred side cannot fit:

```text
try opposite side
then clamp
```

No content may be placed off-screen.

This is the replacement for the now-removed Hover positioning problem.

---

## 23. Quick View Dismissal

Close when:

```text
click orb again
click elsewhere
press Escape when appropriate
open Usage
open Settings
hide Orb
```

If the Orb moves while Quick View is open:

```text
reposition Quick View continuously or close it
```

Recommended v1:

```text
close Quick View when drag begins
```

This avoids distracting panel movement.

---

# PART D — USAGE WINDOW

## 24. Usage Is a Real Native macOS Window

Production must not draw fake red/yellow/green circles.

Use a real:

```text
NSWindow
```

with standard style mask:

```text
titled
closable
miniaturizable
resizable
```

The system owns:

```text
red close
yellow minimize
green zoom/full-screen behavior
```

---

## 25. Usage Titlebar

User-approved visual requirement:

```text
traffic-light controls visible
no “用量” text in the top titlebar
```

Configure:

```swift
window.titleVisibility = .hidden
```

Use the native titlebar.

Do not manually draw a second titlebar inside SwiftUI.

---

## 26. Usage Content Structure

Frozen order:

```text
账户
会话
限额重置额度
Token 使用
```

Token metrics:

```text
今日费用
近30天费用
今日 token 用量
近30天 token 用量
```

Then:

```text
30 natural calendar-day bar chart
```

Spacing should remain comfortable, not compressed.

---

## 27. Usage Liquid Glass Rule

Usage is a content window, not a floating glass panel.

Therefore:

```text
window background -> system
groups            -> standard macOS grouping
controls          -> system
chart             -> custom content
```

Do not apply a glass card to every section.

Use Liquid Glass only if a custom floating/interactive control specifically benefits from it.

---

## 28. Usage Window Lifetime

Use one window controller instance.

Behavior:

```text
open Usage
→ if already open, bring existing window forward

close red button
→ close window
→ keep Monitor running
```

Do not create duplicate Usage windows on repeated clicks.

---

# PART E — SETTINGS WINDOW

## 29. Settings Is a Real Native macOS Window

Same window rules as Usage:

```text
real NSWindow
real traffic lights
no manually drawn traffic-light circles
```

User-approved requirement:

```text
no “设置” title text in the top titlebar
```

Use:

```swift
window.titleVisibility = .hidden
```

---

## 30. Settings Navigation

Current sections:

```text
通用
悬浮窗
通知
隐私
高级
关于
```

For macOS, prefer a native sidebar/list presentation.

On a sufficiently wide window:

```text
sidebar on left
detail on right
```

Do not imitate iOS Settings.

---

## 31. Settings Toggle Controls

All binary settings must use the native SwiftUI:

```swift
Toggle(...)
    .toggleStyle(.switch)
```

Do not display literal:

```text
ON
OFF
```

unless required for accessibility text.

Affected settings include:

```text
开机启动
显示悬浮窗
始终置顶
锁定位置
暂停监控
等待授权通知
任务完成通知
隐藏账户信息
```

Do not hand-draw a custom switch.

---

## 32. Floating Orb Size Slider

Use native SwiftUI:

```swift
Slider
```

The slider value is directly bound to:

```text
AppSettings.orbSize
```

Behavior:

```text
drag slider
→ Orb resizes in realtime
→ percentage/ring/content all scale together
→ persist size with short debounce
```

If Orb is currently hidden:

```text
slider still changes stored size
```

When Orb is shown again:

```text
it appears at the selected size
```

---

## 33. Language Control

Use native:

```text
Picker
```

Values:

```text
跟随系统
简体中文
English
```

Avoid custom dropdown styling unless system behavior is insufficient.

---

# PART F — WINDOW COORDINATION

## 34. WindowCoordinator

Create:

```swift
@MainActor
final class WindowCoordinator
```

Responsibilities:

```text
show/hide menu popup
show/hide Orb
show/hide Quick View
show/focus Usage
show/focus Settings
close dependent transient panels
apply Always on Top
apply Lock Position
apply Orb resize
```

All window actions route through this controller.

SwiftUI buttons do not construct NSWindow objects themselves.

---

## 35. Mutual Interaction Rules

### Opening Usage

```text
close menu popup
close Quick View
show/focus Usage
```

### Opening Settings

```text
close menu popup
close Quick View
show/focus Settings
```

### Hiding Orb

```text
close Quick View
hide Orb
persist visibility = false
```

### Quitting

```text
close transient panels
flush state
disconnect Monitor only
terminate Codex Monitor
leave Codex running
```

---

## 36. App Activation

For menu popup and Orb interactions:

```text
do not unnecessarily activate the whole app
```

For full Usage / Settings windows:

```text
bring the native window to front
activate app as needed for keyboard interaction
```

Because `LSUIElement = true`, this activation must not create a permanent Dock icon.

---

# PART G — SYSTEM INTEGRATIONS

## 37. Launch at Login

Use:

```text
ServiceManagement
SMAppService.mainApp
```

Settings toggle:

```text
ON  -> register
OFF -> unregister
```

Read actual service status and reconcile the toggle.

Do not rely on a preference value alone.

---

## 38. Notifications

Use:

```text
UNUserNotificationCenter
```

Request authorization only when necessary.

Frozen defaults:

```text
等待授权通知 = OFF
任务完成通知 = OFF
```

If disabled:

```text
do not post
```

Do not use notification permission as the source of truth for whether the setting itself is enabled.

---

## 39. Open Codex

Use:

```text
NSWorkspace
```

Resolution priority:

```text
known Codex app bundle identifier / URL
known installed application URL
fallback user-facing error
```

Do not shell out to arbitrary `open` commands when native APIs are sufficient.

---

# PART H — APPLE LIQUID GLASS IMPLEMENTATION

## 40. System First

Priority:

```text
1. native system component
2. standard SwiftUI style
3. native glassEffect for custom component
4. custom drawing only when product-specific geometry requires it
```

Examples:

```text
Settings Toggle -> system Toggle
Settings Slider -> system Slider
Window traffic lights -> NSWindow
Context menu -> NSMenu
menu popup -> NSPopover
Floating Orb -> custom SwiftUI + native glassEffect
Quick View -> custom floating panel + native glassEffect
```

---

## 41. Glass Interactivity

For custom interactive glass components where pointer response is appropriate:

```text
Glass.regular.interactive()
```

may be used.

Do not make passive display cards interactive solely for visual effect.

---

## 42. Glass Tint

State color should primarily live in:

```text
state ring / status dot
```

not by tinting the whole window bright green/yellow/red.

A subtle system glass tint may be used only if it does not overpower the semantic ring.

---

## 43. Reduce Transparency

If the user enables macOS Reduce Transparency:

```text
respect system behavior
```

Do not force custom blur back on.

The design must remain readable with more opaque materials.

---

## 44. Contrast

Status must never depend on color alone.

Red/yellow/green are supplemented by:

```text
different dot position
Quick View status text
icons / labels
```

This matters for accessibility and color-vision differences.

---

# PART I — FOCUS / KEYBOARD / ACCESSIBILITY

## 45. Menu Popup Keyboard

Ensure normal macOS keyboard navigation for actionable controls.

Use native focusable components.

Escape:

```text
closes popup
```

where system behavior does not already handle it.

---

## 46. Orb Accessibility

Expose an accessibility label such as:

```text
“Codex Monitor，工作中，剩余额度 42%”
```

Do not expose decorative ring layers separately.

Right-click menu must remain keyboard accessible through normal macOS interaction when opened.

---

## 47. Quick View Accessibility

Expose:

```text
state
task
activity
model
runtime
session Token
remaining quota
```

as semantic text.

Do not let decorative Glass layers become accessibility elements.

---

# PART J — PERFORMANCE

## 48. Animation Lifecycle

Breathing animation runs only while:

```text
THINKING
WORKING
WAITING_APPROVAL
```

No animation timer while:

```text
IDLE
COMPLETED
FAILED
INTERRUPTED
DISCONNECTED
PAUSED
```

Completed state is constant green for 5 seconds.

Red terminal state is constant red for 15 seconds.

---

## 49. No Data Polling From Animation

The ~0.8-second breathing animation is entirely visual.

It must never trigger:

```text
account/read
rateLimits/read
thread/list
database query
```

Each frame/tick.

---

## 50. Window Rendering

Only keep expensive view work active for visible windows.

Usage chart should not continuously redraw while the Usage window is closed.

---

# PART K — ERROR PRESENTATION

## 51. Surface Priority

Transient technical errors should not create modal alerts unless user action is required.

Use:

```text
status state
inline text
last updated / stale indication
diagnostic log
```

Modal native alerts are appropriate for:

```text
reset credit confirmation
reset failure requiring explanation
destructive local-history clear action
critical database migration problem
```

---

# PART L — PRODUCTION CONTROLLERS

## 52. Recommended Controllers

```text
AppDelegate
AppEnvironment
WindowCoordinator
StatusItemController
MenuPopoverController
OrbWindowController
QuickViewWindowController
UsageWindowController
SettingsWindowController
```

Views:

```text
StatusCapsuleView
MenuPopupView
FloatingOrbView
QuickView
UsageView
SettingsView
```

---

## 53. Suggested UI Folder

```text
UI/
├── DesignSystem/
│   ├── GlassSurface.swift
│   ├── Spacing.swift
│   ├── Typography.swift
│   └── StatusPalette.swift
│
├── MenuBar/
│   ├── StatusCapsuleView.swift
│   ├── StatusItemController.swift
│   ├── MenuPopupView.swift
│   └── MenuPopoverController.swift
│
├── FloatingOrb/
│   ├── FloatingOrbView.swift
│   ├── OrbWindowController.swift
│   ├── OrbResizeController.swift
│   └── OrbPlacementService.swift
│
├── QuickView/
│   ├── QuickView.swift
│   └── QuickViewWindowController.swift
│
├── Usage/
│   ├── UsageView.swift
│   ├── UsageWindowController.swift
│   ├── UsageChart.swift
│   └── UsageMetricGrid.swift
│
└── Settings/
    ├── SettingsView.swift
    ├── SettingsWindowController.swift
    └── SettingsSection.swift
```

---

# PART M — ACCEPTANCE TESTS

## 54. Menu Bar

Pass when:

1. Capsule matches frozen B proportion.
2. White capsule outline is retained.
3. State dots map correctly.
4. Breathing changes brightness only.
5. Clicking opens one native popup.
6. Clicking outside closes it.
7. No duplicate popup can exist.

---

## 55. Floating Orb

Pass when:

1. Default size is 90 pt.
2. User can continuously resize it.
3. Ring/percentage scale proportionally.
4. Slider and direct resize stay synchronized.
5. Position is restored after restart.
6. Position is clamped into visible screen.
7. Always-on-top applies immediately.
8. Lock prevents dragging.
9. Single click opens Quick View.
10. Right click opens native context menu.
11. No Hover interaction exists.

---

## 56. Quick View

Pass when:

1. Read-only.
2. No buttons.
3. No pointer triangle.
4. Never clips off-screen.
5. Displays the current frozen state information.
6. Closes when Orb drag begins.
7. Does not approve authorization.

---

## 57. Usage

Pass when:

1. Real native macOS window.
2. Real traffic-light controls.
3. No fake traffic-light SwiftUI circles.
4. Titlebar does not show “用量”.
5. Red closes the window, not the Monitor process.
6. Opening again focuses the same window.
7. Content order matches frozen Usage design.

---

## 58. Settings

Pass when:

1. Real native macOS window.
2. Real traffic lights.
3. Titlebar does not show “设置”.
4. All binary options use native switch Toggle.
5. Orb size uses native Slider.
6. Slider resizes Orb in realtime.
7. Settings changes apply immediately.
8. Closing Settings does not quit Monitor.

---

## 59. Liquid Glass

Pass when:

1. Native macOS 26 Liquid Glass APIs are used for custom glass surfaces.
2. The app does not mimic Glass with a web/CSS look.
3. Usage/Settings are not covered in unnecessary glass cards.
4. Native controls remain native.
5. Reduce Motion / Reduce Transparency are respected.
6. State color remains restrained and readable.

---

# PART N — TECHNICAL DECISIONS

## 60. Frozen / Recommended Decisions

```text
SwiftUI + AppKit hybrid
AppKit window controllers for precise macOS behavior
NSStatusItem for custom three-dot status capsule
NSPopover for menu-bar popup
NSPanel for Floating Orb
NSPanel for no-arrow Quick View
NSWindow for Usage
NSWindow for Settings
native traffic-light controls
native Toggle switches
native Slider
SMAppService for launch at login
UNUserNotificationCenter for notifications
LSUIElement utility-app behavior
macOS 26+ recommended
native Liquid Glass, not imitation
```

---

## 61. Remaining Architecture Validation

Before marking this file FROZEN:

### A. Deployment Target

Recommended:

```text
macOS 26.0+
```

because full native Liquid Glass is a core product requirement.

If older macOS support is later required, define a compatibility matrix before coding.

### B. Exact NSStatusItem Width

Validate the chosen:

```text
48 × 22 B capsule
```

inside the actual macOS 26 menu bar at:

```text
1x
2x Retina
Light appearance
Dark appearance
```

The product proportion stays B; implementation may need a small point-level adjustment so it optically matches the frozen design in the real system menu bar.

### C. NSPanel Material Rendering

Prototype the Orb on real macOS 26 and verify the native Liquid Glass effect inside a transparent NSPanel.

Do not replace native Liquid Glass with manual CSS-like drawing if the first prototype needs tuning.

---

## 62. Apple API Basis

Architecture decisions in this document intentionally follow current Apple platform capabilities:

```text
SwiftUI View.glassEffect(_:in:)
SwiftUI Glass / GlassEffectContainer
ServiceManagement SMAppService
AppKit NSWindow / NSPanel / NSStatusItem / NSPopover
SwiftUI native Toggle / Slider / Picker
UserNotifications
```

System-native behavior takes priority over visual imitation.

---

## 63. Next Document

After architecture review:

```text
08_DESIGN_SYSTEM_AND_COMPONENT_SPEC
```

This document will convert the approved v1.9 visual prototype into implementation tokens and component rules:

```text
spacing
typography
status colors
sizes
corner geometry
Liquid Glass usage boundaries
menu popup measurements
Orb geometry
Quick View hierarchy
Usage layout
Settings layout
SF Symbols / system icons
animation rules
accessibility behavior
```
