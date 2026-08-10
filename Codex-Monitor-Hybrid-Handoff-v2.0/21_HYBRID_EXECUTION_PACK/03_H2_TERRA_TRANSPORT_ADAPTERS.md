# H2 — Terra / High — Transport Adapters & Owned Runtime Supervisor

> Execute only if H1R explicitly authorizes H2.

```text
你现在负责 H2。

读取 Master PRD v2、FINAL_AR_P0_REPORT、H1/H1R 报告、H1_TRANSPORT_DECISION。

只实现 H2 transport layer，不进入 H3。

实现：
- H1R 批准的唯一 local transport；
- JSON-RPC initialize/request-response/notification routing；
- Adapter-specific connection health；
- Account Adapter transport boundary；
- Monitor-owned Runtime Adapter transport boundary；
- Desktop Snapshot Adapter read-only boundary；
- Future Observer Adapter 空实现；
- owned runtime supervisor 的最小 lifecycle；
- connection/source epochs；
- sanitizer；
- exact transport provenance；
- reconnect 仅做到 H1/H2 明确授权的低层连接重建，不宣称 active state reconstruction。

必须保留 capability gates。

禁止：
- approval capability promotion；
- Session Token product enablement；
- live multi-thread claim；
- FAILED/INTERRUPTED real capability promotion；
- active recovery claim；
- Desktop live events；
- reset mutation；
- public/beta positioning。

输出：
PHASE_H2_REPORT.md

测试：
transport fixture tests
request/response correlation
adapter isolation
source health independence
Desktop write/lifecycle prohibition
Future Observer no-data
sanitization

完成后停止。
下一阶段建议：GPT-5.6 Sol / High — H2R
```
