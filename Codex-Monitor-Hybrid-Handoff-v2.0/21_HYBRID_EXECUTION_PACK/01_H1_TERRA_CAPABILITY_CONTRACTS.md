# H1 — Terra / High — Capability Contracts & Adapter Registry

## Authorization

H1 is explicitly authorized by `FINAL_AR_P0_REPORT.md`.

Nothing beyond H1 is authorized by this file.

## Copy-ready prompt

```text
你现在负责 Codex Monitor Hybrid v1 的 H1：Capability Contracts & Adapter Registry。

请先读取：

README_START_HERE_V2.md
17_MASTER_PRD_V2_HYBRID.md
14_ARCHITECTURE_REVISION_HYBRID_V1.md
FINAL_AR_P0_REPORT.md
19_CAPABILITY_BASELINE_AND_GATES.md
20_HYBRID_PHASE_MODEL_PLAYBOOK.md

以及需要参考的 LEGACY_REFERENCES/04–09，但只允许采用与 Hybrid v2 不冲突的规则。

当前正式结论：
Architecture = CONDITIONAL GO
Release = INTERNAL / DEVELOPER ONLY

本阶段只实现 H1 基线，不得进入 H2。

允许实现：

1. granular capability types：
   unsupported
   unvalidated
   snapshot
   liveAuthoritative
   mutationValidated

2. Adapter registry contracts：
   Account Adapter
   Monitor-owned Runtime Adapter
   Desktop Snapshot Adapter
   Future Observer Adapter

3. Future Observer Adapter 必须为空能力，不得产生 fake data。

4. source/provenance types：
   sourceID
   sourceKind
   adapterID / adapterVersion
   runtimeInstanceID
   observationMode
   authority
   freshness
   accountEpoch
   connectionEpoch
   lifecycleEpoch
   namespaced Thread/Turn/Item identity

5. Account snapshot contract：
   只建模实际观测到的 runtime shapes；
   每个字段 optional；
   freshness-scoped；
   不宣称 stable account key；
   不实现 sparse merge；
   不实现 account switching；
   authoritative cost 缺失时保持 nil。

6. Monitor-owned normalized observation envelope：
   只为已经观察到的方法/Item type 建立 contract；
   不启用产品能力；
   不建立 fullRealtime bool。

7. Desktop SnapshotSummary：
   read time
   raw/coarse status
   title/preview availability
   history availability
   staleness
   source classification state

8. sanitized fixtures：
   只使用现有证据支持的数据形状；
   fixture 必须标注 source/evidence provenance；
   mock/fixture 不得提升真实 Adapter capability。

9. forbidden-inference tests：
   - account connected != runtime available
   - fresh quota != runtime state
   - Desktop active != THINKING/WORKING
   - account Usage != Session Token
   - schema presence != reset mutation support
   - Desktop snapshot never enters live reducer
   - fixture/mock cannot promote liveAuthoritative

10. evidence metadata：
    evidence run
    CLI version
    exact transport label
    probe/harness version or digest when available
    sanitizer version
    confidence/limitations

11. 在 H1 内生成一份：
    `H1_TRANSPORT_DECISION.md`
    明确 H2 若被授权时准备采用的唯一 local transport、为什么、生命周期/权限/安全假设。
    只做决策文档；H1 不实现 transport。

12. 如当前 workspace 尚未是 Git repository：
    允许初始化本地 Git repository，
    但不要创建远程仓库、不要 push。
    如果你认为初始化 Git 会改变当前用户工作流，请先报告再执行。

硬禁止：

- fullRealtime flag
- WAITING_APPROVAL 启用
- approval notification
- user-visible Session Token
- live multi-Thread aggregation
- real FAILED/INTERRUPTED Adapter projection
- active reconnect/reconstruction
- missed-event recovery
- safe owner-UI survival claim
- unvalidated current-activity user text
- product-visible ordinary Desktop Chat rows
- Desktop live state
- thread/resume/start/fork observer workaround
- sparse rate-limit merge
- stable account key claim
- account switching
- authoritative cost 推算
- timezone-sensitive 30-day Usage 语义宣称
- reset-credit consume
- beta/public release positioning
- production UI

测试要求：

- capability contract tests
- namespaced identity tests
- provenance tests
- forbidden-inference tests
- fixture provenance tests
- no fake Future Observer data test

输出：

H1_CAPABILITY_BASELINE.md
H1_ADAPTER_CONTRACTS.md
H1_TRANSPORT_DECISION.md
PHASE_H1_REPORT.md

PHASE_H1_REPORT 必须记录：
Model used
Reasoning
files changed
tests
deviations
current capability gates
是否初始化 Git
下一阶段是否建议 H1R

完成后立即停止。
不得进入 H2。

最后写：
下一阶段建议：GPT-5.6 Sol / High — H1R Architecture Review
```
