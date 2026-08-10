# Phase 0B — Terra / High — 实际执行 P0

## 模型
- GPT-5.6 Terra
- Reasoning: High

## 目标
建立 P0 Probe，真实验证当前 Mac 上 Codex 的协议能力。

## 必须读取
- Master PRD
- `10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md`
- `PHASE_0A_REPORT.md`

## 可复制话术

```text
你现在负责 Codex Monitor 的 Phase 0B：实际执行 P0 Protocol Validation。

请读取：
README_START_HERE.md
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md
PHASE_0A_REPORT.md

严格按照 10_P0 的顺序执行。

本阶段允许：
- 创建 Tools/P0Probe；
- 检查本机 Codex 版本；
- 生成 stable JSON/TS schema；
- 验证本地 app-server transport；
- 执行安全、只读、非破坏性的协议探针；
- 生成脱敏 fixtures；
- 运行必要测试。

本阶段禁止：
- 正式 UI 开发；
- 进入 Phase 1；
- 消耗真实 reset credit，除非我另行明确授权；
- 保存 OAuth/API key/refresh token；
- 使用 private backend；
- 猜字段；
- 猜 waiting approval 状态；
- 修改 FROZEN 产品规则；
- 为了继续而绕过 hard NO-GO。

请生成：
P0_REPORT_DRAFT.md
PHASE_0B_REPORT.md

对每一个 P0 Gate 标记：
PASS / PARTIAL / FAIL / NOT TESTED

如果遇到 hard NO-GO，立即停止并清楚说明原因。

完成后停止。
最后明确写：
下一阶段建议：GPT-5.6 Sol / High — Phase 0C P0 Review
```

## 必须产出
- `P0_REPORT_DRAFT.md`
- `PHASE_0B_REPORT.md`
- sanitized fixtures / evidence

## 通过后
新建 Task → **Sol / High** → `03_PHASE_0C_SOL_P0_DECISION.md`
