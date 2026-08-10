# Phase 1 — Terra / High — Headless Transport

## 模型
- Terra High

## 目标
只完成无 UI 的 Codex Transport。

## 范围
- validated Unix socket / transport
- WebSocket / JSON-RPC
- initialize
- request/response matching
- notification routing
- server-request observation
- reconnect
- sanitizer
- fixture replay

## 可复制话术

```text
你现在负责 Phase 1：Headless Transport。

读取：
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
最终 P0_REPORT.md
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md
PHASE_0C_REPORT.md

只实现 Phase 1，不进入 UI。

必须实现：
- P0 已验证的本地 transport；
- initialize / initialized；
- JSON-RPC request-response correlation；
- notification routing；
- server-request passive observation；
- reconnect / backoff / generation；
- sanitization；
- mock/fixture replay tests。

禁止：
- 创建正式 SwiftUI UI；
- 修改 FROZEN 产品规则；
- 引入未在 P0 通过的 private capability。

完成条件：
- transport tests pass；
- reconnect tests pass；
- fixture/replay tests pass；
- 能输出 sanitized normalized transport events；
- 创建 PHASE_1_REPORT.md。

完成后停止。
最后写：
下一阶段建议：GPT-5.6 Sol / High — Phase 1 Review
```
