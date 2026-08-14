# Codex Monitor — Design System & Component Spec v1.0

> Status: **Design Draft — Based on approved Visual Review v1.9**  
> Platform: macOS 26+  
> Visual language: Apple-native, restrained Liquid Glass  
> UI stack: SwiftUI + AppKit  
> Depends on:
> - `04_STATE_ENGINE_AND_EVENT_MAPPING_v1.1_FROZEN.md`
> - `07_MACOS_SWIFTUI_APPKIT_ARCHITECTURE_v1.0.md`
> - historical approved visual prototype (retained only on `codex/github-readiness-audit`): `Codex-Monitor-Visual-Review-Mobile-v1.9.html`

---

## 1. Purpose

This document converts the approved visual prototype into native macOS implementation rules.

The prototype is a **visual reference**, not a CSS specification.

Production rules:

1. Prefer Apple system components and system metrics.
2. Use native Liquid Glass on macOS 26+.
3. Do not reproduce the HTML’s fake blur, gradients, traffic lights, switches, or sliders.
4. Preserve the approved proportions, information hierarchy, spacing rhythm, state semantics, and interaction model.
5. Small point-level adjustments are allowed only when required for correct native macOS optical alignment.

---

## 2. Product Visual Character

Codex Monitor should feel like:

```text
a small Apple system utility
+
a subtle futuristic functional layer
```

It must not feel like:

```text
SaaS dashboard
browser extension
gaming HUD
cyberpunk status widget
visionOS demo pasted onto macOS
glassmorphism template
```

Target balance:

```text
~70% native macOS restraint
~30% custom Liquid Glass identity
```

The custom identity is concentrated in:

```text
Menu Bar status capsule
Floating Orb
Quick View
```

Usage and Settings remain predominantly native macOS content windows.

---

## 3. Native-First Rule

Before creating a custom component, Codex must ask:

```text
Does macOS / SwiftUI already provide this component?
```

If yes, use it.

Examples:

| Need | Production component |
|---|---|
| Window close/minimize/zoom | native `NSWindow` traffic lights |
| Toggle | SwiftUI `Toggle` + `.switch` |
| Slider | SwiftUI `Slider` |
| Picker | SwiftUI `Picker` |
| Context menu | `NSMenu` |
| Menu-bar popup | `NSPopover` |
| Window separator | system Divider / native separator |
| Sidebar | native SwiftUI List / NavigationSplitView-style structure |
| Alert | `NSAlert` or native SwiftUI alert |
| Menu icons | SF Symbols where suitable |

Do not redraw system controls just to match the HTML prototype.

---

# PART A — COLOR

## 4. Semantic Status Colors

Use Apple semantic/system colors in production.

Reference values from the approved prototype:

```text
Working / Thinking / Idle Green:
#34C759

Waiting Approval Yellow:
#FFCC00

Failed / Interrupted / System Error Red:
#FF3B30

Disconnected / Paused Gray:
#8E8E93
```

In Swift:

```swift
Color(nsColor: .systemGreen)
Color(nsColor: .systemYellow)
Color(nsColor: .systemRed)
Color(nsColor: .systemGray)
```

Prefer the system semantic value over a hard-coded sRGB value so appearance adapts appropriately.

### Idle optical lift

The approved prototype made idle green slightly brighter than the base green.

Production rule:

- idle may receive a very subtle optical brightness lift;
- do not invent a different semantic green;
- working/idle must still clearly belong to the same green state family.

---

## 5. Neutral Colors

Do not hard-code the prototype’s gray page background into native windows.

Use system semantic colors:

```text
window background
control background
separator
secondary label
tertiary label
quaternary label
```

Suggested AppKit/SwiftUI semantics:

```text
NSColor.windowBackgroundColor
NSColor.controlBackgroundColor
NSColor.separatorColor
Color.primary
Color.secondary
```

Dark Mode must work automatically.

---

## 6. Color Usage Boundary

Status color is used primarily on:

```text
Menu Bar dots
Floating Orb state ring
small state indicator in Quick View / popup
```

Do not tint entire windows green/yellow/red.

Do not color Usage cards based on state.

Do not use red/yellow as decorative accents.

---

# PART B — TYPOGRAPHY

## 7. Font Family

Use the system font only.

```text
SF Pro / system font
```

SwiftUI:

```swift
.font(.system(...))
```

Do not bundle custom fonts.

Do not simulate SF Pro via a web font.

---

## 8. Type Hierarchy

Recommended native hierarchy:

### A. Primary status

Examples:

```text
工作中
等待授权
任务完成
Codex 未连接
```

Reference:

```text
17 pt
Semibold/Bold
```

Production:

```swift
.font(.system(size: 17, weight: .semibold))
```

### B. Primary numeric metric

Examples:

```text
$77.53
1.33亿 token
42%
```

Reference:

```text
22 pt for Usage metrics
24 pt for 90 pt Orb percentage
Bold/Semibold
```

### C. Section heading

Examples:

```text
账户
会话
限额重置额度
Token 使用
```

Reference:

```text
15 pt
Semibold/Bold
```

### D. Body / task title

Reference:

```text
13–14 pt
Regular/Semibold
```

### E. Secondary / metadata

Examples:

```text
运行 12:43
更新时间
重置 8月11日
```

Reference:

```text
12–13 pt
Secondary color
```

### F. Small labels

Reference:

```text
11–12 pt
Secondary
```

Use dynamic system metrics when native controls supply their own typography.

---

## 9. Text Rules

- Do not use all-caps English UI labels in the production Chinese interface.
- Do not overuse bold.
- One dominant information level per surface.
- Current action is one line.
- Task title is one line.
- Long email may truncate in the middle/end according to available width.
- Long command/activity text must be sanitized and truncated.
- Never show hidden reasoning content.

---

# PART C — SPACING & GEOMETRY

## 10. Spacing Scale

Use a restrained 4-point-oriented spacing scale:

```text
4
6
8
10
12
14
16
20
24
32
```

Preferred recurring values:

```text
icon ↔ label: 8–10
row vertical padding: 8–15
section internal spacing: 12–16
major section separation: 20–24
window content inset: ~20
```

Avoid arbitrary spacing values unless required for optical alignment.

---

## 11. Corner Radius

System/native controls use system radius.

Custom approved components:

```text
Floating Orb: perfect Circle
Quick View: ~18 pt reference radius
Menu popup: native NSPopover/system radius
Usage/Settings group surfaces: ~10–12 pt reference
```

Do not make every object highly rounded.

---

## 12. Border Rule

Native windows and controls use system borders/separators.

Custom border use:

```text
Menu Bar capsule:
white outline retained

Floating Orb:
do not add a strong white outline around the whole orb unless native glass rendering requires a subtle optical edge

Quick View:
native glass boundary / subtle system edge
```

Avoid thick white outlines around content cards.

---

# PART D — MENU BAR STATUS CAPSULE

## 13. Frozen Variant

Selected and frozen:

```text
B · Balanced
```

Reference geometry:

```text
width: 48 pt
height: 22 pt
corner radius: ~13 pt
dot diameter: 7 pt
gap between dots: 5 pt
```

This is the optical target.

A real native implementation may adjust by approximately ±1–2 pt if required to align correctly inside the macOS menu bar, but it must still visually read as the approved B proportion.

---

## 14. Capsule Outline

User-approved direction:

```text
retain the white capsule outline
```

Reference:

```text
~1.35 pt
high-opacity white
```

Production guidance:

- Keep the outline thin.
- Do not turn it into a glowing border.
- Allow the system material underneath to remain visible.
- In bright/light menu-bar conditions, ensure the outline still has enough contrast without becoming heavy.

---

## 15. Capsule Fill

Reference prototype:

```text
very dark / translucent capsule
subtle top-to-bottom material change
```

Production:

- let native menu-bar/system material drive the background;
- use a restrained dark translucent fill only if needed for dot readability;
- no heavy gradient;
- no bevel effect;
- no neon shadow.

---

## 16. Dot Mapping

Frozen:

| State | Dot 1 | Dot 2 | Dot 3 |
|---|---|---|---|
| Idle | Green constant | Green constant | Green constant |
| Thinking | Green breathing | inactive | inactive |
| Working | Green breathing | inactive | inactive |
| Waiting Approval | inactive | Yellow breathing | inactive |
| Completed | Green constant | Green constant | Green constant |
| Failed | inactive | inactive | Red constant |
| Interrupted | inactive | inactive | Red constant |
| System Error | inactive | inactive | Red constant |
| Disconnected | Gray/inactive | Gray/inactive | Gray/inactive |
| Paused | Gray/inactive | Gray/inactive | Gray/inactive |

Inactive dots remain visible enough to preserve the three-dot structure but must not compete with the active state dot.

---

## 17. Breathing Motion

Frozen:

```text
cadence: ~0.8 s
brightness only
no scale
no position change
no outer glow
```

The dot itself does not pulse in size.

With Reduce Motion:

```text
use constant state color
```

---

# PART E — FLOATING ORB

## 18. Base Geometry

Frozen default:

```text
90 × 90 pt
```

Circle:

```text
1:1
```

The user may resize continuously.

The whole visual scales proportionally.

---

## 19. Orb Size Range

Current implementation safety range:

```text
64–180 pt
```

This range is **recommended**, not a semantic breakpoint system.

No alternate small/large layout.

At all sizes:

```text
ring remains visible
percentage remains visible
everything scales proportionally
```

---

## 20. State Ring Geometry

Approved reference:

```text
ring diameter ≈ 90% of Orb diameter
ring width ≈ 7 pt at 90 pt Orb
```

Scale proportionally:

```text
ringWidth = orbSize × (7 / 90)
```

Reference:

```text
90 pt orb -> 7 pt ring
64 pt orb -> ~5 pt ring
180 pt orb -> ~14 pt ring
```

Implementation may clamp stroke width slightly for optical quality at extreme sizes.

---

## 21. Ring Material

The user specifically requested a slight concave/convex material impression.

Production interpretation:

- semantic state color is clear;
- use subtle light/shadow shaping inside the ring;
- native Liquid Glass remains dominant;
- ring should feel like a colored material embedded in/over the glass surface;
- no fluorescent/neon effect.

Do not copy the prototype’s CSS box-shadows literally.

---

## 22. Orb Percentage

At default 90 pt:

```text
reference: 24 pt bold
```

Display:

```text
42%
```

Disconnected:

```text
--
```

The percentage remains completely static during breathing animation.

No scale, bounce, fade, or pulse.

---

## 23. Orb Body

Use native Liquid Glass on the circular custom view.

Production goals:

```text
translucent
subtle refraction
soft material depth
not milky white
not chrome
not highly glossy
```

The Orb should remain readable on:

```text
light desktop wallpaper
dark desktop wallpaper
busy photographic wallpaper
```

---

## 24. Orb Interaction Feedback

Pointer interaction can use subtle native interactive glass response.

Do not restore Hover information.

Allowed pointer feedback:

```text
system cursor behavior
subtle native glass response
drag/resize cursor when relevant
```

Not allowed:

```text
Hover info card
Hover tooltip panel
Hover enlargement
Hover halo
```

---

# PART F — QUICK VIEW

## 25. Surface

Quick View is:

```text
no-arrow floating panel
read-only
Liquid Glass
```

Reference width:

```text
~350 pt
```

Recommended production width:

```text
340–360 pt
```

Prefer:

```text
~350 pt
```

unless content/localization requires a small adjustment.

---

## 26. Quick View Padding

Reference:

```text
horizontal: 15–16 pt
vertical: 14–16 pt
```

Section divider spacing:

```text
~11–12 pt
```

Task block top margin:

```text
~12 pt
```

---

## 27. Quick View Hierarchy

Approved structure:

```text
Codex                            18:56
● 工作中

Codex Monitor App
正在修改 3 个文件

────────────────

GPT-5.6 Sol · 运行 12:43
本会话 644.38万 Token · 剩余额度 42%
```

Rules:

- `Codex` is contextual label, not oversized title.
- state is visually dominant.
- task title is semibold.
- current action is secondary.
- model/runtime and token/quota are compact metadata.
- no buttons.
- no switch.
- no close button.
- no pointer triangle.

---

## 28. Quick View State Variants

### Completed

```text
✓ 任务完成
```

Duration:

```text
5 seconds
```

Then global state recomputes.

### Waiting Approval

```text
● 等待授权
等待你在 Codex 中确认
```

No approve button.

### Failed / Interrupted / System Error

Use red semantic indicator/text accent in a restrained manner.

Global red state duration:

```text
15 seconds
```

### Disconnected

```text
○ Codex 未连接
```

No “打开 Codex” button in Quick View.

---

# PART G — MENU BAR POPUP

## 29. Popup Width

Prototype reference:

```text
~340 pt
```

Recommended native target:

```text
330–350 pt
```

Prefer ~340 pt unless system layout requires adjustment.

---

## 30. Popup Structure

Frozen:

```text
Block 1
Codex runtime state

Divider

Block 2
Account
Plan / quota
Reset credit
Immediate reset

Divider

Block 3
Usage
Settings
Show/Hide Floating Window
Quit
```

No top navigation.

No tab bar.

No dashboard widgets.

---

## 31. Popup Spacing

Approved after spacing increase:

```text
outer content inset: ~15–16 pt
major divider vertical margin: ~14 pt
block row rhythm: ~8 pt
menu action gap: ~6 pt
menu action vertical padding: ~8 pt
```

Do not compress back to the earlier dense version.

---

## 32. Popup Action Icons

All four action icons must have:

```text
same physical icon container
~24 × 24 pt reference
```

Visible glyph:

```text
~20 pt
```

`显示悬浮窗` may optically use ~22 pt inside the same 24 pt container because circular geometry appears smaller.

Settings:

```text
flat 2D gear
```

Use SF Symbols when the symbol matches the intended Apple-flat appearance.

Recommended candidates to validate:

```text
Usage       -> chart.bar / chart.bar.xaxis
Settings    -> gearshape
Orb         -> circle.circle / custom simple orb symbol
Quit        -> power
```

Do not use colorful filled app icons.

---

## 33. Immediate Reset Button

Use a native button.

Visual:

```text
full-width within the account/quota block
secondary/system button treatment
```

Do not make it bright red.

Confirmation happens after click.

When unavailable:

```text
disabled or absent according to final native layout
```

Do not show a fake enabled control with 0 credits.

---

# PART H — USAGE WINDOW

## 34. Window Chrome

Production:

```text
real NSWindow
real traffic lights
title text hidden
```

Approved:

```text
no “用量” text in titlebar
```

Do not draw custom traffic-light dots.

---

## 35. Usage Content Inset

Approved visual rhythm:

```text
~20 pt
```

Use:

```text
20 pt reference content padding
```

unless a native scroll/content view requires a nearby system metric.

---

## 36. Usage Section Spacing

Approved after refinement:

```text
section title → content: ~13 pt
major section bottom padding: ~24 pt
major section margin: ~24 pt
```

The sections are:

```text
账户
会话
限额重置额度
Token 使用
```

Keep this order.

---

## 37. Usage Group Surfaces

Reference:

```text
corner radius ~12 pt
padding ~14 pt
```

Production rule:

- use restrained native group backgrounds;
- thin system separators;
- no heavy card shadow;
- no independent glass layer per card.

---

## 38. Account Block

Content:

```text
email
default marker
account tools
```

Reference internal row minimum:

```text
~42 pt
```

Account tool buttons:

```text
native secondary buttons
~8 × 10 pt internal padding reference
```

Important implementation caveat:

Prototype account tools are not all guaranteed for v1 until protocol validation passes.

Do not fake unsupported switching.

---

## 39. Session Block

Primary:

```text
quota window / remaining
```

Secondary:

```text
reset time
last update
```

Use system secondary text.

Do not over-emphasize the last-update time.

---

## 40. Reset Credit Block

Primary:

```text
0 次可用
1 次可用
2 次可用
```

Secondary status may appear on the right or below.

No decorative icon required.

---

## 41. Token Metric Grid

Frozen 2 × 2 structure:

```text
今日
近30天费用
今日 token 用量
近30天 token 用量
```

Reference metric cell:

```text
padding ~17 pt
label 13 pt
value 22 pt
value top gap ~8 pt
```

Use thin separators.

Do not use four floating glass tiles.

---

## 42. 30-Day Chart

Approved reference:

```text
30 vertical slots
chart plot height ~164 pt
chart horizontal inset ~16 pt
chart top padding ~32 pt
chart bottom padding ~20 pt
```

Bars:

- all 30 calendar slots rendered;
- zero-day bars may use a minimal baseline visual or true zero according to native chart clarity;
- bar rounding should be subtle;
- no gradient-filled marketing chart.

Tooltip:

```text
exact Token
authoritative fee or $--
```

Tooltip should feel native and compact.

---

# PART I — SETTINGS WINDOW

## 43. Window Chrome

Production:

```text
real NSWindow
real traffic lights
title text hidden
```

Approved:

```text
no “设置” text in titlebar
```

---

## 44. Settings Layout

For normal desktop width:

```text
sidebar left
detail right
```

Reference sidebar width:

```text
~200 pt
```

Sidebar sections:

```text
通用
悬浮窗
通知
隐私
高级
关于
```

Use native selection appearance.

Do not use pill tabs in production.

---

## 45. Settings Content Inset

Reference:

```text
20 pt
```

Group spacing:

```text
~20 pt
```

Group corner radius reference:

```text
~12 pt
```

Setting row:

```text
minimum height ~58 pt
padding ~15 × 16 pt
```

Secondary description:

```text
4 pt below primary label
```

---

## 46. Binary Controls

Frozen:

```text
native Apple switch style only
```

SwiftUI:

```swift
Toggle(...)
    .toggleStyle(.switch)
```

Never render:

```text
ON
OFF
```

as the visible control.

Do not custom-draw the switch geometry from the HTML.

---

## 47. Orb Size Slider

Frozen interaction:

```text
native Slider
realtime resize
```

Display:

```text
minimum
slider
maximum
current value
```

Current prototype range:

```text
64 — 180
```

Default:

```text
90 pt
```

Recommended value label:

```text
90 pt
```

rather than `90 px` in native macOS implementation.

The slider’s active tint may use system accent color.

Do not use the status green solely because working state is green.

---

## 48. Settings Groups

### General

```text
Language
Launch at Login
```

### Floating Window

```text
Show Floating Window
Always on Top
Lock Position
Orb Size Slider
```

### Monitoring / Notifications

```text
Pause Monitoring
Waiting Approval Notification
Task Complete Notification
```

### Privacy

```text
Hide Account Info
```

### Advanced

May include:

```text
Refresh
Open Codex
Open Log Folder
```

### About

```text
Version
build information
```

---

# PART J — ICONOGRAPHY

## 49. SF Symbols First

Use SF Symbols for standard system concepts.

Rules:

```text
monochrome
hierarchical or monochrome rendering
system label color
consistent optical size
```

Avoid:

```text
multicolor icons
custom emoji
web SVG icon packs
Lucide/Font Awesome in production
```

unless a genuinely product-specific icon is required.

---

## 50. Status Icons

Status should primarily use:

```text
colored dots / state ring
```

not separate pictograms.

Quick View may use:

```text
checkmark
small state dot
```

sparingly.

---

# PART K — LIQUID GLASS

## 51. Where Glass Is Required

Primary custom glass surfaces:

```text
Floating Orb
Quick View
```

Secondary/native glass may naturally appear in:

```text
system menu-bar / popover material
native toolbar/control layers
```

---

## 52. Where Glass Is Not Required

Do not force custom Liquid Glass on:

```text
every Usage section
every Settings group
30-day chart
standard switch
standard slider
standard alert
context menu
```

System-native appearance wins.

---

## 53. Glass Strength

Target:

```text
restrained
clear enough to read
not opaque white
not heavily blurred
not luminous
```

No “glass card inside glass card inside glass window”.

---

## 54. Glass Outline

Do not add a generic 1 px white border to every glass component.

The approved **status capsule** is the explicit exception: its white outline is retained.

For Orb/Quick View:

- use system Glass edge behavior;
- add custom edge only if readability requires it after native prototype review.

---

# PART L — MOTION

## 55. State Motion

Only:

```text
Thinking / Working -> green brightness breathing
Waiting Approval -> yellow brightness breathing
```

Reference duration:

```text
~0.8 s
```

No size pulse.

No spring bounce.

No glow pulse.

---

## 56. Completion / Failure Timing

Frozen:

```text
Completed:
constant green, 5 seconds

Failed / Interrupted / System Error:
constant red, 15 seconds
```

No animation is required during these retention states.

---

## 57. Window Motion

Use standard macOS window/popover behavior.

Do not add custom entrance animations unless they are subtle and system-consistent.

Quick View may use a short opacity/scale transition only if native panel presentation feels abrupt; default to minimal motion.

---

# PART M — ACCESSIBILITY

## 58. Reduce Motion

When enabled:

```text
disable breathing animation
keep semantic colors and positions
```

---

## 59. Reduce Transparency

Respect system preference.

The app must remain readable when transparency is reduced.

Do not force blur.

---

## 60. Color Independence

Status information is never color-only.

Examples:

```text
Menu Bar -> dot position
Quick View -> textual state
Orb click -> textual state in Quick View
```

---

## 61. VoiceOver Labels

Menu Bar capsule:

```text
“Codex Monitor，工作中”
```

Orb:

```text
“Codex Monitor，工作中，剩余额度 42%”
```

Settings controls use standard native labels.

---

# PART N — LIGHT / DARK APPEARANCE

## 62. Appearance Support

Must support:

```text
Light
Dark
Auto/System
```

Do not create a separate custom dark palette unless required.

System semantic materials adapt automatically.

---

## 63. Status Capsule Contrast

The approved capsule uses a dark body and white outline.

Validate in:

```text
light desktop/menu bar
dark desktop/menu bar
high contrast
```

The capsule may need subtle system-material adaptation while preserving the frozen B shape and white-outline concept.

---

# PART O — RESPONSIVE WINDOW RULES

## 64. Usage

Recommended initial production size:

```text
~560–640 pt wide
~620–720 pt tall
```

This is a recommendation, not frozen product geometry.

Minimum width should preserve:

```text
2-column Token metric grid
readable account tools
30-day chart
```

Allow vertical scrolling if content exceeds the window.

---

## 65. Settings

Recommended initial size:

```text
~620–700 pt wide
~520–620 pt tall
```

This is a recommendation, not frozen product geometry.

At narrow width:

- keep sidebar usable;
- do not collapse into a phone/iOS-style screen unless future product work explicitly requests it.

---

# PART P — DESIGN QA

## 66. Forbidden Visual Patterns

Reject implementation if any of these appear:

```text
large hero gradients
neon glow
oversized typography
SaaS dashboard cards
web-style navbar
glass on every content block
custom imitation traffic lights
custom imitation Apple switch
custom imitation Apple slider
floating rounded rectangles around every text row
animated percentage text
Hover info panel
```

---

## 67. Required Visual Review Matrix

Before UI is considered finished, capture screenshots on real macOS 26 for:

```text
Light appearance
Dark appearance
Reduce Motion
Reduce Transparency
100% / Retina display
different desktop wallpapers
Orb 64 pt
Orb 90 pt
Orb 180 pt
Menu Bar idle
Menu Bar working
Menu Bar waiting
Menu Bar red error
Quick View
Menu popup
Usage
Settings
```

---

## 68. Native-vs-Prototype Rule

If there is a conflict between:

```text
HTML visual imitation
```

and:

```text
correct native Apple behavior
```

use correct native Apple behavior **unless the conflict changes a frozen product decision**.

Examples:

```text
HTML fake traffic lights
-> replace with real NSWindow traffic lights

HTML custom switch
-> replace with native Toggle

HTML fake Slider
-> replace with native Slider

HTML glass gradients
-> replace with native Liquid Glass
```

But do not change:

```text
B status capsule
white capsule outline
state dot mapping
Orb 90 pt default
Ring/state relationship
single-click Quick View
no Hover
Usage section order
Settings control semantics
```

---

# PART Q — CODEX IMPLEMENTATION DIRECTIVE

## 69. Mandatory UI Implementation Rules

Codex must treat the following as hard constraints:

```text
1. Build a real native macOS app.
2. Do not port the HTML/CSS directly.
3. Use SwiftUI + AppKit.
4. Use Apple-native Liquid Glass on macOS 26+.
5. Use real NSWindow traffic lights.
6. Use real native Toggles, Sliders, Pickers and context menus.
7. Preserve approved component proportions and spacing hierarchy.
8. Preserve B · Balanced Menu Bar capsule with white outline.
9. Preserve the Floating Orb 90 pt default and proportional resizing.
10. Do not implement Hover.
11. Quick View is read-only.
12. Usage and Settings remain restrained content windows, not glass dashboards.
13. Use SF Symbols/system icons before introducing custom icons.
14. Respect accessibility settings.
15. Any visual deviation from a frozen item must be documented before implementation.
```

---

## 70. Apple Design Skill

Before implementing production UI, Codex should read and follow the supplied Apple Design skill:

```text
emilkowalski/skills — apple-design
```

Use that skill as an additional Apple-native design constraint.

If any skill recommendation conflicts with a frozen product decision in this spec:

```text
frozen product decision wins
```

If it only improves native spacing, typography, control behavior, accessibility, or system convention:

```text
follow the skill
```

---

# PART R — FREEZE STATUS

## 71. Frozen Design Decisions

These are approved and should not change casually:

```text
Apple-native restrained visual direction
macOS-only
Liquid Glass concentrated on functional/floating surfaces
B · Balanced Menu Bar capsule
white capsule outline retained
three-dot state mapping
Apple semantic green/yellow/red/gray
~0.8 s brightness-only breathing
default Orb = 90 pt
Orb ring ≈ 90% diameter
ring ≈ 7 pt at 90 pt base
center percentage remains static
no Hover
single-click read-only Quick View
Quick View no pointer triangle
Menu popup three-block structure
Usage section order
Usage spacing is intentionally less compact
Settings uses native window chrome
Usage uses native window chrome
title text hidden in Usage/Settings titlebars
all binary Settings use native switches
Orb size uses native Slider and updates in realtime
system icons / SF Symbols preferred
Completed green retention = 5 s
red terminal retention = 15 s
```

---

## 72. Items Requiring Native Optical Validation

These may move slightly after a real macOS prototype:

```text
exact Menu Bar capsule point width/height by ±1–2 pt
exact Quick View width within ~340–360 pt
exact menu popup width within ~330–350 pt
exact Usage/Settings initial window dimensions
native Liquid Glass intensity
extreme-size Orb stroke optical clamp
```

These are implementation tuning items, not permission to redesign the product.

---

## 73. Next Document

Next:

```text
09_USER_FLOWS_INTERACTION_AND_EDGE_CASES
```

It should specify end-to-end behavior for:

```text
first launch
Codex disconnected
Codex reconnect
working
waiting approval
completion
failure
multi-thread priority
Orb drag/resize
Quick View
right-click menu
Usage
reset-credit consumption
Settings
pause monitoring
launch at login
notifications
account changes
sleep/wake
app quit/relaunch
```
