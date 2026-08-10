# Codex Monitor — Master PRD & Codex Build Instructions v1.0

> **MASTER SOURCE OF TRUTH**
>
> Platform: macOS only  
> Production target: macOS 26+  
> Stack: SwiftUI + AppKit + Swift Concurrency + SQLite  
> Visual reference: `00_APPROVED_VISUAL_REFERENCE_v1.9.html`  
> Product status: Core UI / interaction direction approved; protocol capabilities still subject to P0 validation  
> Implementation rule: **DO NOT REDESIGN THE PRODUCT**

---

# 0. Codex: Read This First

You are implementing **Codex Monitor**, a native macOS utility that monitors the user’s Codex runtime, account usage, quota, session Token usage, reset credits, and task state.

Before writing production UI code:

1. Read this file completely.
2. Read every referenced specification in this folder.
3. Read the Apple Design skill:
   - `https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md`
4. Run the P0 protocol-validation plan in `10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md`.
5. Produce a P0 report.
6. Do **not** proceed to polished production UI until the hard P0 gates pass.

The approved HTML file is a **visual reference only**. It is not the production implementation language and must not be ported as HTML/CSS into the app.

Production must be a real native macOS application.

---

# 1. Product Definition

Codex Monitor is a lightweight macOS menu-bar utility with an optional floating orb.

Its job is to let the user know, at a glance:

```text
Is Codex connected?
Is it idle, thinking, working, waiting for approval, completed, failed, interrupted, or in a system-error state?
Which task is currently most important?
What is the current action?
How long has the current session been running?
How many Tokens has the current session used?
What account is active?
What plan/account type is active?
What authoritative quota windows are available?
What percentage remains?
When do limits reset?
How many reset credits are available?
What did the last 30 days of Token usage look like?
```

It must feel like an Apple system utility, not a SaaS dashboard.

---

# 2. Primary User Experience

The product has seven primary surfaces:

```text
1. Menu Bar status capsule
2. Menu Bar popup
3. Floating Orb
4. Single-click Quick View
5. Orb right-click native context menu
6. Usage window
7. Settings window
```

There is **no Hover information feature**.

Hover was explicitly removed from the product.

---

# 3. Core Scope — v1

v1 includes:

```text
Codex runtime state monitoring
multi-thread state aggregation
Menu Bar status capsule
Floating Orb
single-click read-only Quick View
native right-click context menu
account display
plan/account-type display when authoritative
quota/rate-limit display
quota reset time
earned reset-credit count
explicit reset-credit consumption with confirmation
current Session Token usage
30-day account Token usage
local SQLite history
Usage window
Settings window
Launch at Login
optional approval notification
optional task-complete notification
privacy setting to hide account info
automatic reconnect
sleep/wake reconciliation
multi-display Orb restoration
```

---

# 4. Explicitly Out of Scope — v1

Do not add these unless the user later approves a product revision:

```text
Hover information panel
direct approval/decline of Codex authorization requests
web dashboard
cloud sync of Monitor history
remote monitoring
mobile companion app
team/workspace management
estimated billing when no authoritative fee exists
arbitrary credential storage
copying Codex OAuth/API credentials
private backend integration
screen scraping
Codex UI accessibility scraping
primary dependence on JSONL log tailing
```

---

# 5. Product Safety / Integrity Rules

These rules are hard constraints:

```text
Never guess approval state.
Never guess quota from Token usage.
Never estimate fee and present it as authoritative.
Never store Codex access tokens, refresh tokens, API keys, cookies, or Authorization headers.
Never terminate Codex when Codex Monitor quits.
Never require Codex Monitor to own a task merely to observe it.
Never silently use private/unstable backend APIs to make the product appear complete.
```

When data is unavailable:

```text
show unavailable honestly
```

Examples:

```text
quota unavailable -> --
fee unavailable -> $--
email unavailable -> hide the field
```

---

# 6. Runtime State Machine — FROZEN

The internal states are:

```text
DISCONNECTED
PAUSED
IDLE
THINKING
WORKING
WAITING_APPROVAL
COMPLETED
INTERRUPTED
FAILED
SYSTEM_ERROR
```

Global state priority:

```text
SYSTEM_ERROR / FAILED / INTERRUPTED
>
WAITING_APPROVAL
>
WORKING / THINKING
>
COMPLETED
>
IDLE
>
DISCONNECTED
```

If multiple Threads exist, Menu Bar and Floating Orb show the highest-priority global state.

Detailed behavior is defined in:

```text
04_STATE_ENGINE_AND_EVENT_MAPPING_v1.1_FROZEN.md
```

Do not reinterpret the priority order.

---

# 7. Frozen State Presentation

## 7.1 Idle

```text
Menu Bar:
all 3 dots green constant

Floating Orb:
green constant ring

Quick View:
空闲
```

## 7.2 Thinking / Working

```text
Menu Bar:
dot 1 green brightness breathing

Floating Orb:
green ring brightness breathing

Quick View:
思考中 / 工作中
one-line current action
```

Breathing:

```text
~0.8 s
brightness only
no scale
no position change
no glow
```

The center percentage never scales or pulses.

## 7.3 Waiting Approval

```text
Menu Bar:
dot 2 yellow brightness breathing

Floating Orb:
yellow ring brightness breathing

Quick View:
等待授权
等待你在 Codex 中确认
```

Monitor must not provide approve/decline controls.

## 7.4 Completed

```text
constant green
retain 5 seconds
then recompute global state
```

## 7.5 Failed / Interrupted / System Error

```text
Menu Bar:
dot 3 red constant

Floating Orb:
red constant ring

retention:
15 seconds
```

After 15 seconds, recompute global state.

If a new authoritative Turn starts earlier, the new state wins immediately.

---

# 8. Menu Bar Status Capsule — FROZEN

Selected visual:

```text
B · Balanced
```

Reference geometry:

```text
48 × 22 pt optical target
dot diameter ≈ 7 pt
white capsule outline retained
```

The user explicitly reviewed a version without the white outline and chose to keep the prior outlined version.

Therefore:

```text
DO NOT remove the white capsule outline.
```

A ±1–2 pt native optical adjustment is allowed only after testing in the real macOS menu bar.

Do not change the B proportion into a substantially different capsule.

---

# 9. Floating Orb — FROZEN

Default:

```text
90 × 90 pt
```

Behavior:

```text
freely resizable
all visual content scales proportionally
size remembered
position remembered
Always on Top remembered
Lock Position remembered
visibility remembered
```

Reference ring:

```text
~90% of Orb diameter
~7 pt stroke at 90 pt Orb
```

Center:

```text
remaining % of the most constrained authoritative quota window
```

Example:

```text
primary remaining = 78%
secondary remaining = 42%
Orb center = 42%
```

If no authoritative quota exists:

```text
--
```

Important:

```text
ring color = runtime state
center number = quota remaining
```

Low quota must not recolor the runtime ring.

---

# 10. Floating Orb Resizing

There are two synchronized resize mechanisms:

```text
direct resize
Settings native Slider
```

Single source of truth:

```text
AppSettings.orbSize
```

Current recommended safety range:

```text
64–180 pt
```

Default:

```text
90 pt
```

The user-facing Settings control should display native point terminology:

```text
90 pt
```

not web/CSS pixels.

The Slider must resize the Orb in realtime.

If the user manually resizes the Orb while Settings is open, the Slider must update live.

---

# 11. Orb Interaction — FROZEN

```text
single left click
→ toggle Quick View

right click
→ native context menu

drag
→ move Orb if unlocked

direct resize
→ resize Orb

Hover
→ no information behavior
```

Do not implement a Hover card, Hover tooltip, Hover expansion, or Hover data panel.

---

# 12. Quick View — FROZEN

Quick View is read-only.

No:

```text
buttons
switches
approval controls
pointer triangle
```

Use a borderless/nonactivating panel rather than an arrowed popover.

Approved hierarchy:

```text
Codex                            time
● 工作中

Task title
one-line current action

Model · runtime
Session Token · remaining quota
```

Example:

```text
Codex
● 工作中                         18:56

Codex Monitor App
正在修改 3 个文件

GPT-5.6 Sol · 运行 12:43
本会话 644.38万 Token · 剩余额度 42%
```

Disconnected:

```text
○ Codex 未连接
```

No “Open Codex” button inside Quick View.

Open Codex belongs in the menu/right-click menu/Advanced settings.

---

# 13. Quick View Placement

The panel must never be clipped off-screen.

Preferred horizontal side:

```text
Orb on left half
→ panel to the right

Orb on right half
→ panel to the left
```

Vertical:

```text
center panel around Orb center
then clamp into NSScreen.visibleFrame
```

If preferred horizontal side cannot fit:

```text
try opposite side
then clamp
```

No pointer arrow.

---

# 14. Orb Right-Click Menu — FROZEN DIRECTION

Use a real `NSMenu`.

Order:

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

Use native checkmarks for stateful menu items.

Do not embed custom Toggle controls in `NSMenu`.

---

# 15. Menu Bar Popup — FROZEN STRUCTURE

Use:

```text
NSPopover
+
SwiftUI content
```

Three blocks only:

```text
Block 1:
Codex runtime state / current activity

Block 2:
account / plan / quota / reset credit / immediate reset

Block 3:
Usage
Settings
Show/Hide Floating Window
Quit
```

Do not turn this into a mini dashboard.

Approved spacing was intentionally increased from an earlier dense version.

Do not compress it back.

---

# 16. Menu Bar Popup Icons

Four action icons share the same physical container.

Use Apple-flat/system iconography.

Preferred:

```text
Usage -> SF Symbols chart symbol
Settings -> 2D gearshape
Floating Window -> simple circular/orb symbol
Quit -> power
```

The Floating Window glyph may be optically slightly larger inside the same icon container.

Do not use colorful app icons.

---

# 17. Account Model

Primary source of truth:

```text
Codex app-server
```

Display when authoritative:

```text
email
plan/account type
default/current account marker where supported
```

Default privacy behavior:

```text
show full email
```

Setting:

```text
Hide Account Info
```

When enabled:

```text
mask account identity in Monitor UI
```

Do not rewrite historical database rows merely because masking is enabled.

Never store Codex credentials.

---

# 18. Dynamic Quota Model

Do not hard-code:

```text
5 hour
weekly
```

The backend may expose:

```text
primary
secondary
only one
or future variants
```

Normalize dynamically.

Authoritative:

```text
usedPercent
resetsAt
window duration
```

Remaining:

```text
100 - usedPercent
```

clamped to:

```text
0...100
```

Orb displays:

```text
minimum remaining of all authoritative active windows
```

---

# 19. Reset Credits

Read via supported app-server surface.

Display:

```text
0 次可用
1 次可用
2 次可用
...
```

The count is authoritative.

If detailed credit rows are absent:

```text
do not invent expiry/details
```

---

# 20. Immediate Reset

This changes server/account state and must be treated carefully.

Enable only when:

```text
connected
supported
availableCount > 0
not already submitting
```

Before consuming:

```text
native confirmation required
```

Suggested text:

```text
使用 1 次限额重置额度？

这会立即消耗 1 次可用重置额度，并重置符合条件的 Codex 用量限额。
```

Buttons:

```text
取消
立即重置
```

Use one UUID idempotency key per logical attempt.

If a transport retry occurs:

```text
reuse the same idempotency key
```

After any consume response:

```text
refetch account/rateLimits/read
```

Never decrement the credit count locally and assume success.

---

# 21. Token Usage

Separate three concepts:

```text
current Thread/Session Token usage
account historical Token usage
quota/rate-limit percentage
```

They are not interchangeable.

Current Session:

```text
thread/tokenUsage/updated
```

Account history:

```text
account/usage/read
```

Quota:

```text
account/rateLimits/*
```

Do not infer one from another.

---

# 22. Usage Window — FROZEN STRUCTURE

Use a real native `NSWindow`.

Real macOS traffic-light buttons.

Hide title text:

```text
no “用量” title in the top titlebar
```

Approved content order:

```text
账户
会话
限额重置额度
Token 使用
```

Do not add internal tabs such as:

```text
概览
账户
会话
用量
设置
```

The user explicitly rejected this type of in-page navigation.

---

# 23. Usage Metrics — FROZEN

Top 2 × 2 metric structure:

```text
今日费用
近30天费用

今日 token 用量
近30天 token 用量
```

Prototype example:

```text
今日                     $--
近30天费用               $77.53
今日 token 用量          0 token
近30天 token 用量        1.33亿 token
```

Examples are visual data samples, not values to hard-code.

---

# 24. Usage Cost Rule — FROZEN

If authoritative cost exists:

```text
show it
```

If not:

```text
$--
```

Never:

```text
Token × public pricing
```

and then display the result as a real account charge.

---

# 25. 30-Day Chart — FROZEN

Always:

```text
30 local calendar-day positions
```

including zero-use days.

Do not compress the chart to “30 days with activity”.

Bar hover is allowed because this is chart interaction.

Tooltip:

```text
date
exact Token count
authoritative fee or $--
```

Example:

```text
2026年8月7日
Token：6,243,800
费用：$4.21
```

or:

```text
费用：$--
```

---

# 26. Token Formatting

Chinese:

```text
842        -> 842 token
12,800     -> 1.28万 token
6,243,800  -> 624.38万 token
133,000,000-> 1.33亿 token
```

English:

```text
K
M
etc.
```

Storage remains exact integer.

Formatting is presentation only.

---

# 27. Settings Window — FROZEN DIRECTION

Use a real native `NSWindow`.

Real macOS traffic lights.

Hide title text:

```text
no “设置” title in the top titlebar
```

Sections:

```text
通用
悬浮窗
通知
隐私
高级
关于
```

Prefer native macOS sidebar/list presentation.

Do not make it look like a mobile/iOS Settings screen.

---

# 28. Settings Controls — FROZEN

Every binary setting uses:

```swift
Toggle(...)
    .toggleStyle(.switch)
```

Do not render literal visible:

```text
ON
OFF
```

Affected:

```text
Launch at Login
Show Floating Window
Always on Top
Lock Position
Pause Monitoring
Waiting Approval Notification
Task Complete Notification
Hide Account Info
```

---

# 29. Settings: Floating Orb Size

Use native:

```swift
Slider
```

Realtime bound to:

```text
orbSize
```

No custom web-style slider.

The user explicitly requested a slider because they want realtime size adjustment.

---

# 30. Launch at Login

Use:

```text
ServiceManagement
SMAppService.mainApp
```

Toggle must reflect the actual system registration state.

If registration fails:

```text
revert/reconcile the Toggle
show concise native error
```

Do not display ON if the system operation failed.

---

# 31. Notifications

Use:

```text
UNUserNotificationCenter
```

Defaults:

```text
Waiting Approval Notification = OFF
Task Complete Notification = OFF
```

Ask for system notification permission only when the user enables a feature that needs it.

Do not request permission automatically at first launch.

---

# 32. Pause Monitoring

When ON:

```text
presentation enters PAUSED
incoming task events are not applied to user-facing state
last quota may remain as stale cached value
```

On resume:

```text
reconcile live Codex state
```

Do not simply resume the old pre-pause task state blindly.

---

# 33. Local Persistence

Use:

```text
SQLite
```

Recommended wrapper:

```text
GRDB.swift
```

unless zero-third-party dependency policy is selected.

Store permanently:

```text
daily Usage
thread usage
threads
turn history
```

Store diagnostic Monitor events with a reasonable retention policy.

Do not store credentials.

Preferences use:

```text
UserDefaults / AppStorage
```

---

# 34. Floating Position Persistence

Do not store only absolute pixels.

Store:

```text
display identifier
normalized X
normalized Y
```

On restore:

```text
try original display
fallback to main screen
reconstruct position
clamp into NSScreen.visibleFrame
```

The Orb must never restore fully off-screen.

---

# 35. Display Changes

If the external display is removed:

```text
move Orb to an available screen
preserve relative position where possible
clamp into visibleFrame
```

If Dock/menu-bar geometry changes:

```text
use current visibleFrame
```

not a stale cached frame.

---

# 36. App Process Behavior

Recommended:

```text
LSUIElement = true
```

Codex Monitor behaves as a menu-bar/accessory utility.

No permanent Dock icon is required.

Usage and Settings still open as real native windows.

Closing those windows:

```text
does not quit Monitor
```

---

# 37. Quit Behavior

Quit Monitor:

```text
persist settings
flush database
disconnect Monitor client
close Monitor surfaces
terminate Codex Monitor
```

Do not:

```text
quit Codex
kill Codex Desktop
kill a Codex-owned app-server
```

---

# 38. Native Window Architecture

Use AppKit where exact window behavior is required.

Recommended:

```text
NSStatusItem
→ status capsule

NSPopover
→ Menu Bar popup

NSPanel
→ Floating Orb

NSPanel
→ no-arrow Quick View

NSWindow
→ Usage

NSWindow
→ Settings

NSMenu
→ Orb right-click context menu
```

SwiftUI hosts content.

Do not force all surfaces into generic SwiftUI Window scenes if behavior becomes inaccurate.

---

# 39. Native Liquid Glass — HARD REQUIREMENT

Target:

```text
macOS 26+
```

Use Apple-native Liquid Glass APIs for custom glass surfaces.

Primary custom glass surfaces:

```text
Floating Orb
Quick View
```

Do not simulate Apple Liquid Glass with copied CSS gradients/shadows.

Usage / Settings are content windows and should remain restrained.

Do not put every section inside a glass card.

---

# 40. Apple-Style Hierarchy

Liquid Glass should act as a functional/navigation/floating layer.

Do not create:

```text
glass card inside glass card inside glass card
```

System controls remain native.

Examples:

```text
Toggle -> native
Slider -> native
Picker -> native
NSMenu -> native
traffic lights -> native
```

---

# 41. Design Anti-Patterns — REJECT

Reject the implementation if it introduces:

```text
web navigation bar
large hero gradient
neon glow
gaming HUD
SaaS analytics dashboard
visionOS-heavy floating cards
custom fake traffic lights
custom fake Apple switches
custom fake Slider
animated percentage scaling
Hover information panel
glass on every block
multicolor web icon packs
```

---

# 42. Typography

Use only the system font.

```text
SF Pro / system font
```

No bundled custom font.

Reference hierarchy:

```text
Primary status: ~17 pt semibold
Usage large metric: ~22 pt
Orb % at 90 pt: ~24 pt bold
Section heading: ~15 pt semibold
Body/task title: ~13–14 pt
Metadata: ~12–13 pt
```

Allow native controls to use system-native type metrics.

---

# 43. Spacing

Use an Apple-like restrained spacing scale.

Reference values:

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

Approved Menu popup and Usage layouts deliberately have more breathing room than earlier drafts.

Do not over-compress them.

---

# 44. Menu Popup Reference Spacing

Reference:

```text
outer inset: ~15–16
major divider vertical margin: ~14
block row gap: ~8
menu action gap: ~6
menu action vertical padding: ~8
```

Use native optical tuning, not exact web pixels.

---

# 45. Usage Reference Spacing

Reference:

```text
window content inset: ~20
section title → content: ~13
major section separation: ~24
group internal padding: ~14
metric cell padding: ~17
```

Keep the page calm and readable.

---

# 46. Settings Reference Spacing

Reference:

```text
content inset: ~20
group spacing: ~20
setting row min height: ~58
row padding: ~15 × 16
secondary description gap: ~4
```

Again, native optical alignment wins over copying CSS measurements literally.

---

# 47. Accessibility

Must support:

```text
VoiceOver
Reduce Motion
Reduce Transparency
Light Mode
Dark Mode
```

Reduce Motion:

```text
disable breathing
retain state color and dot position
```

Reduce Transparency:

```text
respect the system
do not force blur
```

Status must not depend on color alone:

```text
Menu Bar -> dot position
Quick View -> text
```

---

# 48. Runtime Current Action

Keep it concise.

Examples:

```text
正在思考
正在修改 App.swift
正在修改 3 个文件
正在运行命令
正在调用工具
正在搜索
正在生成图片
正在整理上下文
```

One line.

Do not expose hidden reasoning content.

Do not show a long raw command if a sanitized summary is available.

---

# 49. Task Title

Priority:

```text
Thread/Session title
>
first user-message preview
```

One line.

Truncate in compact surfaces.

Do not store the full conversation merely to generate a title.

---

# 50. Reconnect

Connection should be event-driven and resilient.

Do not poll the full Codex state every 0.5 seconds.

The 0.8-second rhythm is an animation only.

Suggested reconnect backoff:

```text
0.5 s
1 s
2 s
4 s
8 s
cap around 15 s
+
jitter
```

On reconnect:

```text
initialize
fetch account
fetch rate limits
fetch usage if needed
reconcile loaded threads
resume events
```

---

# 51. Mac Sleep / Wake

Sleep is not task failure.

On wake:

```text
revalidate connection
refresh account/rate limits
refresh stale usage
reconcile loaded threads
```

No user Refresh should normally be required.

---

# 52. Account Changes

Use an account epoch/generation.

If account changes:

```text
increment epoch
discard stale old-account responses
fetch new account data
fetch new limits
fetch new usage
scope SQLite rows correctly
```

Never merge different users' Usage histories.

---

# 53. Connection Generation

Use a connection epoch/generation.

After reconnect:

```text
late events/responses from prior connection cannot overwrite current state
```

---

# 54. P0 Validation — HARD GATE

Read and execute:

```text
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md
```

Production UI must not be polished first.

Required P0 proof includes:

```text
installed Codex version
stable schema generated from installed binary
local supported transport
initialize handshake
account/read
rateLimits/read
usage/read exact schema
loaded Threads
Desktop-created Turn visibility
Item lifecycle
Session Token event
approval lifecycle passive visibility
turn completion mapping
reconnect
account change behavior
```

---

# 55. Approval Visibility Gate

The yellow state is allowed only if P0 proves a passive Monitor client can authoritatively observe the approval lifecycle.

If not:

```text
do not guess yellow state
```

A product/spec revision is required.

---

# 56. Runtime Visibility Gate

If Monitor cannot observe Codex Desktop-created Turns authoritatively:

```text
NO-GO
```

Do not proceed by screen scraping, credential extraction, or private backend integration.

---

# 57. Account Usage Gate

If account Usage fields are partially supported:

```text
ship supported fields
hide/mark unsupported fields
```

Example:

```text
Tokens available
cost absent
→ tokens show normally
→ cost = $--
```

Do not fake completion.

---

# 58. Multi-Account Prototype Caveat

The approved Usage prototype contains account-tool concepts.

They are not permission to store credentials.

If P0 proves a safe official account-switching capability:

```text
implement it
```

If not:

```text
hide/disable/hand off to Codex
```

Core Monitor must still work.

---

# 59. Required Project Structure

Recommended:

```text
CodexMonitor/
├── App/
├── Transport/
├── Domain/
├── Persistence/
├── Repositories/
├── Presentation/
├── UI/
│   ├── DesignSystem/
│   ├── MenuBar/
│   ├── FloatingOrb/
│   ├── QuickView/
│   ├── Usage/
│   └── Settings/
├── System/
├── Tools/
│   └── P0Probe/
└── Tests/
```

Do not place all logic in one AppDelegate or one giant SwiftUI file.

---

# 60. Architectural Responsibility

Transport:

```text
Codex JSON-RPC / WebSocket / protocol decoding
```

Domain:

```text
normalized events
state engine
quota models
account models
```

Persistence:

```text
SQLite / migrations
```

Repositories:

```text
authoritative data orchestration
```

Presentation:

```text
immutable view state
formatters
```

UI:

```text
render only
```

System:

```text
window coordination
launch at login
notifications
screen placement
```

---

# 61. Main Actors / Services

Recommended:

```text
CodexConnectionActor
MonitorCoordinator
DatabaseActor
AccountStoreActor
RateLimitStoreActor
UsageStoreActor
ThreadUsageStoreActor
NotificationCoordinator
WindowCoordinator
```

Presentation:

```text
@MainActor AppPresentationStore
```

Do not let raw JSON-RPC notifications mutate SwiftUI state directly.

---

# 62. App Startup Order

```text
launch
↓
load settings
↓
open/migrate SQLite
↓
load cache
↓
create Menu Bar
↓
restore Orb
↓
render immediately
↓
connect Codex
↓
initialize
↓
fetch fresh snapshots
↓
reconcile runtime
↓
process realtime events
```

The app should not appear blank while waiting for Codex.

---

# 63. Database

Recommended:

```text
SQLite + GRDB.swift
```

Use WAL.

Use migrations.

Never destroy/recreate the user's DB on migration failure.

Historical Usage should survive app restart.

---

# 64. CI / Test Strategy

CI must not require:

```text
real user ChatGPT account
real OAuth credentials
real reset credits
real Codex quota
```

Use sanitized fixtures captured after P0.

Test pyramid:

```text
many unit tests
many protocol/state fixture tests
database tests
mock app-server integration tests
few real local Codex manual/P0 tests
```

---

# 65. Required Fixtures

After P0, create sanitized fixtures for:

```text
disconnected
idle
thinking
working-command
working-file-change
waiting-approval
approval-resolved
completed
interrupted
failed
rate-limit-full
rate-limit-sparse-update
usage-snapshot
thread-token-update
account-change
```

Use them for deterministic tests.

---

# 66. Build Order — HARD ORDER

## Phase 0 — P0

Build:

```text
Tools/P0Probe
protocol schema capture
P0 report
```

Exit criterion:

```text
P0 accepted
```

## Phase 1 — Headless transport

Build:

```text
Swift local transport
JSON-RPC request routing
notification routing
server-request observation
initialize/reconnect
```

Exit:

```text
real Codex events print as sanitized normalized events
```

## Phase 2 — Domain/state engine

Implement frozen state machine.

Exit:

```text
fixtures + real events map correctly
```

## Phase 3 — Account/quota/usage adapter

Implement:

```text
account
rate limits
sparse merge
usage
thread Token
reset credit
```

Exit:

```text
normalized snapshots correct
```

## Phase 4 — SQLite

Implement:

```text
migrations
account history
daily usage
thread usage
turn history
```

Exit:

```text
restart preserves data
```

## Phase 5 — macOS utility shell

Implement:

```text
LSUIElement
NSStatusItem
NSPopover
Orb NSPanel
Quick View NSPanel
Usage NSWindow
Settings NSWindow
WindowCoordinator
```

Exit:

```text
all surfaces open/close correctly
```

## Phase 6 — Functional native UI

Implement approved layouts without over-polishing.

Exit:

```text
all user flows work
```

## Phase 7 — Design fidelity

Apply:

```text
native Liquid Glass
native spacing
B capsule
Orb material
Quick View
Usage/Settings design
```

Exit:

```text
visual QA against v1.9 reference
```

## Phase 8 — System integrations

```text
notifications
Launch at Login
Open Codex
accessibility
```

## Phase 9 — Release QA

```text
Light/Dark
Reduce Motion
Reduce Transparency
multiple displays
sleep/wake
reconnect
database migration
signed build
```

---

# 67. Codex Must Not Reorder P0 Behind UI

Do not say:

```text
“I'll build the UI first and hook up the backend later.”
```

That is explicitly rejected for this project.

The protocol truth must be validated first.

---

# 68. Implementation Checkpoints

At the end of each phase, create:

```text
PHASE_<N>_REPORT.md
```

with:

```text
what was implemented
tests run
screenshots if visual
known deviations
blocked items
files changed
next phase
```

Do not silently move on from a failed gate.

---

# 69. Visual Review Checkpoint

Before final UI approval, capture screenshots for:

```text
Menu Bar idle
Menu Bar working
Menu Bar waiting approval
Menu Bar red failure
Orb 64 pt
Orb 90 pt
Orb 180 pt
Quick View
Menu popup
Usage
Settings
Light
Dark
Reduce Motion
Reduce Transparency
```

Compare to:

```text
00_APPROVED_VISUAL_REFERENCE_v1.9.html
```

But remember:

```text
native Apple behavior overrides HTML imitation
```

unless doing so changes a frozen product decision.

---

# 70. Native UI Rules

Use:

```text
real NSWindow traffic lights
native Toggle
native Slider
native Picker
native NSMenu
native NSPopover
SF Symbols
system font
system colors
native Liquid Glass
```

Do not use:

```text
HTML/CSS
Electron
Tauri webview
React
web icon library
```

for the production app.

---

# 71. Technology Decision

Earlier prototype directions considered other stacks.

The approved production direction is now:

```text
SwiftUI + AppKit
```

Do not revert to Tauri/Rust without a new explicit product decision.

Rust is not required for v1.

---

# 72. macOS Version

Recommended minimum:

```text
macOS 26.0+
```

Reason:

```text
native Apple Liquid Glass is a core visual requirement
```

If older macOS support is later requested:

```text
pause and create a compatibility design/spec
```

Do not silently implement a fake-Liquid-Glass fallback and claim parity.

---

# 73. Apple Design Skill Requirement

Before production UI work, read:

```text
https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md
```

Treat it as an additional Apple-native implementation/design constraint.

Conflict handling:

```text
frozen product decision
>
general skill recommendation
```

If the skill improves:

```text
spacing
typography
native controls
accessibility
window convention
```

follow it.

---

# 74. Source-of-Truth Priority

If documents conflict, use this priority:

```text
1. this Master PRD
2. explicitly FROZEN specification
3. later-numbered specialist specification
4. approved visual reference v1.9
5. earlier draft/prototype
```

If there is still uncertainty:

```text
do not redesign
document the conflict
ask for product decision
```

---

# 75. Required Reference Files

This handoff bundle contains:

```text
00_APPROVED_VISUAL_REFERENCE_v1.9.html

04_STATE_ENGINE_AND_EVENT_MAPPING_v1.1_FROZEN.md
05_ACCOUNT_USAGE_QUOTA_AND_RESET_MODEL_v1.0.md
06_LOCAL_DATABASE_AND_SWIFT_DATA_LAYER_v1.0.md
07_MACOS_SWIFTUI_APPKIT_ARCHITECTURE_v1.0.md
08_DESIGN_SYSTEM_AND_COMPONENT_SPEC_v1.0.md
09_USER_FLOWS_INTERACTION_AND_EDGE_CASES_v1.0.md
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
```

Do not implement from the visual reference alone.

---

# 76. Definition of Done — Functional

v1 is functionally complete when:

```text
Codex connects automatically
runtime states are authoritative
multi-thread priority works
status capsule works
Orb works
Quick View works
right-click menu works
account/quota works to validated capability
Session Token works to validated capability
Usage works to validated capability
reset credit works safely
Settings work
Launch at Login works
notifications work
data persists
reconnect works
sleep/wake works
display restore works
quit does not quit Codex
```

---

# 77. Definition of Done — Design

Design is complete when:

```text
looks native on macOS 26
uses real Liquid Glass where appropriate
does not look like a web app
does not overuse Glass
B capsule matches approved proportion
white capsule outline remains
Orb material is restrained
state colors are correct
no scale/glow breathing
Quick View is clean/read-only
Menu popup has comfortable spacing
Usage has approved information order
Settings uses native switches/Slider
Usage/Settings titlebar text remains hidden
```

---

# 78. Definition of Done — Safety / Integrity

Pass only if:

```text
no Codex credential storage
no private backend dependency for core v1
no guessed approval state
no guessed quota
no estimated fee shown as actual
no screen scraping
no fake support for unsupported account switching
```

---

# 79. Definition of Done — Quality

Required:

```text
unit tests
state-engine tests
protocol fixture tests
database tests
mock integration tests
real P0 report
no obvious main-thread blocking
low idle CPU
no 0.5-second data polling loop
accessibility labels
Light/Dark support
Reduce Motion support
Reduce Transparency support
```

---

# 80. Final Instruction to Codex

Build the product described here.

Do not reinterpret it into a different app.

Do not “improve” the product by adding navigation, dashboards, Hover panels, extra analytics, decorative cards, or alternative state logic.

When the specification says **FROZEN**, treat it as fixed.

When a protocol capability is uncertain:

```text
validate it
```

When a capability is unavailable:

```text
degrade honestly
```

When native macOS provides the component:

```text
use the native component
```

When the approved HTML and correct Apple-native behavior differ:

```text
implement the Apple-native behavior
```

while preserving the frozen product intent.

The target is:

```text
a small, precise, native macOS utility
that feels like it belongs on the system,
gives the user trustworthy Codex status at a glance,
and never invents data merely to fill the interface.
```

---

# 81. First Command to Execute

Do **not** begin by creating polished SwiftUI views.

Begin with:

```text
Read:
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md
```

Then execute Phase 0 and produce:

```text
P0_REPORT.md
```

Only after the P0 GO/partial-GO decisions are recorded should production implementation proceed.
