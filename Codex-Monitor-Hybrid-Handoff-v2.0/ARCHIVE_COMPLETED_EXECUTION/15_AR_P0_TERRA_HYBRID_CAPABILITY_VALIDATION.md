# AR-P0 — Terra / High — Hybrid Capability Validation

> Purpose: validate the revised Hybrid v1 architecture before any production implementation.
> This phase is disposable probe / evidence work only. It is not H1 and it is not production coding.

## Model

```text
GPT-5.6 Terra
Reasoning: High
Speed: Standard
```

## Must read

```text
14_ARCHITECTURE_REVISION_HYBRID_V1.md
PHASE_AR1_REPORT.md
FINAL_P0_REVALIDATION_REPORT.md
PHASE_0E_REPORT.md
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
```

Also read any prior P0 evidence needed to avoid repeating already-proven facts.

## Goal

Validate the four Hybrid v1 capability groups separately:

```text
AR-P0-A  Account semantics
AR-P0-B  Monitor-owned runtime
AR-P0-C  Desktop read-only snapshot
AR-P0-D  Transport support / maturity boundary
```

Optional:

```text
AR-P0-E  Reset-credit mutation
```

Do NOT run AR-P0-E unless the user separately gives explicit permission to consume a real reset credit.

## Copy-ready prompt

```text
你现在负责 Codex Monitor 的 AR-P0：Hybrid Capability Validation。

请先完整读取：

14_ARCHITECTURE_REVISION_HYBRID_V1.md
PHASE_AR1_REPORT.md
FINAL_P0_REVALIDATION_REPORT.md
PHASE_0E_REPORT.md
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md

本阶段只允许做 disposable probes、协议验证、sanitized fixtures 和证据报告。

禁止：
- 开始 H1；
- 写生产 UI；
- 写生产 Transport/Domain/SQLite 模块；
- 把 Desktop snapshot 当 live observer；
- 使用 thread/resume/thread/start/thread/fork 去制造 Desktop 观察能力；
- private backend；
- credential extraction；
- screen/accessibility scraping；
- continuous JSONL tailing 作为主数据源；
- 猜 approval、quota、cost、Session Token；
- 消耗真实 reset credit，除非我单独明确授权。

请严格分开执行以下 Gate。

AR-P0-A — Account semantics
1. 验证 account/read、account/rateLimits/read、account/usage/read 的实际字段和语义。
2. 验证 quota window、usedPercent、resetsAt、windowDurationMins。
3. 验证 reset-credit count/details。
4. 验证 account identity 可用字段及 non-secret stable discriminator 是否存在。
5. 验证 Usage daily bucket 的 date/timezone/null/token/cost 语义。
6. 如能安全观察 account/rateLimits/updated，验证 sparse update；否则标记 NOT TESTED，并继续 full refetch 策略。
7. 每项 capability 标记 unsupported / unvalidated / snapshot / liveAuthoritative / mutationValidated。

AR-P0-B — Monitor-owned runtime
这是最关键 Gate。
1. 只使用 Monitor-owned runtime / Monitor-created Thread / Monitor-created Turn。
2. 启动或注册明确的 owned app-server runtime，并分配 sourceID/runtimeInstanceID。
3. 由测试 harness 创建新 Thread 与无害 Turn。
4. 验证 Thread/Turn/Item correlation。
5. 验证 authoritative lifecycle：turn started、reasoning/active、command/file/tool activity、item started/completed、turn completed。
6. 验证 success / interruption / failure terminal outcomes；真实失败优先安全可控，其他可用 fixtures/mocks。
7. 验证 current activity 只来自 Item lifecycle，且不暴露 hidden reasoning。
8. 验证 thread/tokenUsage/updated 的存在、correlation 和 cumulative/delta 语义。
9. 验证 approval request + authoritative resolution；Probe/监控面不得 approve/decline。
10. 验证至少两个 Monitor-owned Threads 不串线。
11. 验证 reconnect：重新 initialize、恢复策略、active/idle reconstruction。
12. 验证 owner UI/process 断开后的 runtime survival / reattachment 边界；若不能保证，记录 limitation。
13. 每个子能力单独评级，不得用一个 fullRealtime=true 掩盖缺口。
14. 如果核心 lifecycle FAIL，不得转回 Desktop observer workaround。

AR-P0-C — Desktop read-only snapshot
只使用：
- thread/loaded/list
- thread/list
- thread/read(includeTurns: true)
禁止 thread/resume/thread/start/thread/fork。
验证：
- 是否能发现 Desktop Thread；
- title/preview/timestamps/raw status；
- history read；
- before/after refresh snapshot 变化；
- privacy-safe correlation digest；
- 哪些字段可诚实显示。
所有输出明确标记 snapshot only / not live。
AR-P0-C 失败不能自动否定 Account Layer 或 AR-P0-B。

AR-P0-D — Transport support / maturity
记录：
- standalone Codex CLI version；
- app-server transport 实际使用方式；
- WebSocket / Unix socket capability；
- 当前官方文档对 app-server/WebSocket production maturity 的声明；
- experimental / unsupported-for-production 风险；
- Internal/Developer build 是否可接受；
- Public v1 是否需要 release blocker / warning。
不得自行把 maturity 风险解释掉。

AR-P0-E — Reset mutation
默认 NOT RUN。
只有我明确说“我授权消耗 1 次真实 reset credit 用于 AR-P0-E”才允许真实测试。
否则仅 schema + mocks/fixtures，production action 继续 disabled。

输出：
AR_P0_REPORT_DRAFT.md
PHASE_AR_P0_REPORT.md
AR_P0_CAPABILITY_MATRIX.json
AR_P0_EVIDENCE_<timestamp>/

分别给：
AR-P0-A: PASS / PARTIAL / FAIL / NOT TESTED
AR-P0-B: PASS / PARTIAL / FAIL / NOT TESTED
AR-P0-C: PASS / PARTIAL / FAIL / NOT TESTED
AR-P0-D: PASS / PARTIAL / FAIL / NOT TESTED
AR-P0-E: NOT RUN / PASS / FAIL

最重要：AR-P0-B Monitor-owned runtime 必须独立得出结论。
Desktop snapshot 成功不能证明 realtime；Desktop snapshot 失败也不能否定 owned runtime。

完成后停止，不得进入 H1。
最后写：
下一阶段建议：GPT-5.6 Sol / High — AR-P0 Decision Review
```

## Exit gate

Evidence only. Do not start H1.
