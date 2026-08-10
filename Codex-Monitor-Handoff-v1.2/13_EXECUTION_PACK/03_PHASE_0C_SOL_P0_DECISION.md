# Phase 0C — Sol / High — P0 最终 GO / NO-GO

## 模型
- GPT-5.6 Sol
- Reasoning: High

## 目标
只审查 Phase 0B 的证据，不写主体功能。

## 可复制话术

```text
你现在只负责 Codex Monitor Phase 0C：P0 最终审查。

请读取：
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md
PHASE_0A_REPORT.md
PHASE_0B_REPORT.md
P0_REPORT_DRAFT.md
以及 Phase 0B 生成的脱敏证据和 fixtures。

你的任务：
1. 审核 P0 证据是否足够；
2. 对每个核心能力给出 PASS / PARTIAL / FAIL；
3. 判断整个项目 GO / CONDITIONAL GO / NO-GO；
4. 明确 approval yellow state 是否能可靠实现；
5. 明确 Usage 哪些字段可以正式实现；
6. 明确 multi-account switching 是否支持；
7. 明确所有必须做的产品降级；
8. 生成最终 P0_REPORT.md；
9. 生成 PHASE_0C_REPORT.md。

禁止：
- 写正式 UI；
- 为了 GO 而降低证据标准；
- 修改 FROZEN 规则；
- 用猜测替代协议证据。

如果 GO / CONDITIONAL GO：
最后写：
下一阶段建议：GPT-5.6 Terra / High — Phase 1 Headless Transport

如果 NO-GO：
清楚列出阻断点和可接受的下一步，不得自行绕过。

完成后停止。
```

## Gate
只有 `GO` 或可接受的 `CONDITIONAL GO` 才进入 Phase 1。
