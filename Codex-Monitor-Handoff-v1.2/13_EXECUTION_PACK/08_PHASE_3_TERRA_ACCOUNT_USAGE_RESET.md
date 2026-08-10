# Phase 3 — Terra / High — Account / Quota / Usage / Reset

```text
你现在负责 Phase 3。

读取：
05_ACCOUNT_USAGE_QUOTA_AND_RESET_MODEL_v1.0.md
Master PRD
P0_REPORT.md
PHASE_2R_REPORT.md

实现：
- account adapter；
- dynamic quota windows；
- sparse rate-limit merge；
- minimum remaining quota；
- account usage mapping；
- thread token usage；
- reset-credit read；
- reset consume adapter；
- idempotency key reuse；
- account epoch；
- unsupported field graceful degradation。

硬规则：
- 不估算 cost；
- 不从 Token 推 quota；
- 不保存 credentials；
- 不执行真实 reset credit 消耗，除非我单独明确授权。

测试后输出 PHASE_3_REPORT.md。
完成后停止。
下一阶段建议：GPT-5.6 Sol / High — Phase 3 Safety Review
```
