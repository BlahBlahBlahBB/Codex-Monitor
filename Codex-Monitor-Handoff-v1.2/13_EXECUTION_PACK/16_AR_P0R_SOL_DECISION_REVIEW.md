# AR-P0R — Sol / High — Hybrid Capability Decision Review

## Model

```text
GPT-5.6 Sol
Reasoning: High
Speed: Standard
```

## Copy-ready prompt

```text
你现在只负责 Codex Monitor 的 AR-P0R：Hybrid Capability Decision Review。

请读取：
14_ARCHITECTURE_REVISION_HYBRID_V1.md
PHASE_AR1_REPORT.md
AR_P0_REPORT_DRAFT.md
PHASE_AR_P0_REPORT.md
AR_P0_CAPABILITY_MATRIX.json
以及 AR-P0 的全部 sanitized evidence。

你的任务是审核证据，不写生产代码。

必须分别判断：
AR-P0-A — Account semantics
AR-P0-B — Monitor-owned runtime
AR-P0-C — Desktop read-only snapshot
AR-P0-D — Transport maturity
AR-P0-E — Reset mutation（若未授权运行则保持 NOT RUN）

重点审核：
1. 是否把 schema presence 错当 runtime semantics。
2. Monitor-owned runtime 是否真的使用 Monitor-created runtime/Thread/Turn。
3. Thread/Turn/Item correlation 是否可靠。
4. THINKING/WORKING/current activity 是否来自 authoritative lifecycle。
5. approval lifecycle 是否验证 request + resolution。
6. Session Token 是否可靠 correlate 到 owned Thread。
7. multi-Thread 是否不串线。
8. reconnect / active runtime survival 是否有真实恢复证据。
9. Desktop snapshot 是否严格 snapshot-only。
10. 是否出现 thread/resume observer workaround。
11. Account Layer 是否只展示验证字段。
12. sparse rate-limit update 未验证时是否继续 full refetch。
13. reset consume 未真实授权时是否保持 disabled/unvalidated。
14. transport experimental/production maturity 风险是否如实记录。

最终给出两个独立结论：

A. ARCHITECTURE IMPLEMENTATION DECISION
- GO
- CONDITIONAL GO
- NO-GO

B. RELEASE MATURITY DECISION
- INTERNAL/DEVELOPER ONLY
- BETA WITH DISCLOSURE
- PUBLIC RELEASE ELIGIBLE
- NOT YET RELEASE ELIGIBLE

注意：即使 AR-P0-B 技术 PASS，如果 app-server transport 的官方 production maturity 不足，也可以出现 Architecture GO 但 Public Release NOT YET ELIGIBLE。

如果 GO / CONDITIONAL GO：
明确列出 H1 可以实现的 capability baseline，以及 H1 中禁止实现/必须 gated 的能力。

生成：
FINAL_AR_P0_REPORT.md
PHASE_AR_P0R_REPORT.md

如果 Architecture GO / CONDITIONAL GO：
最后写：
下一阶段建议：GPT-5.6 Terra / High — H1 Capability Contracts & Adapter Registry

如果 NO-GO：
不得进入 H1，并列出阻断点。

完成后停止。
```
