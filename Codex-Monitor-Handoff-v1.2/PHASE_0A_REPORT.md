# Codex Monitor — Phase 0A Report

Phase: 0A — P0 前置审查  
Model used: GPT-5.6 Sol（按本 Task 指定执行配置）  
Reasoning level: High  
Start commit: N/A（当前目录不是 Git repository）  
End commit: N/A（本阶段未初始化 Git、未提交）  
Specs read: README、Master PRD、Phase Playbook、P0 Plan、04–09、v1.9 Visual Reference、Apple Design reference 与本机 apple-design Skill  
Tests run: 交接包 SHA-256 校验；macOS/Xcode/Swift/Codex CLI 只读环境盘点；Swift 编译器冒烟测试；默认 control socket 存在性检查  
Result: **CONDITIONAL PASS — 可以开始独立的 Phase 0B Task，但所有协议能力仍为未验证，严禁据此开始 Phase 1 或正式 UI。**

## 1. Phase 0A 范围与完成状态

本阶段只完成了理解、审查、P0 准备与本报告。未创建正式 UI，未创建主体 App，未创建或运行 P0 Probe，未生成 schema，未执行 initialize/account/rate-limit/usage 请求，未消费 reset credit，未进入 Phase 0B 或 Phase 1。

交接包 `MANIFEST.json` 中列出的全部文件均通过 SHA-256 校验。Phase 0A 明确要求的以下资料已完整读取：

1. `README_START_HERE.md`
2. `11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md`
3. `12_PHASE_MODEL_SWITCHING_AND_EXECUTION_PLAYBOOK_v1.0.md`
4. `10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md`
5. `04_STATE_ENGINE_AND_EVENT_MAPPING_v1.1_FROZEN.md`
6. `05_ACCOUNT_USAGE_QUOTA_AND_RESET_MODEL_v1.0.md`
7. `06_LOCAL_DATABASE_AND_SWIFT_DATA_LAYER_v1.0.md`
8. `07_MACOS_SWIFTUI_APPKIT_ARCHITECTURE_v1.0.md`
9. `08_DESIGN_SYSTEM_AND_COMPONENT_SPEC_v1.0.md`
10. `09_USER_FLOWS_INTERACTION_AND_EDGE_CASES_v1.0.md`
11. `00_APPROVED_VISUAL_REFERENCE_v1.9.html`
12. `APPLE_DESIGN_SKILL_REFERENCE.md`

## 2. apple-design Skill

状态：**PASS / 可用且可读**

本机路径：

```text
/Users/shouchen.nsc/.codex/skills/apple-design/SKILL.md
```

该 Skill 已完整读取。其原则与项目方向总体一致，尤其是即时反馈、空间一致性、克制的材质层级、系统字体、Reduce Motion、Reduce Transparency、可访问性和原生控件优先。冲突处理按 Master PRD 执行：

```text
FROZEN 产品决策 > 通用 apple-design 建议
```

例如，Skill 对弹性、速度继承和手势动效的通用建议不得改变本项目已冻结的 `~0.8 s` 亮度呼吸、无缩放、无外发光、完成 5 秒、红色终态 15 秒等规则。

## 3. 规格冲突审查

结论：**未发现阻止 Phase 0B 启动的 FROZEN 产品决策冲突。** 以下差异必须按既定优先级处理，不允许自行重新设计。

| 级别 | 差异 | 处理结论 |
|---|---|---|
| P0 Critical Unknown | P0 文档把 control socket framing 写死为“Unix socket 上的 HTTP WebSocket Upgrade”；本机 `codex app-server --help` 只确认 `unix://` transport，而 `proxy --help` 描述为把 stdio bytes 转发到 control socket，单靠帮助信息不能证明具体 framing。 | Phase 0B 必须从本机 daemon、doctor、实际握手与生成类型取得证据；Probe 不得预先硬编码 WebSocket 假设。若 framing/observer path 不受支持，按 hard gate 停止。 |
| Workflow | `10_P0` 使用 `P0_REPORT.md`，而 Phase Playbook/Execution Pack 要求 Phase 0B 输出 `P0_REPORT_DRAFT.md`，Phase 0C 才输出最终 `P0_REPORT.md`。 | 按后续 Phase 执行规则：0B 只写 Draft，0C 审核后写最终报告。 |
| Low | `08` 引用的视觉文件名是 `Codex-Monitor-Visual-Review-Mobile-v1.9.html`，包内实际文件为 `00_APPROVED_VISUAL_REFERENCE_v1.9.html`。 | 以 Master PRD 与实际文件名为准；不另造第二份视觉文件。 |
| Low | 早期规格/HTML 使用 `px`，Master PRD 和原生实现要求 `pt`；HTML Slider 示例仍显示 `90 px`。 | 原生产品统一使用 point，显示 `90 pt`。HTML 仅作视觉参考。 |
| Low | Usage 2×2 指标的首项在部分文件/HTML中写作“今日”，Master PRD 明确为“今日费用”。 | 使用“今日费用”；值无权威费用时显示 `$--`。 |
| Clarification | 全局优先级把 `DISCONNECTED` 放在最后，但连接丢失章节要求立即呈现 `DISCONNECTED`；若直接把断线与缓存 thread 一起比较，旧状态可能错误获胜。`PAUSED` 也更像全局 presentation override。 | 实现时先应用 connection/pause 全局 override，再聚合当前连接世代内的 per-thread 状态。P0 fixture 必须覆盖“有缓存 active/terminal 状态时断线”。不修改冻结的线程优先级。 |
| Resolved in source | `04` 前段仍写红色终态时长为 open decision，后续 §15 与 Master PRD 已冻结为 15 秒。 | 15 秒为最终值，无需产品决策。 |
| Prototype-only | HTML 中存在 fake traffic lights、custom switches/slider、账户切换按钮和 CSS Glass。 | 全部受“visual reference only”约束；生产必须使用 NSWindow/native Toggle/native Slider/native Liquid Glass，账户切换仅在 P0 证明官方能力后启用。 |

## 4. P0 计划的关键补强项

`10_P0` 已覆盖大多数核心能力，但 Phase 0B 必须补充或显式扩大以下验证，否则证据不足：

1. **CLI 与运行中 app-server 版本一致性**：同时记录 CLI 版本、schema 生成器来源、运行中 daemon/app-server 版本。若版本不同，不能仅凭 CLI 生成 schema 声称与运行端一致。
2. **transport framing、socket ACL 与认证要求**：确认真实 control socket 路径、字节 framing、是否需要 WebSocket Upgrade、是否需要 capability/auth、secondary client 权限；直接 socket 与 proxy 必须分别记录结果。
3. **发布形态等价性**：命令行 Probe 能连接并不自动证明签名后的 macOS App 能连接。必须明确 App Sandbox/entitlement/hardened-runtime 策略，并至少验证与预期生产约束等价的 Swift Probe。
4. **snapshot 与实时事件竞态**：验证 initialize 后并行 snapshot 与实时通知之间不会漏事件或用旧快照覆盖新事件；覆盖重复、乱序、旧 connection epoch、旧 turn/item 事件。
5. **更完整的脱敏范围**：现有 credential-key 规则不够。fixtures 还应默认脱敏 email/account ID、用户消息、thread title、命令参数、绝对 home path、文件内容与业务敏感字段；Token usage 数字采用明确 allowlist 保留。
6. **报告矩阵扩展**：`10_P0` 的简版 A–J 模板没有覆盖全部 22 个步骤。Phase 0B 报告必须逐项标记 `PASS / PARTIAL / FAIL / NOT TESTED`，至少单列 schema、initialize、sparse merge、loaded threads、subscription、item lifecycle、terminal mapping、multi-thread、reset read、sleep/wake、backpressure、sanitizer。
7. **schema 搜索项补全**：除原清单外，显式检查 `account/updated`、现有 thread attach/subscribe/reconciliation 方法、thread read/list 的 pagination/cursor 与 approval resolution 的精确 stable 类型。
8. **本地日期语义**：`account/usage/read` 必须验证 daily bucket 的日期/时区语义，不能只记录字段名，否则 30 个本地日历日可能错位。
9. **observer 安全性**：验证被动 Monitor 连接在收到 server request 时可以不 accept/decline，且不会抢占 Codex Desktop 的 request ownership；一旦协议要求 Monitor 响应，立即安全断开并标 FAIL。

## 5. 当前 Mac / Codex 环境

| 项目 | 结果 | 判定 |
|---|---|---|
| macOS | 26.5.2 (Build 25F84) | PASS，满足 macOS 26+ |
| CPU | arm64 | PASS |
| Xcode | 26.6 (17F113) | PASS |
| macOS SDK | 26.5 | PASS |
| Xcode license | `xcodebuild -license check` 成功 | PASS |
| Swift | 6.3.3；target `arm64-apple-macosx26.0` | PASS |
| Swift 冒烟测试 | 沙箱内使用 `/private/tmp` module cache 成功；沙箱外默认 cache 也成功 | PASS；Phase 0B 应显式使用 task-specific writable module cache |
| Codex binary | `/Applications/ChatGPT.app/Contents/Resources/codex` | PASS |
| Codex version | `codex-cli 0.147.0-alpha.6.5` | AVAILABLE，但 alpha 构建提高了版本/schema 证据要求 |
| app-server 命令 | `app-server`、`daemon`、`proxy`、`generate-json-schema`、`generate-ts` 均存在 | PASS for tooling availability；生成器命令自身标注 experimental，但不传 `--experimental` 时仍需验证生成内容的 stable 边界 |
| doctor | `codex doctor --json` 选项存在 | PASS for tooling availability；本阶段未运行 |
| CODEX_HOME | 当前 shell 未显式设置 | INFO；必须由 doctor/initialize 发现，不能硬编码 |
| 默认 control socket | `/Users/shouchen.nsc/.codex/app-server-control/app-server-control.sock` 当前不存在；`daemon version` 无法连接 | NOT READY / expected P0 discovery；Phase 0B 需在 Codex runtime 处于可测试状态时诊断 |
| 其他 socket | 仅观察到 `/Users/shouchen.nsc/.codex/ipc/ipc.sock` | 不得把它猜作 app-server control socket |
| Python / Node | Python 3.9.6、Node 18.15.0 | 可用于 disposable diagnostics；生产仍必须 Swift |
| 可用磁盘 | 约 503 GiB | PASS |
| Git | 当前目录不是 Git repository | 非 P0 技术阻断；Phase 报告不能伪造 commit ID |
| App 源码 | 当前仅有 handoff bundle | 与 Phase 0A 预期一致 |

环境结论：**具备开始 Phase 0B 的基础工具条件，但 control-plane attach 尚未建立，完整 P0 条件仅可在 Phase 0B 通过实际证据判定。**

## 6. 破坏性、消耗性或会扰动外部状态的操作

已发现以下操作，Phase 0B 不得无条件执行：

1. `10_P0` 示例中的两个 `rm -rf "$HOME/Desktop/Codex-Monitor-P0/schema/..."` 是破坏性操作。不得照抄。应创建新的、明确的 run-specific evidence 目录，或在精确验证目标目录与备份后另行取得授权；默认不覆盖既有证据。
2. `account/rateLimitResetCredit/consume` 会消耗真实 reset credit。Phase 0B 明确禁止 live consume；只做 schema、mock 与 fixture 验证，除非用户另行明确授权一次具体消耗。
3. daemon `start/restart/stop`、杀进程、重启 Codex、主动制造连接中断会影响用户当前工作。优先测试“仅断开 Probe 客户端”的 benign reconnect；如必须扰动 Codex-owned runtime，先与用户协调且不得使用 kill。
4. account sign-out/switch 会改变外部账户状态。只允许用户在 Codex UI 中执行，Monitor 不处理凭据。
5. Mac sleep/wake 会中断当前工作流。必须由用户选择安全时机，未执行时标 `NOT TESTED`，不得伪造 PASS。
6. 正常 Codex 任务、approval 场景和 usage update 会消耗时间/配额并可能修改文件。只使用无敏感数据的临时目录与无害任务，approval 由用户在 Codex 中处理。
7. P0 证据目录按文档位于当前 workspace 之外；在受限执行环境中写入前需要明确的文件系统授权。不得用扩大权限或写入 Codex-owned `~/.codex` 来绕过。

## 7. Phase 0B 精确执行清单

Phase 0B 必须在**新的 Task** 中手动选择 **GPT-5.6 Terra / High**，读取 Phase 0B 执行文件、本报告、README、Master PRD 与 `10_P0`，并严格停留在 P0。

执行顺序：

1. 记录实际 model/effort、时间、工作目录；确认没有 Git commit 可记录时写 `N/A`。
2. 与用户确认 Codex Desktop 处于可测试状态，并确认 approval、account-change、sleep/wake 等需要人工参与的测试窗口。
3. 创建新的 run-specific P0 evidence 目录；不执行任何 `rm -rf`，不覆盖旧 evidence。若目录在 workspace 外，先取得写入授权。
4. 运行只读环境 inventory：`which codex`、版本、app-server help、`doctor --json`；只保存 doctor 的 redacted 输出。
5. 记录 CLI 与运行中 daemon/app-server 版本；若 daemon 未运行或版本不可得，明确标记，不自动 start/restart/kill。
6. 使用同一被测 Codex binary 生成 JSON schema 与 TypeScript bindings；不传 `--experimental`；保存命令、hash、版本与生成器标注。
7. 建立 exact-method/capability matrix，并检查本报告 §4 补充的方法、分页与订阅能力。缺失字段不得从其他版本复制。
8. 通过 doctor/initialize 发现真实 `codexHome` 与 socket；不要把 `.codex/ipc/ipc.sock` 当作 control socket；分别验证 direct socket 与 proxy，首先确定 framing/ACL/auth。
9. 创建 disposable `Tools/P0Probe/`，包含 README、transport、JSON-RPC routing、sanitizer、event recorder、fixture exporter 与 mock。Swift 优先；使用 task-specific writable module cache。
10. Probe 首先只验证 initialize → initialized 的顺序与返回 metadata；任何普通请求不得在 initialize 前发送。
11. 依次验证并脱敏记录 `account/read`、`account/rateLimits/read`、sparse update merge、`account/usage/read`、daily bucket 时区/日期语义。
12. 验证 `thread/loaded/list`、必要的 read/list/pagination 与官方 attach/subscribe/reconciliation；不得用 `thread/resume` 制造假观察能力。
13. 在 Codex Desktop 中启动由 Desktop 创建的无害 Turn；验证 secondary Monitor 能观察 thread/turn/item 全生命周期、identity correlation 与 current-action 所需类型。
14. 验证 `thread/tokenUsage/updated` 的 cumulative/delta、replay 与 thread correlation；Token usage 与 quota 必须分离。
15. 由用户在 Codex Desktop 中触发并处理无害 approval；Monitor 只观察，不 accept/decline；验证 request 与 resolution 的权威可见性。
16. 验证成功、用户中断、受控无害失败的 terminal status；验证同 thread 新 Turn 覆盖 retention，以及不同 thread 的全局优先级 fixtures。
17. 验证多线程 identity、snapshot/event race、重复/乱序/旧 epoch 处理；无法稳定 live 复现的部分使用已脱敏 fixture/mock，并明确区分 live 与 mock 证据。
18. 只读取 reset-credit count/details；live consume 标 `NOT TESTED`，使用 mock 验证 idempotency 与 response 后 full refetch。
19. 验证 account update/history scoping；主动切换仅在用户操作且官方能力存在时测试，不保存任何凭据。
20. 先用仅断开 Probe 的方式验证 reconnect；如需 daemon/Codex restart 或 sleep/wake，取得用户协调。overload/backpressure 只用 mock，不压测真实 Codex。
21. 使用扩展 sanitizer 测试集检查 credentials、PII、home path、命令、消息与文件内容；输出前二次扫描。raw 敏感 payload 不得进入仓库或报告。
22. 对全部 P0 步骤逐项写 `PASS / PARTIAL / FAIL / NOT TESTED`；出现 Desktop-created Turn 不可观察、需要凭据/private backend、或必须改变任务生命周期才能观察时，立即 hard stop。
23. 只产出 `P0_REPORT_DRAFT.md`、`PHASE_0B_REPORT.md` 与 sanitized evidence；不写正式 UI、不进入 Phase 1。Phase 0C 才能生成最终 `P0_REPORT.md` 与 GO/NO-GO。

## 8. Phase 0A 最终判定

- 规格审查：**PASS with documented clarifications**；没有需要先修改 FROZEN 产品决策的阻断冲突。
- apple-design Skill：**PASS**。
- P0 计划完整性：**CONDITIONAL PASS**；执行前必须纳入 §4 补强项和扩展 gate matrix。
- 机器/工具条件：**CONDITIONAL PASS**；Swift/macOS/Xcode/Codex tooling 可用，但 control socket/daemon/observer capability 尚未验证。
- 破坏性操作：**已识别并隔离**；Phase 0B 默认禁止递归删除、reset consume、kill/restart、自动 account switching。
- 是否允许开始 Phase 1 或正式 UI：**NO**。
- 是否允许在新 Task 开始 Phase 0B：**YES，且仅限 P0 实际验证。**

下一阶段建议：GPT-5.6 Terra / High
