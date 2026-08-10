# H1F / H1.1 — Terra / High — Bootstrap & Contract Implementation

> Execute only because `PHASE_H1R_REPORT.md` returned:
> **PASS WITH REQUIRED FIXES — REQUIRE H1F BEFORE H2**
>
> This phase is the executable implementation of the already-reviewed H1 contract layer.
> It must not absorb H2 transport, H3 reducer, UI, persistence, or capability promotion.

## Model

```text
GPT-5.6 Terra
Reasoning: High
Speed: Standard
```

## Must read

```text
17_MASTER_PRD_V2_HYBRID.md
14_ARCHITECTURE_REVISION_HYBRID_V1.md
FINAL_AR_P0_REPORT.md
19_CAPABILITY_BASELINE_AND_GATES.md
H1_CAPABILITY_BASELINE.md
H1_ADAPTER_CONTRACTS.md
H1_TRANSPORT_DECISION.md
PHASE_H1_REPORT.md
PHASE_H1R_REPORT.md
```

## Copy-ready prompt

```text
你现在负责 Codex Monitor Hybrid v1 的 H1F / H1.1：Bootstrap & Contract Implementation。

请先完整读取：

17_MASTER_PRD_V2_HYBRID.md
14_ARCHITECTURE_REVISION_HYBRID_V1.md
FINAL_AR_P0_REPORT.md
19_CAPABILITY_BASELINE_AND_GATES.md
H1_CAPABILITY_BASELINE.md
H1_ADAPTER_CONTRACTS.md
H1_TRANSPORT_DECISION.md
PHASE_H1_REPORT.md
PHASE_H1R_REPORT.md

当前 gate：

H1 contract specification = PASS
H1 implementation = NOT COMPLETE
H1R = PASS WITH REQUIRED FIXES — REQUIRE H1F BEFORE H2
Release = INTERNAL / DEVELOPER ONLY

本阶段只允许实现 H1 contract layer 的可编译代码、测试和本地 Git 基线。

────────────────────
A. Local Git bootstrap
────────────────────

1. 在当前 Codex Monitor workspace root 执行：
   git init

2. 不创建 remote。
3. 不 push。
4. `git remote -v` 必须为空。
5. 保留全部现有 handoff/spec/report/evidence 文件。
6. 创建一个 local baseline commit。
7. H1F 完成后创建一个 scoped H1F implementation commit。
8. 在报告中记录 start/end commit IDs 和可审查 diff。

────────────────────
B. Swift contract/test skeleton
────────────────────

优先创建一个最小、可独立测试的 Swift Package：

Package.swift
Sources/CodexMonitorContracts/
Tests/CodexMonitorContractsTests/
Tests/CodexMonitorContractsTests/Fixtures/

要求：

- `swift build` 可运行；
- `swift test` 可运行；
- 不需要 UI target；
- 不加入第三方依赖，除非先停止并说明必要性；
- 不创建 H2 transport implementation。

────────────────────
C. Minimum compilable contract types
────────────────────

至少实现：

1. CapabilityState
   exactly:
   - unsupported
   - unvalidated
   - snapshot
   - liveAuthoritative
   - mutationValidated

2. granular CapabilityName / CapabilityID
   - 禁止 composite `fullRealtime`

3. SourceID
4. SourceKind
5. EntityKind
6. NamespacedID
   - source-sensitive equality/hash
   - entity kind participates
   - opaque non-empty raw ID

7. Freshness
8. ObservationMode
9. Authority
10. AccountEpoch
11. ConnectionEpoch
12. LifecycleEpoch
13. EvidenceMetadata
14. Provenance

15. AdapterDescriptor
16. immutable CapabilitySnapshot
17. AdapterOutput
18. AdapterRegistry

19. AccountSnapshot
20. RateLimitWindow
21. UsagePresence

22. SnapshotSummary
   - snapshot-only provenance
   - source classification = unclassified/unvalidated at baseline

23. OwnershipRecord
24. RuntimeObservationKind
25. CandidateRuntimeObservationEnvelope
26. LiveAdmittedRuntimeObservation
27. FutureObserverAdapter
   - all unsupported
   - zero outputs/data

所有 absence 必须保持 nil/absent，禁止自动造默认值。

SourceID 不能成为 stable account key。

────────────────────
D. Mandatory product-admission boundary
────────────────────

这是 H1F 最关键要求。

必须实现两个明确分离的路径：

CandidateRuntimeObservationEnvelope
        ↓
A. evidence / diagnostics / fixtures
        ↓
   可保留 unvalidated shape

CandidateRuntimeObservationEnvelope
        ↓
B. LiveProductAdmissionGate
        ↓
只有 capability == liveAuthoritative
并且 exact source/adapter/runtime/epoch/parent identity 全部匹配
        ↓
LiveAdmittedRuntimeObservation

硬规则：

1. Candidate decode/normalize != product eligibility。
2. `unsupported` → reject。
3. `unvalidated` → reject。
4. `snapshot` → reject。
5. 只有 `liveAuthoritative` 才能产生 live-admitted wrapper/token。
6. 当前 baseline 中真实 Adapter 的 liveAuthoritative 数量必须是 0。
7. `observationMode = live` 不能绕过 gate。
8. `authority = partial` 不能绕过 gate。
9. transport connected 不能绕过 gate。
10. ownership record presence 不能绕过 gate。
11. schema/method/event name presence 不能绕过 gate。
12. fixture/mock 不能绕过 gate。
13. sourceID/sourceKind/adapterID/adapterVersion/runtimeInstanceID/connectionEpoch/lifecycleEpoch 不匹配必须 reject。
14. supplied namespaced parent identity 不兼容必须 reject。
15. reject 后不得调用任何 reducer spy / product callback / notification / persistence / UI callback。

H1F 不实现真正 State Engine。
这里只实现 admission primitive。

────────────────────
E. Sanitized fixtures
────────────────────

实现最小 synthetic/redacted fixtures：

- account-snapshot-minimal-v1
- owned-thread-started-v1
- owned-thread-status-changed-v1
- owned-turn-started-v1
- owned-item-started-v1
- owned-item-completed-v1
- owned-turn-completed-success-v1
- owned-token-usage-shape-v1
- desktop-summary-unclassified-v1
- future-observer-empty-v1

每个 fixture 必须包含：

fixture ID
source kind
exact baseline capability
evidenceRun
CLI version
historical transport evidence label
probe/harness availability
sanitizer availability/version
confidence
limitations

硬规则：

- 不使用真实 email；
- 不使用 credential；
- 不使用 home path；
- 不使用真实 conversation content；
- 不使用 retained raw Thread/Turn/Item ID；
- 不使用看起来像当前真实 Session Token 的值；
- AR-P0 历史 transport evidence 继续保持 unresolved/inconsistent；
- H2 forward candidate `Unix-socket WebSocket` 必须是独立字段；
- Future Observer fixture 只能表示 zero-data expectation，不能制造 observation/snapshot/thread/health。

────────────────────
F. Executable tests
────────────────────

`swift test` 至少实现并执行以下 20 类断言：

1. capability taxonomy exactly five states
2. no fullRealtime shortcut
3. same raw ID across different sources != equal
4. entity kind participates in identity
5. provenance required/internal consistency
6. account connected != runtime available/IDLE
7. fresh quota != runtime state/ring/animation eligibility
8. Desktop raw active != THINKING/WORKING
9. account Usage != Session Token
10. schema presence != reset mutation
11. SnapshotSummary cannot enter live admission/reducer path
12. fixture/mock cannot promote real Adapter descriptor
13. Future Observer all unsupported + zero outputs
14. missing secondary/cost/details remain nil
15. Adapter/source lane isolation
16. capability downgrade rejects formerly eligible derived input
17. source/runtime/connection/lifecycle epoch mismatch rejected
18. matching but unvalidated real Adapter candidate rejected
19. unsupported/snapshot candidate rejected from live path
20. H2 Unix-socket forward decision does not rewrite unresolved AR-P0 historical transport evidence

额外建议测试：

- product-admission rejection invokes zero callback/reducer spy
- fixture provenance is distinguishable from real Adapter provenance
- raw IDs never compare equal across namespaces

────────────────────
G. Build acceptance
────────────────────

H1F 只有全部满足才算通过：

git rev-parse --is-inside-work-tree  => true
git remote -v                        => empty
swift build                          => exit 0
swift test                           => exit 0
required tests                       => zero skipped
library target                       => present
test target                          => present
H1 contracts                         => compile
Future Observer outputs              => zero
real liveAuthoritative capabilities  => zero
H2 transport implementation          => absent
H3 reducer                           => absent
UI                                   => absent
database/persistence                 => absent
capability promotion                 => none

────────────────────
H. Explicit prohibitions
────────────────────

H1F 不得：

- open Unix/TCP sockets
- implement WebSocket framing
- implement JSON-RPC
- initialize app-server
- launch/supervise runtime
- implement Account transport calls
- implement Desktop transport calls
- implement Monitor-owned transport calls
- implement live reducer
- implement SwiftUI/AppKit UI
- implement SQLite
- implement notifications
- implement WAITING_APPROVAL
- enable Session Token
- enable live multi-thread
- enable real FAILED/INTERRUPTED
- implement reconnect/reconstruction
- implement current-activity product text
- enable Desktop product rows
- enable Desktop live state
- consume reset credit
- promote any capability
- relabel historical AR-P0 transport evidence
- create Git remote
- push

────────────────────
I. Required outputs
────────────────────

生成：

PHASE_H1F_REPORT.md

并在报告中记录：

- model/reasoning
- start commit
- end commit
- files changed
- package/target layout
- exact `swift build` result
- exact `swift test` result
- test count
- skipped test count
- fixture provenance audit
- forbidden-inference audit
- product-admission audit
- capability baseline at end
- `git remote -v` result
- deviations
- confirmation: no H2/H3/UI/DB work
- confirmation: no capability promotion

完成后立即停止。

不得进入 H2。

最后写：
下一阶段建议：GPT-5.6 Sol / High — H1FR Contract Implementation Review
```

## Stop condition

H1F is not self-authorizing for H2.
