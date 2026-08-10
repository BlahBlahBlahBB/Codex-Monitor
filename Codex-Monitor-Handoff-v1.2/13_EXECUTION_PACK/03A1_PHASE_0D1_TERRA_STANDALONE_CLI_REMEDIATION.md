# Phase 0D.1 — Terra / High — Standalone CLI Environment Remediation

> Trigger: Phase 0D found that `codex remote-control start` exists, but the managed daemon cannot start because the standalone Codex installation/package is missing.
>
> This phase is environment remediation + P0 revalidation only. It is **not Phase 1**.

## Model

```text
GPT-5.6 Terra
Reasoning: High
Speed: Standard
```

## Goal

Use only the current official Codex installation path exposed by OpenAI to install/update the standalone Codex CLI, then retry the local managed daemon/control socket and rerun the live observer gates.

## Copy-ready prompt

```text
你现在负责 Codex Monitor 的 Phase 0D.1：Standalone CLI Environment Remediation。

背景：
Phase 0D 已确认：
- `codex remote-control start` 在本机版本中存在；
- 但 managed daemon 因缺少 standalone managed install/package 无法启动；
- control socket 因此仍不存在；
- Desktop-created Turn observer 仍为 NOT TESTED；
- 当前仍然 NO-GO；
- 不允许进入 Phase 1。

请读取：
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md
P0_REPORT.md
PHASE_0C_REPORT.md
P0_REPORT_REVALIDATION_DRAFT.md
PHASE_0D_REPORT.md
以及 P0_EVIDENCE_20260810_0D。

本阶段只处理当前已知环境阻断并重新验证 P0，不开发正式 UI。

第一步：确认当前安装来源
1. 记录：
   - `which codex`
   - `codex --version`
   - 当前 codex binary 的实际路径 / symlink 信息
2. 不读取 credential。
3. 检查当前安装是否来自 desktop bundled binary、npm/homebrew、或 standalone installer，依据实际文件路径和本机可验证信息判断。

第二步：使用官方 standalone installer
4. 只允许使用 OpenAI 官方当前安装方式安装/更新 Codex CLI：
   `curl -fsSL https://chatgpt.com/codex/install.sh | sh`
5. 如果安装过程需要用户批准网络/写入 ~/.local/bin 或 CODEX_HOME，请停下来请求我批准。
6. 禁止：
   - sudo 安装，除非官方安装器明确要求且我另外批准；
   - 删除现有 Codex Desktop；
   - 修改 auth.json；
   - 导出 access token / refresh token；
   - 使用第三方安装脚本；
   - 覆盖或移动 ChatGPT/Codex Desktop App bundle。
7. 安装后重新记录：
   - `which codex`
   - `codex --version`
   - standalone package/cache 是否存在
   - PATH 是否实际指向 standalone CLI
8. 如 PATH 仍指向旧 binary，不要猜；明确记录并使用官方安装器给出的路径进行本阶段验证。

第三步：retry remote-control managed daemon
9. 再次检查：
   - `codex remote-control --help`
   - `codex remote-control start --help`
10. 使用本机 help 明确支持的命令启动 managed daemon。
11. 不重启/kill Codex Desktop。
12. 验证：
   - daemon start 结果；
   - control socket 是否出现；
   - socket 实际路径；
   - socket 权限；
   - 不记录任何 credential。

第四步：P0Probe 连接
13. 如果 control socket 出现，使用已有 `Tools/P0Probe`：
   - WebSocket HTTP Upgrade
   - initialize
   - initialized
   - account/read
   - account/rateLimits/read
   - account/usage/read
   - thread/loaded/list
14. 所有输出必须 sanitizer。

第五步：Desktop-created Turn live observer hard gate
15. Probe 保持连接。
16. 不允许 Probe 自己创建/启动测试 Turn。
17. 如果需要用户人工配合，请停下来并明确提示：
   “请现在在 Codex Monitor Project 中另外新建一个普通 Codex Chat，发送一个无害测试任务，例如：读取 README_START_HERE.md 第一行标题，不修改文件。完成发送后回来告诉我。”
18. 在用户完成后，Probe 必须证明它能否看到该 Desktop-created Turn 的：
   - thread identity；
   - thread/status/changed；
   - turn/started；
   - item lifecycle；
   - turn/completed。
19. 只有实际收到证据才可 PASS。

第六步：passive approval observer
20. 只有在 Desktop-created Turn observer 已 PASS 后再测试。
21. Probe 不得 approve / decline。
22. 如果无法安全触发 approval，标记 NOT TESTED。
23. 如果能安全触发，验证 secondary Probe 是否看到 approval request 与 authoritative resolution。
24. 未收到真实证据不得判 PASS。

第七步：reconnect
25. 仅断开/重连 P0Probe 本身，不 kill Desktop/daemon。
26. 验证重新 initialize + snapshot/thread reconcile。

第八步：输出
27. 生成：
   - `P0_REPORT_REVALIDATION_V2_DRAFT.md`
   - `PHASE_0D1_REPORT.md`
   - `P0_EVIDENCE_<timestamp>_0D1/`
28. 所有门槛标记 PASS / PARTIAL / FAIL / NOT TESTED。
29. 不得进入 Phase 1。

特别注意：
- standalone CLI 安装成功 != Desktop observer PASS；
- control socket 出现 != Desktop observer PASS；
- 独立 app-server 能启动 != 能观察 Codex Desktop-created Turn；
- 最关键硬门槛始终是 secondary client 对 Desktop-created Turn 的真实 observer evidence。

完成后停止。
最后写：
下一阶段建议：GPT-5.6 Sol / High — Phase 0E Final Revalidation Review
```

## Success condition

The phase is successful only if it obtains live evidence for the Desktop-created Turn observer gate.

Installing the standalone CLI alone is not a P0 success.
