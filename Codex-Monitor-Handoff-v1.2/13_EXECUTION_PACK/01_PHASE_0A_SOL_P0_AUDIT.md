# Phase 0A — Sol / High — P0 前置审查

## 你现在就执行这个任务

### 模型
- GPT-5.6 Sol
- Reasoning: High

### 本阶段目标
只做“理解 + 审查 + P0 准备”，**不写正式 UI，不开始主体开发**。

### 开始前必须读取
- `README_START_HERE.md`
- `11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md`
- `12_PHASE_MODEL_SWITCHING_AND_EXECUTION_PLAYBOOK_v1.0.md`
- `10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md`
- 04–09 全部规格
- `00_APPROVED_VISUAL_REFERENCE_v1.9.html`
- `APPLE_DESIGN_SKILL_REFERENCE.md`

### 可复制话术

```text
你现在负责 Codex Monitor 的 Phase 0A：P0 前置审查。

请完整读取项目中的：
README_START_HERE.md
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
12_PHASE_MODEL_SWITCHING_AND_EXECUTION_PLAYBOOK_v1.0.md
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md

然后按照 Master PRD 的引用关系继续读取 04–09 全部规格，并查看：
00_APPROVED_VISUAL_REFERENCE_v1.9.html

同时确认 apple-design Skill 是否已经安装并能够读取。
如果未安装，请先按项目要求安装/配置；
如果当前环境无法安装，请明确报告，不允许直接跳过。

本 Phase 只允许：
1. 检查规格之间是否存在冲突；
2. 检查 P0 是否遗漏关键验证；
3. 检查当前 Mac / Codex 环境是否具备执行 P0 的条件；
4. 给出 Phase 0B 的精确执行清单；
5. 创建 PHASE_0A_REPORT.md。

禁止：
- 编写正式 UI；
- 编写主体 App；
- 修改任何 FROZEN 产品决策；
- 跳过 P0；
- 开始 Phase 1；
- 猜测 Codex 协议或字段；
- 为了“继续开发”而绕过阻断项。

完成 PHASE_0A_REPORT.md 后立即停止。

最后一行必须写：
下一阶段建议：GPT-5.6 Terra / High

不要继续执行 Phase 0B。
```

### 必须产出
- `PHASE_0A_REPORT.md`

### 你检查什么
- 有没有发现规格冲突
- apple-design Skill 是否可读
- 是否具备跑 P0 的条件
- 有没有要求你做破坏性操作

### 通过后
**不要回复原 Task“继续”。**
新建 Task → 手动切到 **Terra / High** → 打开 `02_PHASE_0B_TERRA_P0_EXECUTION.md`
