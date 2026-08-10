# Codex Monitor — 现在开始执行

> 这是你从“上传交接包”到“最终 Release Candidate”的实际执行入口。
> 规则：**一个 Phase 一个独立 Codex Task；每个 Task 开始前手动选模型；每个 Task 结束必须生成对应报告并停止。**

---

## 你现在立刻做的 5 件事

1. 把 `Codex-Monitor-Handoff-v1.2` 整个文件夹放进 Codex Monitor 项目/仓库。
2. 确认 `apple-design` Skill 可用。
3. 新建一个 Codex Task。
4. 选择 **GPT-5.6 Sol / High**。
5. 把 `01_PHASE_0A_SOL_P0_AUDIT.md` 里的“可复制话术”完整发给 Codex。

**不要让 Sol 继续到 Phase 0B。**

---

## 整体模型分工

```text
Sol   = 决策 / 审查 / GO-NO-GO / 难题 / 最终验收
Terra = 主体开发
Luna  = 机械性、低风险、可明确验收的重复工作
```

口诀：

```text
Sol 决策 → Terra 开发 → Luna 搬砖 → Sol 验收
```

---

## 整体执行顺序

```text
Phase 0A  Sol High   P0 前置审查
Phase 0B  Terra High 实际跑 P0
Phase 0C  Sol High   P0 GO / NO-GO

Phase 1   Terra High Headless Transport
Phase 1R  Sol High   Transport Review

Phase 2   Terra High State Engine
Phase 2R  Sol High   State Engine Review

Phase 3   Terra High Account / Quota / Usage / Reset
Phase 3R  Sol High   Safety/Data Review

Phase 4   Terra Med  SQLite / Repository
Phase 4L  Luna Med   Fixtures / DB Tests

Phase 5   Terra High AppKit Shell
Phase 5R  Sol High   Native Architecture Review

Phase 6   Terra Med  Functional SwiftUI UI
Phase 6L  Luna Med   Localization / repetitive UI tests

Phase 7   Terra High Liquid Glass / Design Fidelity
Phase 7R  Sol High   Apple Design Review

Phase 8   Terra Med  Login / Notifications / Accessibility
Phase 8L  Luna Med   Accessibility / regression helper work

Phase 9   Terra Med/High QA + Fixes
Phase 9L  Luna Med   Repetitive regression matrix

Phase 10  Sol High   Release Candidate Audit
Phase 11  Terra Med/High RC Fixes
Final     Sol High   Final Sign-off
```

---

## 每个 Phase 的固定动作

```text
A. 新建一个 Codex Task
B. 手动选择指定模型 + Reasoning
C. 让模型读 Master PRD + 当前 Phase 文件 + 上一阶段报告
D. 只做当前 Phase
E. 跑测试
F. 输出 PHASE_<N>_REPORT.md
G. 停止
H. 你手动切模型，新建下一 Task
```

**不要在原 Task 里回复“继续下一阶段”。**

---

## 文件索引

从这里按顺序打开：

- `01_PHASE_0A_SOL_P0_AUDIT.md`
- `02_PHASE_0B_TERRA_P0_EXECUTION.md`
- `03_PHASE_0C_SOL_P0_DECISION.md`
- `04_PHASE_1_TERRA_TRANSPORT.md`
- `05_PHASE_1R_SOL_TRANSPORT_REVIEW.md`
- `06_PHASE_2_TERRA_STATE_ENGINE.md`
- `07_PHASE_2R_SOL_STATE_REVIEW.md`
- `08_PHASE_3_TERRA_ACCOUNT_USAGE_RESET.md`
- `09_PHASE_3R_SOL_SAFETY_REVIEW.md`
- `10_PHASE_4_TERRA_SQLITE.md`
- `11_PHASE_4L_LUNA_TESTS.md`
- `12_PHASE_5_TERRA_APPKIT_SHELL.md`
- `13_PHASE_5R_SOL_NATIVE_REVIEW.md`
- `14_PHASE_6_TERRA_FUNCTIONAL_UI.md`
- `15_PHASE_6L_LUNA_UI_SUPPORT.md`
- `16_PHASE_7_TERRA_LIQUID_GLASS.md`
- `17_PHASE_7R_SOL_DESIGN_REVIEW.md`
- `18_PHASE_8_TERRA_SYSTEM_INTEGRATIONS.md`
- `19_PHASE_8L_LUNA_ACCESSIBILITY_TESTS.md`
- `20_PHASE_9_TERRA_QA_FIXES.md`
- `21_PHASE_9L_LUNA_REGRESSION.md`
- `22_PHASE_10_SOL_RC_AUDIT.md`
- `23_PHASE_11_TERRA_RC_FIXES.md`
- `24_FINAL_SOL_SIGNOFF.md`

辅助文件：

- `90_MODEL_SWITCH_RULES.md`
- `91_PHASE_REPORT_TEMPLATE.md`
- `92_BLOCKER_ESCALATION_RULES.md`
- `93_APPLE_DESIGN_SKILL_USAGE.md`
