# Phase 0D — Terra / High — Control Socket / Remote-Control Revalidation

> Trigger: Phase 0C returned NO-GO because the control socket was absent and live observer gates remained NOT TESTED.
> This is a P0 remediation branch, not Phase 1.

## Model

- GPT-5.6 Terra
- Reasoning: High
- Speed: Standard

## Goal

Determine whether the missing control socket is a recoverable runtime/environment condition using only capabilities exposed by the installed Codex build, then rerun the live P0 observer gates.

Passing “a Unix socket exists” is not enough. The key question remains: can a separate Monitor client observe a Turn created in Codex Desktop?

## Copy-ready prompt

```text
你现在负责 Codex Monitor 的 Phase 0D：Control Socket / Remote-Control Revalidation。

背景：
Phase 0C 的最终结论为 NO-GO，但同时确认：
- control socket 缺失属于可重新验证的环境/运行条件问题；
- live attach / Desktop-created Turn / passive approval observer / reconnect 等门槛仍为 NOT TESTED；
- 不允许直接进入 Phase 1。

请读取：
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md
P0_REPORT_DRAFT.md
P0_REPORT.md
PHASE_0B_REPORT.md
PHASE_0C_REPORT.md
以及 P0_EVIDENCE_20260810_0B。

本 Phase 只做 P0 补验证，不做正式 UI，不做 Phase 1。

第一部分：能力发现
1. 记录 `codex --version`。
2. 运行并保存脱敏输出：
   - `codex app-server --help`
   - `codex remote-control --help`
   - `codex remote-control start --help`
   - 如本机存在相关 doctor/status 子命令，也记录只读状态输出。
3. 不假设文档命令一定与本机版本一致，以本机 `--help` 为准。

第二部分：非破坏性恢复 control socket
4. 如果本机明确支持官方 `codex remote-control start`：
   - 先检查是否已有 daemon；
   - 已有则不重启、不替换；
   - 没有则只使用本机帮助明确支持的方式启动；
   - 机器可读/JSON 输出仅在本机明确支持时使用。
5. 禁止 kill/replace Codex Desktop；禁止读取/修改 auth 凭证；禁止 private backend。
6. 记录 daemon 是否启动、control socket 是否出现、实际 socket 路径与权限；不记录 credential。

第三部分：Unix socket P0 Probe
7. 使用已有 `Tools/P0Probe` 连接实际 Unix socket。
8. 验证 WebSocket HTTP Upgrade、initialize、initialized、account/read、account/rateLimits/read、account/usage/read、thread/loaded/list。
9. 所有输出必须经过 sanitizer。

第四部分：Desktop observer 硬门槛
10. Probe 保持连接后，验证一个“由 Codex Desktop 创建，而不是由 Probe 创建”的新 Turn。
11. 如果需要我人工配合，请暂停并明确告诉我：
   “请现在在 Codex Monitor Project 的另一个新 Chat 中发送一个无害测试任务，完成后回来告诉我。”
12. Probe 必须记录能否看到 thread identity、thread/status/changed、turn/started、item lifecycle、turn/completed。
13. 不得由 Probe 自己 start/resume 一个 Turn 来替代这个门槛。

第五部分：passive approval observer
14. 仅在无害情况下测试。
15. 如需我配合，请让我在另一个 Codex Desktop Chat 触发一个无害、可能需要授权的操作并停在授权 UI。
16. Monitor Probe 不得 approve / decline。
17. 验证 secondary Probe 是否收到 approval request 与 authoritative resolution。
18. 如果无法安全触发，标记 NOT TESTED，不得猜 PASS。

第六部分：reconnect
19. 只断开/重连 Probe 自身，不 kill Codex Desktop。
20. 验证重新 initialize、snapshot reconcile、thread identity 与事件流恢复。

第七部分：结论
21. 输出：
   - `P0_REPORT_REVALIDATION_DRAFT.md`
   - `PHASE_0D_REPORT.md`
   - 新的 sanitized evidence 文件夹
22. 每个门槛标记 PASS / PARTIAL / FAIL / NOT TESTED。
23. 必须明确区分：
   A. `codex app-server --listen unix://` 能建立独立 app-server；
   B. `codex remote-control` 能启动 managed daemon；
   C. secondary Monitor client 能否观察 Codex Desktop-created Turn。
   A/B 不能自动证明 C。
24. 不得因为 socket 出现就把 Desktop observer 自动判 PASS。
25. 不得进入 Phase 1。

如果 live observer 仍 FAIL/NOT TESTED，停止并保留 NO-GO。
如果核心 live observer 通过，也不要进入 Phase 1，交给 Sol 复审。

最后写：
下一阶段建议：GPT-5.6 Sol / High — Phase 0E Revalidation Review
```
