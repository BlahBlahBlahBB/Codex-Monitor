# Codex Monitor — Phase Model Switching & Execution Playbook v1.0

> Purpose: manually control GPT-5.6 Sol / Terra / Luna by development phase to protect quota while keeping high-risk decisions on the strongest model.
>
> Core rule: **one Phase = one bounded task/conversation whenever practical.**
>
> Do not ask one long-running Sol conversation to implement the whole project.

---

# 1. Model Roles

## GPT-5.6 Sol

Use for:

- project comprehension
- architecture / protocol judgement
- GO / NO-GO
- high-risk state/concurrency decisions
- review after important phases
- difficult bug escalation
- final Apple design review
- release candidate audit

Default effort:

```text
High
```

Do not default to xhigh/max unless a concrete hard problem remains unresolved.

---

## GPT-5.6 Terra

Default implementation model.

Use for:

- P0 probe implementation
- JSON-RPC / Unix socket transport
- Swift Concurrency
- state engine implementation
- account / quota / usage adapters
- SQLite / repositories
- AppKit window controllers
- SwiftUI functional UI
- Liquid Glass implementation
- normal debugging

Default effort:

```text
Medium
```

Escalate to:

```text
High
```

for transport, concurrency, AppKit lifecycle, protocol adapter, reset-credit logic, or repeatedly failing bugs.

---

## GPT-5.6 Luna

Use only for bounded, mechanical work after the design is already decided.

Use for:

- fixtures
- mock data
- repetitive unit tests
- localization files
- documentation cleanup
- simple model/struct generation
- mechanical renaming
- small formatting cleanup
- low-risk refactors with explicit tests

Default effort:

```text
Medium
```

Do not use Luna for architecture, P0 judgement, state semantics, concurrency ownership, database migration design, reset-credit safety, or final visual judgement.

---

# 2. How To Manually Switch

At each Phase boundary:

```text
1. Stop the current task.
2. Require PHASE_<N>_REPORT.md.
3. Ensure tests for that Phase pass.
4. Commit/save the current repository state if appropriate.
5. Start a NEW Codex task/conversation in the SAME project/repository.
6. In Codex's model selector, manually choose the model for the next Phase.
7. Choose the requested reasoning level.
8. Paste the Phase handoff prompt from this playbook.
9. Make the new model read:
   - README_START_HERE.md
   - Master PRD
   - relevant specialist spec
   - previous PHASE report
10. Tell it to work ONLY on the current Phase.
```

Why a new task/conversation is preferred:

- keeps context smaller;
- avoids paying repeatedly for a giant old conversation;
- prevents the next model from inheriting irrelevant debugging history;
- makes Phase boundaries auditable;
- makes it obvious which model performed which work.

Do not delete the previous conversation. Keep it as an audit trail.

---

# 3. Model Escalation Rule

Start a normal implementation task with:

```text
Terra Medium
```

Move to:

```text
Terra High
```

when any of these happen:

- protocol decoding is ambiguous;
- concurrency/state ordering is involved;
- AppKit window lifecycle is behaving unexpectedly;
- two sensible attempts have failed;
- changes touch reset-credit consumption;
- database migration behavior changes.

Escalate to:

```text
Sol High
```

when:

- Terra High fails twice on the same root problem;
- the solution would change a FROZEN rule;
- the P0 result is ambiguous;
- a protocol limitation requires product degradation;
- there is a security/privacy concern;
- a cross-module architecture change is proposed.

Use:

```text
Luna Medium
```

only after Terra/Sol has already defined an exact, bounded implementation task.

---

# 4. Phase Schedule

| Phase | Task | Primary model | Effort | Reviewer |
|---|---|---|---|---|
| 0A | Read all specs + audit P0 plan | Sol | High | — |
| 0B | Implement/run P0 probe | Terra | High | Sol |
| 0C | P0 GO/NO-GO review | Sol | High | — |
| 1 | Headless transport | Terra | High | Sol |
| 2 | Domain + frozen state engine | Terra | High | Sol |
| 3 | Account / quota / usage / reset adapter | Terra | High | Sol for safety review |
| 4 | SQLite + repositories | Terra | Medium | Terra High / Sol only if architecture changed |
| 4L | Fixtures + repetitive persistence tests | Luna | Medium | Terra |
| 5 | macOS utility shell / AppKit windows | Terra | High | Sol |
| 6 | Functional SwiftUI UI | Terra | Medium | Terra High |
| 6L | Localization / repetitive UI tests | Luna | Medium | Terra |
| 7 | Native Liquid Glass + design fidelity | Terra | High | Sol |
| 8 | Login item / notifications / accessibility | Terra | Medium | Terra High |
| 8L | Accessibility fixtures/docs/tests | Luna | Medium | Terra |
| 9 | Full QA + bug fixing | Terra | Medium/High | Sol |
| 9L | Repetitive regression matrix | Luna | Medium | Terra |
| 10 | Release candidate architecture/design audit | Sol | High | — |
| 11 | RC fixes / packaging | Terra | Medium/High | Sol final sign-off |

---

# 5. Phase 0A — Start NOW

## Model

```text
GPT-5.6 Sol
Reasoning: High
```

## Goal

Sol only reads, audits, and prepares P0 execution.

It must not build production UI.

## Prompt

```text
你现在负责 Codex Monitor 的 Phase 0A：P0 前置审查。

项目交接包已经在当前项目中。

请先完整阅读：

README_START_HERE.md
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md

然后按 Master PRD 的引用关系阅读 04–09 全部规格，并查看：
00_APPROVED_VISUAL_REFERENCE_v1.9.html

同时确认 apple-design Skill 是否已经安装并可读取。
如未安装，请按项目要求安装/配置；如当前环境无法安装，请明确报告。

本 Phase 只允许：
1. 检查规格冲突；
2. 检查 P0 计划是否缺失关键验证；
3. 检查当前机器/项目是否具备执行 P0 的条件；
4. 给出 Phase 0B 的精确执行清单；
5. 创建 PHASE_0A_REPORT.md。

禁止：
- 编写正式 UI；
- 修改 FROZEN 产品决策；
- 跳过 P0；
- 开始 Phase 1；
- 为了继续而猜测 Codex 协议。

完成后停止，并在最后明确写：
“下一阶段建议：GPT-5.6 Terra / High”
不要继续执行 Phase 0B。
```

## Exit gate

Must produce:

```text
PHASE_0A_REPORT.md
```

You review it briefly.

If it reports no blocking spec conflict, switch manually to Terra High.

---

# 6. Phase 0B — Execute P0

## Model

```text
GPT-5.6 Terra
Reasoning: High
```

## Prompt

```text
你现在负责 Codex Monitor 的 Phase 0B：实际执行 P0 Protocol Validation。

请读取：

README_START_HERE.md
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md
PHASE_0A_REPORT.md

严格按照 10_P0 的顺序执行。

本阶段可以：
- 创建 Tools/P0Probe；
- 检查本机 Codex 版本；
- 生成 stable JSON/TS schema；
- 验证本地 app-server transport；
- 执行安全的只读协议探针；
- 生成经过脱敏的 fixtures；
- 运行非破坏性测试。

本阶段禁止：
- 正式 UI 开发；
- 消耗真实 reset credit，除非我另行明确授权；
- 保存 OAuth/API key/refresh token；
- 使用 private backend；
- 猜字段；
- 猜 waiting approval 状态；
- 修改 FROZEN 产品规则。

请输出：
P0_REPORT_DRAFT.md
PHASE_0B_REPORT.md

对每一个 P0 Gate 标记：
PASS / PARTIAL / FAIL / NOT TESTED

如果遇到 hard NO-GO 阻断，立即停止，不要自行绕过。

完成后停止，并明确写：
“下一阶段建议：GPT-5.6 Sol / High，用于 P0 GO/NO-GO 审查”
```

## Exit gate

Must have:

```text
P0_REPORT_DRAFT.md
PHASE_0B_REPORT.md
sanitized evidence
```

Then switch to Sol High.

---

# 7. Phase 0C — Sol P0 Decision

## Model

```text
GPT-5.6 Sol
Reasoning: High
```

## Prompt

```text
你现在只负责 Codex Monitor Phase 0C：P0 最终审查。

请读取：
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md
PHASE_0A_REPORT.md
PHASE_0B_REPORT.md
P0_REPORT_DRAFT.md
以及 Phase 0B 生成的脱敏证据/fixtures。

你的任务：
1. 审核 P0 证据是否足够；
2. 对每个核心能力给出 PASS / PARTIAL / FAIL；
3. 判断整个项目是 GO / CONDITIONAL GO / NO-GO；
4. 明确 approval yellow state 是否可以可靠实现；
5. 明确 Usage 哪些字段可以正式实现；
6. 明确 multi-account switching 是否支持；
7. 明确所有需要产品降级的地方；
8. 生成最终 P0_REPORT.md；
9. 生成 PHASE_0C_REPORT.md。

不要写正式 UI。
不要擅自修改 FROZEN 规则。

如果 GO/CONDITIONAL GO，请在最后给出：
“下一阶段建议：GPT-5.6 Terra / High — Phase 1 Headless Transport”
然后停止。
```

---

# 8. Phase 1 — Headless Transport

## Model

```text
Terra High
```

## Scope

Only:

```text
Swift transport
Unix-socket/WebSocket or validated transport
JSON-RPC routing
initialize
request/response matching
notifications
server-request observation
reconnect
sanitization
```

No visual UI.

## Prompt skeleton

```text
你现在负责 Phase 1：Headless Transport。

读取 Master PRD、最终 P0_REPORT.md、10_P0 和 PHASE_0C_REPORT.md。

只实现 Phase 1。
不得进入 UI。

完成条件：
- transport tests pass
- reconnect tests pass
- fixture/replay tests pass
- 能打印 sanitized normalized transport events
- 创建 PHASE_1_REPORT.md

完成后停止。
下一阶段推荐模型：Sol High 做 Phase 1 Review。
```

Then create a short Sol High review task.

Sol must review only—not rewrite the whole module unless a real architecture issue exists.

---

# 9. Phase 2 — Domain / State Engine

## Implementation

```text
Terra High
```

Implement frozen states and global priority.

Use recorded P0 fixtures.

## Review

```text
Sol High
```

Review:

- concurrency ordering;
- terminal timers;
- multi-thread aggregation;
- stale events;
- approval resolution;
- no FROZEN drift.

If review passes, continue.

---

# 10. Phase 3 — Account / Quota / Usage / Reset

## Model

```text
Terra High
```

Reason:

This phase contains:

- sparse rate-limit merges;
- account epochs;
- usage schema mapping;
- idempotency;
- scarce reset-credit consumption.

After implementation:

```text
Sol High
```

reviews only:

```text
reset safety
account isolation
authoritative-vs-estimated data
protocol capability degradation
```

Do not spend a real reset credit for automated validation.

---

# 11. Phase 4 — SQLite / Repositories

## Main model

```text
Terra Medium
```

Escalate to Terra High for:

- migration changes;
- account-scope bugs;
- concurrency/write ordering.

## Luna tasks

After architecture is in place, create separate Luna Medium tasks for:

```text
database fixtures
repetitive CRUD tests
30-day zero-fill tests
formatter test expansion
mock records
```

Example Luna prompt:

```text
这是一个严格限定的机械性任务。

读取 Master PRD、06_LOCAL_DATABASE...、PHASE_4_REPORT.md。

只补充以下测试：
[具体测试列表]

不得修改数据库架构、migration 设计、Repository API 或产品逻辑。
如果测试暴露架构问题，只报告，不自行重构。

运行测试后创建 PHASE_4L_REPORT.md 并停止。
```

---

# 12. Phase 5 — AppKit Utility Shell

## Model

```text
Terra High
```

Build only system shell:

```text
LSUIElement
NSStatusItem
NSPopover
Orb NSPanel
Quick View NSPanel
Usage NSWindow
Settings NSWindow
NSMenu
WindowCoordinator
```

No final visual polish yet.

Then:

```text
Sol High review
```

Review native window semantics and lifecycle.

---

# 13. Phase 6 — Functional UI

## Model

```text
Terra Medium
```

Before work:

```text
read apple-design Skill
read 08 Design System
read approved v1.9 visual reference
```

Goal:

all functionality visible and usable.

Do not spend Sol quota polishing every row.

Luna can handle:

```text
localization keys
simple labels
repetitive preview fixtures
basic UI unit tests
```

provided it cannot change structure.

---

# 14. Phase 7 — Liquid Glass / Design Fidelity

## Implementation

```text
Terra High
```

Requirements:

```text
native macOS 26 Liquid Glass
not CSS imitation
native switches
native Slider
native window traffic lights
no glass-card explosion
```

Then mandatory:

```text
Sol High
```

review with screenshots of:

```text
Menu Bar states
Orb 64/90/180
Quick View
Menu popup
Usage
Settings
Light/Dark
Reduce Motion
Reduce Transparency
```

Sol's job here is visual/system QA, not new product ideation.

---

# 15. Phase 8 — System Integrations

## Model

```text
Terra Medium
```

Implement:

```text
SMAppService
UNUserNotificationCenter
Open Codex
accessibility labels
settings reconciliation
sleep/wake
display restore
```

Use Luna for repetitive accessibility/test matrices only after implementation.

---

# 16. Phase 9 — QA

## First pass

```text
Luna Medium
```

only for executing clearly defined regression/test matrices and recording failures.

## Fixes

```text
Terra Medium
```

Escalate difficult bugs:

```text
Terra High
```

If two good Terra High fixes fail or the fix changes architecture:

```text
Sol High
```

---

# 17. Phase 10 — Release Candidate Audit

## Model

```text
Sol High
```

Read:

```text
Master PRD
P0_REPORT
all PHASE reports
test results
visual QA screenshots
git diff/release branch
```

Audit:

```text
spec drift
security/privacy
protocol truth
state correctness
database safety
native Apple behavior
Liquid Glass restraint
accessibility
known limitations
```

Output:

```text
RC_AUDIT.md
```

No broad rewrite.

---

# 18. Phase 11 — RC Fixes

Use:

```text
Terra Medium
```

for straightforward fixes.

Use:

```text
Terra High
```

for architectural or concurrency fixes.

After all fixes:

```text
Sol High
```

does a final targeted sign-off against `RC_AUDIT.md`.

---

# 19. Quota-Saving Rules

## Rule A — New conversation per Phase

This is the most important practical rule.

Avoid one giant Sol conversation for the whole project.

## Rule B — Do not repeatedly paste the full PRD

The repo already contains the documents.

Prompt the model to read exact files.

## Rule C — Ask for concise Phase reports

Reports should contain facts, not retell every spec.

## Rule D — Sol reviews diffs/reports, not the entire repository from scratch every time

Tell Sol:

```text
focus on the changed files + relevant spec + PHASE report
```

unless a cross-system audit is required.

## Rule E — Keep xhigh/max off by default

Use High for difficult work.

Only raise effort if tests show a quality problem that High cannot solve.

## Rule F — Luna only gets bounded tasks

Bad Luna prompt:

```text
finish the app
```

Good Luna prompt:

```text
add these 12 fixture-based tests without changing production APIs
```

---

# 20. What To Do If A Model Is Not Available

Do not substitute silently.

If Sol is unavailable due allowance/capacity:

```text
pause a Sol-gated review
```

You may continue independent low-risk work that does not depend on the unresolved review.

If Terra is unavailable:

```text
Sol may implement only when the task is important enough to justify the quota
```

or wait.

If Luna is unavailable:

```text
Terra Medium can do Luna work
```

Never let model availability become permission to skip a safety/review gate.

---

# 21. “Can Sol Spawn Terra/Luna For Me?”

Do not rely on this for quota planning.

The safe operating assumption is:

```text
you manually select the model for each new Phase task
```

If the current Codex UI/runtime explicitly shows and guarantees per-worker model control, you may use it later, but it is not required by this plan.

The Phase reports must state the actual model/effort used.

---

# 22. Phase Report Header

Every report should start with:

```text
Phase:
Model used:
Reasoning level:
Start commit:
End commit:
Specs read:
Tests run:
Result:
```

This lets the user audit model usage and development progress.

---

# 23. Immediate Execution Checklist

Do this now:

```text
[1] Open Codex.
[2] Select the Codex Monitor project/repository.
[3] Upload/copy the entire Handoff bundle into the project if it is not already there.
[4] Install/confirm apple-design Skill.
[5] Start a NEW task.
[6] Select GPT-5.6 Sol.
[7] Select High reasoning.
[8] Paste the Phase 0A prompt from §5.
[9] Wait for PHASE_0A_REPORT.md.
[10] Do not let Sol continue to Phase 0B.
[11] Start a NEW task in the same project.
[12] Select GPT-5.6 Terra.
[13] Select High.
[14] Paste the Phase 0B prompt.
[15] Wait for P0_REPORT_DRAFT.md + PHASE_0B_REPORT.md.
[16] Start a NEW Sol High task for Phase 0C.
[17] Only after Sol writes final P0_REPORT.md and says GO/CONDITIONAL GO should Phase 1 begin.
```

---

# 24. Short Version

The project loop is:

```text
SOL
decide / audit
↓
TERRA
implement
↓
LUNA
mechanical tests/cleanup when useful
↓
SOL
review important gate
↓
TERRA
continue implementation
```

Not:

```text
SOL does everything
```

and not:

```text
LUNA builds the architecture
```

---

# 25. First Three Tasks Summary

### Task 1 — Right now

```text
Sol High
Phase 0A
Read + audit only
```

### Task 2

```text
Terra High
Phase 0B
Run P0
```

### Task 3

```text
Sol High
Phase 0C
P0 GO / NO-GO
```

Only then:

```text
Terra High
Phase 1
Headless transport
```
