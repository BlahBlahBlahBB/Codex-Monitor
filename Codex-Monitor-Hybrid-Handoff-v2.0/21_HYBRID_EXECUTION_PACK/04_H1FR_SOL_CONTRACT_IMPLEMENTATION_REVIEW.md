# H1FR — Sol / High — Contract Implementation Review

> Run only after H1F finishes.

## Model

```text
GPT-5.6 Sol
Reasoning: High
Speed: Standard
```

## Copy-ready prompt

```text
你现在只负责 Codex Monitor Hybrid v1 的 H1FR：Contract Implementation Review。

请读取：

17_MASTER_PRD_V2_HYBRID.md
FINAL_AR_P0_REPORT.md
H1_CAPABILITY_BASELINE.md
H1_ADAPTER_CONTRACTS.md
H1_TRANSPORT_DECISION.md
PHASE_H1R_REPORT.md
PHASE_H1F_REPORT.md

并检查：

- Git start/end commit
- H1F git diff
- Package.swift / project layout
- Sources/CodexMonitorContracts
- Tests/CodexMonitorContractsTests
- fixtures
- `swift build`
- `swift test`

重点审核：

1. H1 contracts 是否真正可编译。
2. 是否只有五个 capability states。
3. 是否不存在 composite fullRealtime。
4. NamespacedID 是否 source-sensitive + entity-kind-sensitive。
5. Provenance/freshness/epochs 是否强制且正确。
6. Adapter Registry 是否隔离四个 source kinds。
7. Future Observer 是否 all-unsupported + zero-data。
8. Desktop Snapshot 是否无法进入 live admission path。
9. Fixture/mock 是否无法 promote real Adapter capability。
10. Account/quota/Usage 是否仍保持 snapshot/optional/honest。
11. 最关键：CandidateRuntimeObservationEnvelope 与 LiveProductAdmissionGate 是否真正分离。
12. 匹配但 `unvalidated` 的真实 Adapter candidate 是否仍被拒绝。
13. unsupported/snapshot candidate 是否被拒绝。
14. source/runtime/connection/lifecycle epoch mismatch 是否被拒绝。
15. rejection 是否 zero product callback / zero reducer spy。
16. 当前 real `liveAuthoritative` capability count 是否为 0。
17. AR-P0 historical transport evidence 是否仍是 unresolved/inconsistent。
18. H2 forward decision 是否只是 Unix-socket WebSocket forward candidate，不改写历史 evidence。
19. 是否没有 H2 transport / H3 reducer / UI / DB。
20. Git remote 是否为空、无 push。

结论只允许：

PASS — AUTHORIZE H2
PASS WITH REQUIRED FIXES — DO NOT ENTER H2
FAIL — DO NOT ENTER H2

如果 PASS：
明确写：
下一阶段建议：GPT-5.6 Terra / High — H2 Transport Adapters & Owned Runtime Supervisor

如果需要修复：
列出最小修复项，停止，不得自己修改。

生成：
PHASE_H1FR_REPORT.md

完成后停止。
```
