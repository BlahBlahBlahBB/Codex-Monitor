# Codex Monitor — User Flows, Interaction & Edge Cases v1.0

> Status: **Product Flow Draft — Ready for implementation review**  
> Platform: macOS 26+  
> Depends on:
> - `04_STATE_ENGINE_AND_EVENT_MAPPING_v1.1_FROZEN.md`
> - `05_ACCOUNT_USAGE_QUOTA_AND_RESET_MODEL_v1.0.md`
> - `06_LOCAL_DATABASE_AND_SWIFT_DATA_LAYER_v1.0.md`
> - `07_MACOS_SWIFTUI_APPKIT_ARCHITECTURE_v1.0.md`
> - `08_DESIGN_SYSTEM_AND_COMPONENT_SPEC_v1.0.md`

---

## 1. Purpose

This document defines the end-to-end behavior of Codex Monitor from a user's point of view.

It covers:

- first launch
- Codex unavailable
- connection / reconnection
- idle
- thinking / working
- waiting approval
- completion
- failure / interruption / system error
- multi-thread aggregation
- Floating Orb
- Quick View
- Menu Bar popup
- right-click context menu
- Usage
- Settings
- reset-credit consumption
- notifications
- pause monitoring
- account changes
- sleep / wake
- launch at login
- quit / relaunch
- window and display edge cases

There is **no Hover feature**.

---

# PART A — FIRST LAUNCH

## 2. First Launch Sequence

Expected sequence:

```text
User launches Codex Monitor
↓
Load local settings
↓
Open / migrate local SQLite database
↓
Create Menu Bar status item
↓
Restore Floating Orb visibility / size / position
↓
Render cached state if available
↓
Start Codex connection
↓
Fetch account / quota / usage / loaded threads
↓
Reconcile UI with live Codex state
```

The app should feel available immediately.

Do not block the UI behind a full-screen loading state.

---

## 3. First Launch With No Cache

If there is no prior local state:

```text
Menu Bar -> disconnected / gray
Floating Orb -> gray ring + `--`
```

Then the app attempts to connect automatically.

No modal alert should appear merely because Codex is not currently running.

---

## 4. Notification Permission

Do not request notification permission immediately on first launch.

Default notification settings are:

```text
Waiting Approval Notification = OFF
Task Complete Notification = OFF
```

Request system notification authorization only when the user turns on a notification feature that requires it.

If macOS denies permission:

```text
setting can show unavailable / permission required
```

Do not repeatedly prompt.

---

# PART B — CODEX CONNECTION

## 5. Codex Already Running

Expected:

```text
Monitor launches
↓
connects automatically
↓
loads current account / limits / usage / active threads
↓
projects current global state
```

No manual refresh is required.

---

## 6. Codex Not Running

State:

```text
DISCONNECTED
```

UI:

```text
Menu Bar -> gray / inactive
Orb -> gray + `--`
Quick View -> Codex 未连接
```

Menu popup / right-click menu may offer:

```text
打开 Codex
```

No error modal.

---

## 7. Open Codex

From:

```text
Menu popup
Orb right-click menu
Settings > Advanced
```

Behavior:

```text
invoke NSWorkspace
↓
launch/focus Codex Desktop
↓
Monitor keeps reconnecting automatically
↓
once connection succeeds, live state replaces disconnected state
```

Do not require the user to press Refresh after Codex opens.

---

## 8. Connection Lost While Codex Is Running

Possible causes:

```text
Codex restart
app-server restart
transport failure
Mac sleep
temporary socket failure
```

Behavior:

```text
enter DISCONNECTED
retain cached account / usage history
do not present stale quota as live
Orb center -> `--`
start reconnect backoff
```

No red task-failure state should be invented from transport failure alone.

---

## 9. Reconnect

On successful reconnect:

```text
initialize
fetch account
fetch rate limits
fetch usage if needed
fetch loaded threads
reconstruct runtime state
resume realtime events
```

The UI should transition directly to the reconstructed authoritative state.

Example:

```text
disconnected
→ reconnect
→ active Turn exists
→ green breathing working state
```

No intermediate fake idle period is required.

---

# PART C — IDLE / ACTIVE STATES

## 10. Idle

Condition:

```text
connected
no active Turn
no higher-priority retained terminal state
```

UI:

```text
Menu Bar -> all 3 dots green constant
Orb -> green constant
Quick View -> 空闲
```

No animation.

---

## 11. Thinking

Condition:

```text
active Turn
reasoning / generic active state
```

UI:

```text
Menu Bar dot 1 -> green brightness breathing
Orb ring -> green brightness breathing
Quick View -> 思考中 / 正在思考
```

Animation:

```text
~0.8 s
brightness only
```

---

## 12. Working

Condition:

```text
active command / file / tool / search / image generation / other work item
```

UI:

```text
Menu Bar dot 1 -> green breathing
Orb -> green breathing
Quick View -> 工作中
```

Current action examples:

```text
正在修改 3 个文件
正在运行命令
正在调用工具
正在搜索
正在生成图片
正在整理上下文
```

Only one concise line.

---

# PART D — WAITING APPROVAL

## 13. Approval Requested

Condition:

```text
Codex cannot continue until user approval/authorization is resolved
```

UI:

```text
Menu Bar dot 2 -> yellow brightness breathing
Orb ring -> yellow brightness breathing
Quick View -> 等待授权
```

Quick View text:

```text
等待你在 Codex 中确认
```

No approve/decline buttons in Monitor.

---

## 14. Optional Approval Notification

If:

```text
Waiting Approval Notification = ON
```

post one native notification for the transition.

Do not notify repeatedly while the same approval request remains pending.

If multiple approval requests arrive for the same Turn:

```text
dedupe by request/turn identity
```

---

## 15. Approval Resolved

Behavior:

```text
approval resolved
↓
remove pending request
↓
derive current active state again
```

Example:

```text
WAITING_APPROVAL
→ user approves in Codex
→ command starts
→ WORKING
```

If approval is declined and Codex ends the Turn:

```text
follow authoritative turn completion state
```

---

# PART E — COMPLETION / FAILURE

## 16. Successful Completion

When an authoritative successful Turn completion arrives:

```text
state = COMPLETED
```

Presentation:

```text
constant green
Quick View -> 任务完成
```

Retention:

```text
5 seconds
```

After 5 seconds:

```text
recompute global state
```

If nothing else is active:

```text
IDLE
```

---

## 17. Task Complete Notification

If enabled:

```text
post one completion notification
```

If disabled:

```text
no notification
```

Notification is independent from the 5-second visual completion retention.

---

## 18. Failed

When authoritative Turn status is failed:

```text
state = FAILED
```

Presentation:

```text
Menu Bar dot 3 -> red constant
Orb ring -> red constant
Quick View -> 执行失败 / concise summary
```

Retention:

```text
15 seconds
```

Then recompute global state.

Failure remains stored in local history.

---

## 19. Interrupted

When authoritative Turn status is interrupted:

```text
state = INTERRUPTED
```

Presentation:

```text
red constant
15 seconds
```

Quick View:

```text
任务已中断
```

---

## 20. System Error

When Codex reports a system error:

```text
state = SYSTEM_ERROR
```

Presentation:

```text
red constant
15 seconds
```

Quick View should distinguish:

```text
Codex 异常
```

from a user task failure.

---

## 21. New Turn During Terminal Retention

Example:

```text
FAILED red retention begins
↓ 6 seconds later
new Turn starts on same Thread
```

Behavior:

```text
new authoritative active state wins immediately
```

Do not force the red state to remain for the entire 15 seconds.

---

# PART F — MULTI-THREAD AGGREGATION

## 22. Global Priority

Frozen:

```text
FAILED / INTERRUPTED / SYSTEM_ERROR
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

The Menu Bar and Orb always show the highest-priority global state.

---

## 23. Multi-Thread Example 1

```text
Thread A -> WORKING
Thread B -> WAITING_APPROVAL
```

Global:

```text
WAITING_APPROVAL
```

Quick View should prefer the thread causing the global state.

---

## 24. Multi-Thread Example 2

```text
Thread A -> WORKING
Thread B -> FAILED
```

Global:

```text
FAILED
```

After red retention expires:

```text
Thread A still WORKING
→ global returns to WORKING
```

---

## 25. Multi-Thread Example 3

```text
Thread A -> COMPLETED
Thread B -> WORKING
```

Global:

```text
WORKING
```

The completed state is not globally visible because a higher-priority active state exists.

---

# PART G — FLOATING ORB

## 26. Show / Hide

Sources:

```text
Menu popup
Orb right-click menu
Settings > Floating Window
```

All modify the same setting:

```text
orbVisible
```

If hidden:

```text
Quick View closes
Orb panel hides
visibility persists
```

---

## 27. Orb Default Size

First run:

```text
90 pt
```

Thereafter:

```text
restore user-selected size
```

---

## 28. Resize Via Settings Slider

Behavior:

```text
drag Slider
→ Orb resizes in realtime
→ ring / percentage / glass body scale proportionally
→ current value updates
→ persist with short debounce
```

No refresh or reopen required.

---

## 29. Direct Orb Resize

If direct resize interaction is enabled:

```text
user resizes Orb
→ same size source updates
→ Settings slider updates live if open
```

No separate size states.

---

## 30. Orb Drag

When unlocked:

```text
drag Orb body
→ move window
```

During drag:

```text
close Quick View
```

At drag end:

```text
persist normalized screen position
```

---

## 31. Lock Position

If ON:

```text
Orb cannot be dragged
```

Resize can remain available unless future product review says otherwise.

The lock is specifically a position lock.

---

## 32. Always On Top

If ON:

```text
apply floating window level immediately
```

If OFF:

```text
return to standard accessory panel behavior
```

No app restart.

---

# PART H — QUICK VIEW

## 33. Open

Single left click on Orb:

```text
toggle Quick View
```

No Hover.

No double-click action.

---

## 34. Content Selection

Quick View represents the thread responsible for the current global state.

Tie-break:

```text
1. higher state priority
2. most recent relevant state transition
```

If global state is idle:

```text
show global idle/account/session summary
```

---

## 35. Placement

Preferred:

```text
Orb left half -> panel right
Orb right half -> panel left
```

Vertically center with Orb, then clamp into visible frame.

If preferred side cannot fit:

```text
try opposite side
then clamp
```

No arrow.

---

## 36. Dismiss

Close on:

```text
second Orb click
click outside
Orb drag begins
Orb hidden
Usage opened
Settings opened
app quit
```

---

# PART I — ORB RIGHT-CLICK MENU

## 37. Menu Structure

Frozen direction:

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

Use native `NSMenu`.

---

## 38. Refresh

Manual refresh performs:

```text
account/read
rateLimits/read
usage/read
loaded thread reconciliation
```

Disable or ignore repeated clicks while already refreshing.

---

## 39. Stateful Menu Items

Use native checkmarks:

```text
始终置顶
锁定位置
```

Do not show custom toggles inside the context menu.

---

# PART J — MENU BAR POPUP

## 40. Open / Close

Left click status capsule:

```text
toggle native popover
```

Click outside:

```text
close
```

No duplicate popover.

---

## 41. Block 1 — Runtime

Shows:

```text
Codex state
last update / current time
one-line current action if relevant
```

No verbose logs.

---

## 42. Block 2 — Account / Quota

Shows available authoritative data:

```text
email
default marker if relevant
plan
remaining quota
reset credit count
Immediate Reset when available
```

If Hide Account Info is ON:

```text
mask email
```

---

## 43. Block 3 — Actions

Frozen:

```text
用量
设置
显示/隐藏悬浮窗
退出
```

Opening Usage / Settings closes the popover.

---

# PART K — USAGE WINDOW

## 44. Open

From:

```text
Menu popup
Orb right-click menu
```

Behavior:

```text
if Usage already open
→ activate/focus existing window

else
→ create/show one Usage window
```

Never create duplicates.

---

## 45. Close

Native red traffic-light button:

```text
close Usage window
```

Monitor process remains active.

---

## 46. Loading

Open immediately using cache.

If data is fresh:

```text
render immediately
optional background refresh
```

If stale:

```text
render cached values
mark/update as needed
refresh in background
```

Do not blank the whole page.

---

## 47. 30-Day Chart

Always show:

```text
30 calendar-day positions
```

Zero-use dates remain visible.

Hovering chart bars is allowed because it is chart interaction, not the removed Orb Hover feature.

Tooltip:

```text
exact Token
authoritative fee or $--
```

---

# PART L — RESET CREDIT

## 48. Reset Button Availability

Enable only when:

```text
connected
availableCount > 0
supported authoritative rate-limit surface exists
not already submitting
```

---

## 49. Reset Confirmation

Native confirmation:

```text
使用 1 次限额重置额度？

这会立即消耗 1 次可用重置额度，并重置符合条件的 Codex 用量限额。
```

Buttons:

```text
取消
立即重置
```

---

## 50. User Cancels

Behavior:

```text
close confirmation
do nothing
```

No API call.

---

## 51. Reset Success

Response:

```text
reset
or alreadyRedeemed
```

Behavior:

```text
show concise success feedback
refetch rate limits
update quota + credit count
```

The Orb percentage updates from the authoritative refreshed snapshot.

---

## 52. Nothing To Reset

Response:

```text
nothingToReset
```

Behavior:

```text
refetch snapshot
show concise native explanation
```

Do not decrement local credit count manually.

---

## 53. No Credit

Response:

```text
noCredit
```

Behavior:

```text
refetch snapshot
update UI
show concise explanation
```

---

## 54. Timeout

If transport times out during the same logical redemption:

```text
retry only with same idempotency key
```

Never generate a new key just because of retry.

---

# PART M — SETTINGS

## 55. Open

From:

```text
Menu popup
Orb context menu
```

Single instance.

Opening Settings closes transient popovers/Quick View.

---

## 56. Window Close

Native red traffic-light:

```text
close Settings only
```

Monitor stays alive.

---

## 57. Language

Options:

```text
Follow System
简体中文
English
```

Apply live where practical.

A full process restart should not be required merely to switch app language unless a platform limitation makes it unavoidable.

---

## 58. Launch At Login

Toggle:

```text
ON -> register SMAppService
OFF -> unregister
```

If system operation fails:

```text
reconcile visual toggle to actual service state
show concise error
```

Do not leave the toggle visually ON when the system registration failed.

---

## 59. Show Floating Window

Toggle:

```text
ON -> show Orb
OFF -> hide Orb + close Quick View
```

Immediate.

---

## 60. Pause Monitoring

When ON:

```text
runtime state -> PAUSED presentation
stop applying incoming task events to user-facing state
retain last known quota as stale
```

The transport may remain connected if technically useful.

When OFF:

```text
reconcile live account / thread state
resume authoritative presentation
```

Do not simply continue from the pre-pause active state without resync.

---

## 61. Hide Account Info

Immediate.

Affected surfaces:

```text
Menu popup
Usage
Settings/account references if any
diagnostic user-facing summaries
```

Do not rewrite database history.

---

# PART N — ACCOUNT CHANGES

## 62. Account Updated

When Codex reports a different account identity:

```text
increment account epoch
discard old in-flight account responses
fetch new account
fetch new limits
fetch new usage
scope future local history to new account
```

UI should switch atomically when sufficient new account data exists.

---

## 63. Unsupported Multi-Account Switching

If prototype buttons cannot be implemented safely using official Codex account surfaces:

```text
do not fake the feature
```

Options:

```text
disable
hide
handoff to Codex account UI
```

must be chosen during P0 integration review.

Monitor must not store raw Codex credentials.

---

# PART O — SLEEP / WAKE

## 64. Mac Sleeps

Before/during sleep:

```text
no special user alert
connection may drop
```

Do not mark task failed solely because the machine slept.

---

## 65. Wake

On wake:

```text
revalidate connection
refresh account / limits
refresh Usage if stale
reconcile loaded threads
```

Presentation should recover automatically.

---

# PART P — DISPLAY CHANGES

## 66. External Display Removed

If Orb was on a removed screen:

```text
fallback to current main screen
restore using normalized coordinates
clamp entirely into visibleFrame
```

Never leave the Orb inaccessible off-screen.

---

## 67. Resolution / Scale Change

Recompute from:

```text
screen identifier
normalized X/Y
```

Preserve relative position when possible.

---

## 68. Dock / Menu Bar Position Change

Use current:

```text
NSScreen.visibleFrame
```

on placement/reposition.

Do not rely on a cached old visible frame.

---

# PART Q — APP QUIT / RELAUNCH

## 69. Quit Monitor

From:

```text
Menu popup
Orb context menu
```

Behavior:

```text
persist settings / Orb state
flush DB writes
close Monitor transport
terminate Codex Monitor
```

Do not terminate Codex Desktop.

---

## 70. Relaunch

Restore:

```text
Orb visibility
Orb size
Orb position
Always On Top
Lock Position
language
notification settings
privacy setting
pause setting
```

Runtime task state is reconstructed fresh from Codex.

Do not restore a stale `WORKING` state from the prior process.

---

# PART R — EDGE CASES

## 71. Quota Missing But Codex Connected

Behavior:

```text
runtime state still works
Orb state ring still shows runtime color
center percentage -> `--`
```

Do not gray the whole Orb merely because quota data is unavailable.

---

## 72. Token Missing

Quick View:

```text
omit or show unavailable token value gracefully
```

Do not manufacture `0 token` unless the authoritative value is actually zero.

---

## 73. Cost Missing

Usage:

```text
$--
```

Never estimate.

---

## 74. Long Task Title

Rules:

```text
one line
truncate
no wrapping in compact surfaces
```

Full title may be available in accessibility/help text if desired.

---

## 75. Long Email

Prefer:

```text
middle/end truncation
```

while preserving recognizability.

If privacy setting ON:

```text
masked identity wins
```

---

## 76. Rapid State Changes

Example:

```text
Thinking
→ Working
→ Waiting Approval
→ Working
→ Completed
```

Do not queue animations.

Always render the latest authoritative state.

---

## 77. Multiple Fast Turn Completions

Completion retention should not block a newly active higher-priority state.

Use timestamped/turn-scoped terminal retention.

---

## 78. Approval Arrives During Red Retention

If a different thread requests approval while one thread is in red retention:

```text
red remains globally higher priority
```

After red expires:

```text
global becomes waiting approval
```

---

## 79. User Opens Usage While Disconnected

Allowed.

Show:

```text
cached Usage
stale/last updated context as appropriate
```

Do not block the window.

---

## 80. Database Temporarily Unavailable

If database cannot be opened:

```text
Monitor may continue with live in-memory state if safe
historical Usage persistence unavailable
show recoverable diagnostic state
```

Do not quit Codex.

A migration failure must preserve the DB file.

---

## 81. Settings Slider During Hidden Orb

Allowed.

```text
slider changes stored orbSize
```

No need to auto-show Orb.

---

## 82. Quick View While Quota Updates

If quota changes while Quick View is open:

```text
update quota text live
```

Do not close/reopen the panel.

---

## 83. Menu Popup While State Changes

Update content live.

Do not dismiss merely because:

```text
WORKING -> WAITING_APPROVAL
```

---

# PART S — USER FLOW ACCEPTANCE TESTS

## 84. First Launch

Pass when:

1. Menu Bar appears immediately.
2. Orb restores/appears according to default.
3. No unnecessary notification permission prompt.
4. Codex connection happens automatically.
5. No modal error if Codex is absent.

---

## 85. Runtime

Pass when:

1. Idle maps correctly.
2. Thinking maps correctly.
3. Working maps correctly.
4. Approval maps to yellow.
5. Completion holds 5 seconds.
6. Red terminal holds 15 seconds.
7. New active work overrides retained terminal state where specified.
8. Multi-thread priority works.

---

## 86. Orb

Pass when:

1. No Hover information exists.
2. Single click toggles Quick View.
3. Right click opens native context menu.
4. Drag closes Quick View.
5. Resize syncs with Settings.
6. Lock works.
7. Always-on-top works.
8. Position survives display changes.

---

## 87. Usage / Reset

Pass when:

1. Usage is single-instance.
2. Closing Usage does not quit Monitor.
3. Cached content appears immediately.
4. Chart always has 30 calendar slots.
5. Cost is never estimated.
6. Reset always confirms.
7. Reset retries are idempotent.
8. Post-reset values come from refetch.

---

## 88. Settings

Pass when:

1. All binary controls are native switches.
2. Orb Slider resizes live.
3. Launch at Login reflects actual system status.
4. Pause requires resync when resumed.
5. Hide Account Info updates live.
6. Closing Settings does not quit Monitor.

---

## 89. Recovery

Pass when:

1. Codex restart reconnects automatically.
2. Mac wake resyncs automatically.
3. Removed display cannot strand the Orb off-screen.
4. Account change cannot be overwritten by stale requests.
5. Monitor relaunch reconstructs runtime state from Codex.

---

# PART T — FREEZE STATUS

## 90. Product Behaviors Ready To Freeze

The following are consistent with all prior approved decisions:

```text
no Hover
automatic Codex reconnect
no modal alert when Codex absent
single-click read-only Quick View
native right-click menu
Quick View follows global-priority thread
working/thinking green breathing
waiting approval yellow breathing
red terminal = 15 seconds
completed = 5 seconds
multi-thread priority
Orb settings apply immediately
Usage opens from cache
reset requires confirmation
Settings/Usage are single-instance windows
window close never quits Monitor
Monitor quit never quits Codex
sleep/wake auto-reconcile
display changes auto-clamp Orb
```

---

## 91. Items Still Dependent On P0 Technical Validation

These are not product uncertainties; they depend on actual Codex protocol capability:

```text
ability to attach reliably to the running Codex Desktop app-server
visibility of approval lifecycle to a secondary Monitor client
exact account/usage response schema
safe official multi-account switching capability
stable account identifier availability
```

If P0 shows a capability is unavailable, product behavior must degrade honestly rather than be simulated.

---

## 92. Next Document

Next recommended document:

```text
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN
```

It should define:

```text
exact probe sequence
required local Codex commands
expected JSON-RPC calls
sanitized outputs to capture
pass/fail gates
fallback paths
implementation milestones
test strategy
build order for Codex
```
