# H2R — Sol / High — Transport/Lifecycle/Security Review

```text
只审查 H2。

重点：
exact transport
JSON-RPC correctness
source isolation
connection epochs
owned-runtime supervisor safety
Desktop read-only guarantee
credential/privacy
no capability promotion by transport
no fake observer
no active-recovery overclaim

输出 PHASE_H2R_REPORT.md。

只有明确 AUTHORIZE H3 才可进入 H3。
完成后停止。
```
