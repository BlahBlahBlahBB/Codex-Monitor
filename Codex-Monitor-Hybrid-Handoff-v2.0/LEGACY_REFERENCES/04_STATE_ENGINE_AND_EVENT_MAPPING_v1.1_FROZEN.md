# Codex Monitor — State Engine & Event Mapping v1.0

> Status: **FROZEN — Product Approved**  
> Platform: macOS only  
> Implementation target: SwiftUI + AppKit + Swift Concurrency  
> Product rule: Monitor is read-first. It does not approve/decline Codex task permissions in v1.

---

## 1. Purpose

This document defines the core runtime logic of Codex Monitor:

1. How Codex events are converted into internal states.
2. How multiple Threads/Turns are aggregated into one global state.
3. How each state is projected onto:
   - Menu Bar 3-dot indicator
   - Floating Orb
   - Single-click Quick View
   - macOS notifications
4. How reconnects, event ordering, completed turns, failures and approval waits are handled.
5. Which parts are confirmed by the Codex app-server protocol and which still require P0 validation on the user's Mac.

Hover interaction has been removed from the product.

---

## 2. Runtime Data Source Priority

Use the following priority order:

1. **Codex app-server realtime events**
2. **Codex app-server query APIs**
3. **Codex persisted thread/account data**
4. **Local fallback / diagnostic data only when necessary**

Do not make JSONL log scraping the primary source of truth.

Connection candidates:

- app-server stdio
- local Unix socket control plane
- fallback process launched by Codex Monitor only if direct attachment to the existing Codex runtime is not possible

P0 must validate the exact integration path with the installed Codex Desktop version before production implementation begins.

---

## 3. Internal State Model

Each monitored thread owns its own state.

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

### DISCONNECTED

Meaning:
- Codex runtime/app-server cannot be reached.

UI:
- Menu Bar indicator: gray/off state.
- Floating Orb: gray ring, center `--`.
- Quick View: `Codex 未连接`.
- No Hover behavior exists.

### PAUSED

Meaning:
- User manually paused monitoring.

UI:
- Gray state.
- Floating Orb may retain last known quota percentage.
- Quick View shows `监控已暂停` and last update time.
- No task events are applied until monitoring resumes.

### IDLE

Meaning:
- Connection is healthy.
- No active Turn requires work or attention.

UI:
- Menu Bar: all 3 dots green, constant.
- Floating Orb: green ring, constant.
- Quick View: `空闲`.

### THINKING

Meaning:
- A Turn is active and the current dominant activity is model reasoning / generation rather than external execution.

UI:
- Menu Bar: first dot green, brightness breathing.
- Floating Orb: green ring, brightness breathing.
- Quick View: `思考中` / `正在思考`.

Animation rule:
- Approx. 0.8 s breathing cadence.
- Brightness only.
- No geometric scaling.
- No outer glow.
- Percentage text never scales or moves.

### WORKING

Meaning:
- A Turn is actively performing work such as command execution, file modification, tool invocation, web search, image generation, compaction, collaboration work, etc.

UI:
- Menu Bar: first dot green, brightness breathing.
- Floating Orb: green ring, brightness breathing.
- Quick View uses one concise current-activity line.

### WAITING_APPROVAL

Meaning:
- Codex has requested user authorization/approval and cannot proceed until the user responds in Codex.

UI:
- Menu Bar: second dot yellow, brightness breathing.
- Floating Orb: yellow ring, brightness breathing.
- Quick View: `等待授权`.
- Monitor does not provide approve/decline buttons.
- Optional system notification only when the user has enabled `等待授权通知`.

### COMPLETED

Meaning:
- A Turn completed successfully.

Retention:
- Show completion state for 5 seconds.
- Then transition to IDLE, unless another thread has a higher-priority active state.

UI:
- Menu Bar: all 3 dots green, constant.
- Floating Orb: green constant.
- Quick View: `任务完成` with final duration/token information.

### INTERRUPTED

Meaning:
- Turn ended with `interrupted`.

UI:
- Menu Bar: third dot red, constant.
- Floating Orb: red ring, constant.
- Quick View: `任务已中断`.

**Open product decision:** duration of the red terminal indication must be finalized (see §15).

### FAILED

Meaning:
- Turn ended with `failed`, or an authoritative execution failure is promoted to a Turn failure.

UI:
- Menu Bar: third dot red, constant.
- Floating Orb: red ring, constant.
- Quick View: concise failure summary only; never show a long stack trace here.

**Open product decision:** duration of the red terminal indication must be finalized (see §15).

### SYSTEM_ERROR

Meaning:
- Loaded thread reports a system error, or Monitor detects a runtime failure that makes thread state unreliable.

UI:
- Red state.
- Quick View distinguishes `Codex 异常` from a user task failure.

---

## 4. Official Codex Event → Internal State Mapping

| Codex signal | Internal state | Current activity |
|---|---|---|
| connection unavailable | DISCONNECTED | `Codex 未连接` |
| `thread.status = idle` and no terminal retention | IDLE | `空闲` |
| `thread.status = systemError` | SYSTEM_ERROR | `Codex 异常` |
| `thread.status = active` | THINKING fallback | `处理中` |
| `turn/started` | THINKING | `正在思考` |
| `item/started` type `reasoning` | THINKING | `正在思考` |
| `item/started` type `commandExecution` | WORKING | `正在运行命令` or short safe command |
| `item/started` type `fileChange` | WORKING | `正在修改 <file>` / `正在修改 N 个文件` |
| `item/started` type `mcpToolCall` | WORKING | `正在调用工具` |
| `item/started` type `webSearch` | WORKING | `正在搜索` |
| `item/started` type `imageGeneration` | WORKING | `正在生成图片` |
| `item/started` type `imageView` | WORKING | `正在查看图片` |
| `item/started` type `collabToolCall` | WORKING | `正在执行协作任务` |
| `item/started` type `contextCompaction` | WORKING | `正在整理上下文` |
| approval request for command/file/tool/network action | WAITING_APPROVAL | `等待你在 Codex 中确认` |
| `serverRequest/resolved` | re-derive active state | return to current Turn activity |
| `turn/completed` status `completed` | COMPLETED | `任务已完成` |
| `turn/completed` status `interrupted` | INTERRUPTED | `任务已中断` |
| `turn/completed` status `failed` | FAILED | concise failure summary |
| runtime `error` mid-turn | pending failure signal | do not terminalize until authoritative turn result unless connection becomes unusable |
| `thread/tokenUsage/updated` | no state change | update Session token display |

### Important rule

`thread/status = active` is only a coarse fallback.  
The fine-grained state is derived from Turn + Item + approval lifecycle events.

---

## 5. Current Activity Derivation

Quick View must stay concise.

Priority inside an active Turn:

```text
WAITING_APPROVAL
    >
active file/command/tool work
    >
reasoning
    >
generic active
```

When multiple active Items exist, choose a user-comprehensible summary rather than exposing raw internal events.

Examples:

```text
正在修改 App.swift
正在修改 3 个文件
正在运行 npm run build
正在调用工具
正在搜索
正在生成图片
正在整理上下文
正在思考
```

Rules:

- One line only.
- Truncate long commands.
- Do not display raw reasoning content.
- Do not expose sensitive command payloads beyond the redacted/display form provided by Codex.
- Quick View is status, not a log viewer.

---

## 6. Per-Thread Runtime Record

Recommended in-memory model:

```swift
struct ThreadRuntimeState {
    let threadID: String

    var threadTitle: String?
    var model: String?

    var state: MonitorState
    var previousActiveState: MonitorState?

    var currentTurnID: String?
    var currentActivity: CurrentActivity?

    var activeItemIDs: Set<String>
    var pendingApprovalRequestIDs: Set<String>

    var turnStartedAt: Date?
    var turnCompletedAt: Date?

    var sessionTokenUsage: TokenUsage?
    var lastErrorSummary: String?

    var lastEventAt: Date
}
```

Task title rule:

1. Use Thread/Session title when available.
2. Otherwise use the first user message / thread preview.
3. One visible line only; truncate overflow.

---

## 7. Global Aggregation Across Multiple Threads

Menu Bar and Floating Orb represent the whole Codex runtime, not one selected thread.

Global priority:

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

Examples:

```text
Thread A = WORKING
Thread B = WAITING_APPROVAL
=> Global = WAITING_APPROVAL
```

```text
Thread A = WORKING
Thread B = FAILED
=> Global = FAILED
```

```text
Thread A = COMPLETED
Thread B = WORKING
=> Global = WORKING
```

The 5-second COMPLETED state is only globally visible when no higher-priority active/alert state exists.

---

## 8. Menu Bar Projection

Frozen visual option:

```text
B · Balanced
48 × 22
dot size: 7 px
white capsule outline retained
```

State projection:

| Global state | Dot 1 | Dot 2 | Dot 3 |
|---|---|---|---|
| IDLE | green constant | green constant | green constant |
| THINKING | green breathing | off | off |
| WORKING | green breathing | off | off |
| WAITING_APPROVAL | off | yellow breathing | off |
| COMPLETED | green constant | green constant | green constant |
| INTERRUPTED | off | off | red constant |
| FAILED | off | off | red constant |
| SYSTEM_ERROR | off | off | red constant |
| DISCONNECTED | gray/off | gray/off | gray/off |
| PAUSED | gray/off | gray/off | gray/off |

---

## 9. Floating Orb Projection

Frozen behavior:

```text
default size: 90 px
freely resizable
all content scales proportionally
center value: remaining percentage of the most constrained quota window
ring geometry: ~90% of orb diameter
ring width: ~7 px at 90 px base size
```

The colored ring represents **Codex runtime state**, not quota severity.

Color:

```text
IDLE / THINKING / WORKING / COMPLETED = Apple System Green
WAITING_APPROVAL = Apple System Yellow
INTERRUPTED / FAILED / SYSTEM_ERROR = Apple System Red
DISCONNECTED / PAUSED = System Gray
```

Breathing:

```text
cadence ~0.8 s
brightness-only
no scale
no geometry change
no glow
center percentage remains completely static
```

---

## 10. Single-Click Quick View Projection

There is no Hover interaction.

Single click opens a read-only Quick View.

No:
- buttons
- switches
- menus
- approval controls

Working example:

```text
Codex
● 工作中                         18:56

Codex Monitor App
正在修改 3 个文件

GPT-5.6 Sol · 运行 12:43
本会话 644.38万 Token · 剩余额度 42%
```

Completed example:

```text
✓ 任务完成
Codex Monitor App
用时 04:32 · 128.6万 Token · 剩余额度 61%
```

Disconnected example:

```text
○ Codex 未连接
```

Opening Codex is handled from Menu Bar / context menu, not Quick View.

---

## 11. Token / Quota / Credit Separation

Do not derive remaining quota percentage by dividing token count by an assumed fixed token allowance.

Store and display these as separate concepts:

```text
Token usage -> thread/account usage events
Quota remaining -> official rate-limit data
Credits/reset credits -> official account/rate-limit data
```

The Floating Orb center displays the remaining percentage of the most constrained current quota window.

Example:

```text
5-hour remaining = 78%
weekly remaining = 42%
Floating Orb = 42%
```

---

## 12. Account / Usage APIs

Initial connection snapshot should request:

```text
account/read
account/rateLimits/read
account/usage/read
thread/loaded/list
thread/list (as needed for titles/history)
```

Realtime updates:

```text
account/rateLimits/updated
thread/status/changed
turn/*
item/*
thread/tokenUsage/updated
approval lifecycle
account/updated
```

Rate-limit updates may be sparse. Merge them into the last full snapshot rather than treating missing fields as zero/null.

Reset-credit data should be treated as snapshot-based and refreshed after a reset is consumed.

---

## 13. Reconnect and Event Ordering

### On connection loss

```text
connection lost
→ DISCONNECTED
→ retain last known account/quota data as stale
→ do not mutate thread state from stale local assumptions
```

### Reconnect

Use exponential backoff with jitter.

Suggested cadence:

```text
0.5s
1s
2s
4s
8s
then cap at 15s
```

On reconnect:

```text
initialize
→ account snapshot
→ rate-limit snapshot
→ usage snapshot
→ thread/loaded/list
→ reconstruct loaded thread states
→ resume realtime event processing
```

### Event ordering

Use server-provided threadId / turnId / itemId as the identity model.

Rules:

- Ignore stale Item events from an older Turn after a newer Turn has become authoritative.
- `item/completed` is authoritative for that Item.
- `turn/completed` is authoritative for Turn terminal state.
- A transient `error` event should not by itself replace a later authoritative `turn/completed`.
- Approval state is cleared when the matching request resolves or the Turn terminalizes.

---

## 14. P0 Technical Validation — Mandatory Before UI Implementation

Two integration details must be tested on the actual installed Codex Desktop build.

### P0-A: attach to the existing app-server

Official app-server supports a local Unix socket control-plane transport, but Codex Monitor must verify that the running Codex Desktop instance exposes/uses a listener the Monitor can attach to in the intended production configuration.

Pass criteria:

```text
Monitor launches while Codex Desktop is already running
→ connects without taking ownership of Codex
→ reads account/rate-limit/thread state
→ receives realtime thread/turn/item updates
```

### P0-B: approval visibility from a secondary Monitor client

The app-server protocol defines server-initiated approval requests, but v1 must verify that a separate monitoring/control-plane connection can reliably observe the approval lifecycle of Turns initiated by Codex Desktop.

Pass criteria:

```text
Codex Desktop starts a task
→ task asks for command/file approval
→ Codex Monitor enters WAITING_APPROVAL
→ user approves/declines in Codex Desktop
→ Monitor receives resolution
→ Monitor returns to derived active/terminal state
```

If this does not work from a secondary client, WAITING_APPROVAL must not be guessed. A protocol-supported fallback must be identified before shipping the yellow state as reliable.

---

## 15. FAILED / INTERRUPTED Red-State Persistence — FROZEN

Product decision:

```text
FAILED / INTERRUPTED / SYSTEM_ERROR terminal red indication = 15 seconds
```

Behavior:

1. When an authoritative terminal failure/interruption is received, the affected thread enters the corresponding red terminal state.
2. The red Menu Bar indicator and red Floating Orb remain constant for **15 seconds**.
3. After 15 seconds:
   - if another higher-priority alert/active thread exists, recompute the global state from all threads;
   - otherwise return the global presentation to `IDLE`.
4. The failure/interruption record is **not deleted** after 15 seconds. It remains available in Quick View/history/diagnostic records.
5. If a new Turn starts on the same thread during the 15-second retention window, the new authoritative active state replaces the old red terminal presentation immediately.
6. No red-state breathing animation is used. Red is always constant.

This decision is frozen for v1.

---

## 16. Acceptance Tests

The State Engine is considered complete only when these scenarios pass:

1. Codex not running → gray disconnected state.
2. Codex starts → automatic reconnect without user refresh.
3. Idle → all three Menu Bar dots green.
4. Reasoning → first green dot + green orb brightness breathing.
5. Command/file/tool activity → WORKING with concise activity text.
6. Approval request → yellow state; Monitor never offers approve/decline.
7. Approval resolved → state returns to active work automatically.
8. Successful completion → COMPLETED for 5 seconds → IDLE.
9. Interrupted → red constant for 15 seconds, then global state is recomputed.
10. Failed → red constant for 15 seconds, then global state is recomputed.
11. Two concurrent threads → global priority aggregation works.
12. Rate-limit change → quota UI updates without polling every 0.5s.
13. Token usage update → Session token count updates independently of quota percentage.
14. Monitor disconnect/reconnect → no duplicate state transitions and no lost current state after resync.
15. Monitor crash/exit → Codex continues functioning normally.


---

## 17. Frozen Product Constants

```text
Completed state retention: 5 seconds
Failed/interrupted/system-error red retention: 15 seconds
Working/thinking breathing cadence: ~0.8 seconds
Breathing changes brightness only
No Hover interaction
Quick View is read-only
Approval is completed in Codex, not in Codex Monitor
Global priority:
  ERROR/FAILED/INTERRUPTED
  > WAITING_APPROVAL
  > WORKING/THINKING
  > COMPLETED
  > IDLE
  > DISCONNECTED
```

State Engine v1 is now **Frozen**. Any future change to these constants should be treated as a product-spec revision rather than an implementation detail.
