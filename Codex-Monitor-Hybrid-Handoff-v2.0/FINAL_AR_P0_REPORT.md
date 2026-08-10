# FINAL AR-P0 REPORT — Hybrid Capability Decision Review

Phase: AR-P0R — GPT-5.6 Sol / High  
Date: 2026-08-10  
Architecture baseline: `14_ARCHITECTURE_REVISION_HYBRID_V1.md`  
Review scope: evidence and architecture decision only; no production implementation.

## Final decisions

### A. ARCHITECTURE IMPLEMENTATION DECISION

**CONDITIONAL GO**

H1 may begin only as the capability-contract, Adapter-registry, source/provenance-model, and sanitized-fixture phase defined by Hybrid v1. This is not authorization to claim or ship composite full realtime, and it is not authorization to enter H2 from this review.

The condition is structural: every unproved semantic must remain represented as `unvalidated`, `unsupported`, or disabled. H1 must not turn schema presence, event-name presence, aggregate counts, or a mock fixture into an enabled runtime capability.

### B. RELEASE MATURITY DECISION

**INTERNAL/DEVELOPER ONLY**

The reviewed baseline is not beta or public-release eligible. Official OpenAI documentation currently states that the app-server command and WebSocket transport are experimental and unsupported for production workloads. In addition, the complete Monitor-owned realtime contract and Desktop source classification are not validated. See [official OpenAI Codex App Server documentation](https://developers.openai.com/codex/app-server).

## Reviewed gate verdicts

| Gate | Final verdict | Decision meaning |
|---|---|---|
| AR-P0-A — Account semantics | **PARTIAL** | Runtime snapshot shapes exist; several field semantics and identity behaviors remain unvalidated. |
| AR-P0-B — Monitor-owned runtime | **PARTIAL** | Owned success lifecycle was observed, but the full realtime contract did not pass. |
| AR-P0-C — Desktop read-only snapshot | **PARTIAL** | Approved read-only calls worked as snapshots; ordinary Desktop Chat classification was not proved. |
| AR-P0-D — Transport maturity | **PASS** | The support boundary was honestly identified; that boundary is itself a release blocker. |
| AR-P0-E — Reset mutation | **NOT RUN** | No authorization was given and no real credit was consumed; production mutation stays disabled. |

## Evidence reviewed

- `AR_P0_REPORT_DRAFT.md`
- `PHASE_AR_P0_REPORT.md`
- `AR_P0_CAPABILITY_MATRIX.json`
- `AR_P0_EVIDENCE_20260810_01/sanitized/probe_summary.json`
- `AR_P0_EVIDENCE_20260810_02/sanitized/probe_summary.json`
- `AR_P0_EVIDENCE_20260810_01/environment/runtime_transport.md`
- `AR_P0_EVIDENCE_20260810_01/fixtures/owned_runtime_failed_terminal_fixture.json`
- All earlier sanitized P0 evidence in `P0_EVIDENCE_20260810_0B`, `P0_EVIDENCE_20260810_0D`, and `P0_EVIDENCE_20260810_0D1`
- Current official OpenAI Codex App Server documentation

All retained JSON evidence parsed successfully. A static credential/email/home-path/private-key scan found no retained sensitive value in the reviewed evidence roots. The AR-P0 safety fields report no Desktop `thread/resume`/`thread/start`/`thread/fork`, no approval response, no reset-credit consume call, and no raw payload retention.

## Evidence integrity corrections

The draft artifacts are directionally honest, but the following corrections are binding for architecture decisions:

1. Both sanitized AR-P0 runs record `correlation.checked = 139`, not 141. The draft report, phase report, and capability matrix overstate this count.
2. `AR_P0_CAPABILITY_MATRIX.json` indexes only evidence root `_01`; `_02` is not referenced. The second run changes only its timestamp, salted digest, and one retained history turn count (8 to 9). It adds no new runtime capability proof.
3. `PHASE_AR_P0_REPORT.md` says `Tools/AR_P0Probe/ar_p0_probe.py`, its test file, and three passing tests were delivered. Those files are absent from the reviewed handoff. The correlation and sanitizer algorithms therefore cannot be independently reproduced or audited from this package.
4. Transport provenance is inconsistent: the sanitized summaries label the owned transport `loopback-websocket`, while `runtime_transport.md` says `Unix-socket WebSocket listener`. This does not erase the observed local app-server behavior, but exact transport binding is not reliably recorded.
5. The failed-terminal fixture explicitly contains no real runtime capture and cannot promote failed-terminal handling to `liveAuthoritative`.

These issues do not invalidate the Hybrid layering decision. They lower confidence in the affected granular capabilities and prohibit a composite full-realtime claim.

## AR-P0-A — Account semantics

### Supported at snapshot level

- `account/read` returned runtime shapes for `email`, `planType`, `type`, and `requiresOpenaiAuth`. Only returned fields may enter the Account contract; email is not a stable account key and must be privacy-masked in presentation.
- `account/rateLimits/read` returned a primary window with numeric `usedPercent`, `resetsAt`, and `windowDurationMins`, plus `rateLimitsByLimitId` and a reset-credit `availableCount`.
- `account/usage/read` returned summary numeric fields and daily buckets shaped as `startDate:string` plus `tokens:number`.
- The captured Usage shape contained no authoritative cost field. Product output remains `$--`.

### Not validated

- No non-secret stable account discriminator, account change, or account switching behavior was proved.
- Runtime presence and type do not prove full behavioral semantics for `resetsAt`, quota transitions, timezone boundaries, null handling, or daily-bucket normalization.
- The reset-credit `credits` array was empty. The count is snapshot-supported; detail element semantics were not observed at runtime.
- Six `account/rateLimits/updated` notifications were counted, but no payload shape, controlled transition, or merge sequence was retained. Sparse merge remains unvalidated; every notification must trigger a full authoritative refetch.
- The 30-day local-calendar chart and zero-fill policy cannot be enabled from this evidence alone because timezone/date-boundary semantics remain unvalidated.

### Account decision

Account snapshot contracts may proceed in H1 with field-level optionality, freshness, account/connection epochs, and explicit semantic confidence. Stable identity, sparse merge, reset details, authoritative cost, account switching, and mutation remain gated.

## AR-P0-B — Monitor-owned runtime

### What the retained evidence supports

- The summaries report an independently started `monitorOwnedRuntime`, assigned `sourceID` and `runtimeInstanceID`, with four newly created ephemeral Threads/Turns across success, approval-attempt, and interruption-attempt paths.
- Runtime notifications include `thread/started`, `thread/status/changed`, `turn/started`, `item/started`, `item/completed`, `thread/tokenUsage/updated`, and `turn/completed`.
- Four successful `turn/completed` terminal outcomes were retained.
- Item types included `reasoning`, `commandExecution`, `agentMessage`, and `userMessage`; hidden reasoning and raw content were not retained.
- Both runs report 139 checked correlated events and zero owned-set mismatches.
- The runtime process survived one client disconnect; a replacement connection reinitialized and completed `thread/loaded/list`.

### What the evidence does not support

- **Correlation strength:** “zero mismatches against the owned set” is an aggregate membership assertion. With no retained per-event correlation ledger and no probe implementation, it does not prove exact Thread → Turn → Item parentage or reject an event incorrectly attributed to another owned Thread.
- **THINKING / WORKING:** lifecycle method and Item-type delivery is sufficient to define gated contracts and fixture tests. It is not enough to claim complete state reduction, ordering, epoch rejection, or recovery behavior in production.
- **Current activity:** only Item types were retained. No safe user-visible activity selection, redaction, ordering, or truncation result was validated. Hidden reasoning must remain unavailable.
- **Approval:** neither an approval request nor authoritative resolution was observed. `WAITING_APPROVAL` and approval notifications remain disabled.
- **Session Token:** token update delivery and shape were observed, but no per-Thread numeric sequence was retained to establish correlation, `last` versus `total` cumulative/delta semantics, lifecycle-epoch freshness, or reconnect continuity. Session Token display remains disabled.
- **Multi-Thread isolation:** the owned-set mismatch count does not demonstrate correct per-Thread routing between the two intended test Threads. Live multi-Thread aggregation remains unvalidated.
- **Terminal coverage:** interruption raced completion and failed; no interrupted terminal was captured. No real failed terminal was captured. `INTERRUPTED` and `FAILED` projection from this Adapter remain gated.
- **Reconnect/reconciliation:** the replacement client could not read the owned Thread, and active reconstruction was not tested. Runtime-process survival after a socket client disconnect is not active reattachment.
- **Owner UI/process exit:** no owner-UI quit or supervisor handoff was tested. Safe active runtime survival/reattachment remains unvalidated.

### Owned-runtime decision

The core success lifecycle did not fail, so the architecture is not rejected. AR-P0-B is nevertheless **PARTIAL**, not full realtime PASS. H1 may model these capabilities separately; no single `fullRealtime = true` capability is allowed.

## AR-P0-C — Desktop read-only snapshot

### Supported boundary

- The AR-P0 runs report only `thread/loaded/list`, `thread/list`, and `thread/read(includeTurns:true)` on the Desktop proxy.
- `thread/list` returned 50 stored summaries; three sanitized reads returned history.
- `thread/loaded/list` returned an empty set before and after.
- Within each run, before/after salted digests matched and all 50 raw statuses were `notLoaded`.
- No Desktop lifecycle operation was reported. The mode is correctly labeled `snapshot_only_not_live`.

### Missing proof

- `source_kind_counts` is empty. The retained evidence does not prove that any of the 50 summaries or three history reads represents an ordinary Codex Desktop Chat.
- The unchanged before/after digest does not validate detection of a changed Desktop snapshot.
- A successful empty `loaded/list` response proves method availability, not loaded Desktop Thread discovery.
- Title/preview/timestamps/raw-status shapes may be represented in a snapshot contract, but Desktop content must not ship until source classification and privacy-safe correlation to a known Desktop test Thread are positively proved.

### Desktop decision

The Desktop Adapter must remain snapshot-only and excluded from live reduction, animation, duration, approval, current activity, terminal timers, notifications, Session Token, and recovery. Product-visible Desktop Thread rows remain disabled until source classification is validated.

## AR-P0-D — Transport support and maturity

- Installed evidence reports Codex CLI `0.147.0` and local app-server transport behavior.
- Current official documentation describes `stdio`, WebSocket, Unix-socket WebSocket, and `off` transports; it also says `thread/start` automatically subscribes its creator, while `thread/read` reads stored state without resuming or subscribing.
- The same documentation states that the app-server command and WebSocket transport are experimental and unsupported for production workloads.
- The AR evidence does not consistently identify whether the owned probe used loopback IP WebSocket or Unix-socket WebSocket. H2 must not begin until the selected local transport and its lifecycle/security assumptions are explicit.

AR-P0-D passes as an honest maturity assessment. The maturity result is a release restriction, not a production endorsement.

## AR-P0-E — Reset mutation

**NOT RUN.** The user did not authorize consumption of one real reset credit. Schema presence and a mock/fixture cannot validate mutation behavior. `account/rateLimitResetCredit/consume` remains hidden or disabled in production, and no implementation phase may silently enable it.

## Review of the 14 required decision questions

| # | Review finding | Binding decision |
|---:|---|---|
| 1 | Several draft entries promote returned shapes into broad semantics. | Treat runtime shapes as snapshot presence only; preserve separate semantic gates. |
| 2 | Owned runtime/Thread/Turn creation is reported, but provenance is self-attested and the harness is absent. | Accept only for bounded internal contracts; require reproducible provenance before release claims. |
| 3 | 139/0 owned-set checks exist; exact parent correlation is not retained. | Exact Thread/Turn/Item correlation remains partial. |
| 4 | Turn and Item lifecycle methods were captured. | Contracts for lifecycle-derived states may proceed; complete production state claims and current activity text remain gated. |
| 5 | No approval request or resolution was observed. | Approval capability is `unvalidated`; `WAITING_APPROVAL` disabled. |
| 6 | Token event shape exists; per-Thread sequence and cumulative/delta semantics do not. | Session Token display disabled. |
| 7 | Two intended Threads were exercised, but owned-set membership is not a cross-routing proof. | Multi-Thread live aggregation remains unvalidated. |
| 8 | Client-disconnect survival and reinitialize succeeded; active read/reconstruction failed or was not tested. | Reconnect/reconciliation and owner-UI survival are unvalidated. |
| 9 | Desktop operations were limited to approved reads and labeled snapshot-only. | Desktop Adapter may never emit live states. |
| 10 | No AR-P0 Desktop `thread/resume`/`thread/start`/`thread/fork` workaround is reported. | The prohibition remains absolute. Earlier P0 observer failures remain failures. |
| 11 | Account response shapes are known; stable identity and several semantics are not. | Show only returned, freshness-scoped, privacy-safe fields. |
| 12 | Update notifications were counted without controlled sparse payload semantics. | Continue full refetch; no sparse merge. |
| 13 | Reset mutation was not authorized or run. | Keep disabled and `unvalidated`. |
| 14 | Official maturity risk is recorded accurately. | Internal/developer only; public/beta release blocked. |

## H1 capability baseline authorized by CONDITIONAL GO

H1 may implement only the following architectural baseline:

- Granular capability states: `unsupported`, `unvalidated`, `snapshot`, `liveAuthoritative`, and `mutationValidated`, without a composite full-realtime shortcut.
- Adapter registry boundaries for Account, Monitor-owned Runtime, Desktop Snapshot, and an empty Future Observer Adapter that emits no fake data.
- First-class source/provenance models: `sourceID`, `sourceKind`, `runtimeInstanceID`, Adapter identity/version, observation mode, authority, freshness, account/connection/lifecycle epochs, and namespaced Thread/Turn/Item identities.
- Snapshot Account contracts for the actually returned shapes, with every field optional and freshness-scoped; primary rate-limit snapshot support; absent secondary values preserved as absent.
- Owned-runtime normalized envelopes and sanitized fixtures for observed success lifecycle methods and Item types, while marking all unproved sub-capabilities separately.
- Desktop `SnapshotSummary` contracts for read time, raw/coarse status, title/preview availability, history availability, and staleness; these records bypass live reduction.
- Explicit forbidden-inference tests: account connectivity cannot imply runtime availability; Desktop `active` cannot imply `THINKING`/`WORKING`; Usage cannot substitute for Session Token; schema presence cannot enable reset mutation.
- Evidence metadata that records source run, CLI version, exact transport, probe/harness version or digest, sanitizer version, and confidence/limitations.

## H1 prohibited or mandatory-gated capabilities

- No full-realtime product flag or claim.
- No `WAITING_APPROVAL`, approval notification, or monitoring-surface approve/decline control.
- No user-visible Session Token value.
- No live multi-Thread aggregation claim.
- No `FAILED` or `INTERRUPTED` projection from the real Adapter until real terminal captures pass.
- No active reconnect/reconstruction, missed-event recovery, or safe owner-UI survival claim.
- No hidden reasoning or unvalidated current-activity text.
- No product-visible ordinary Desktop Chat rows until positive Desktop source classification and privacy-safe correlation pass.
- No Desktop live state, animation, duration, terminal retention, approval, notification, token, or recovery behavior under any condition.
- No Desktop `thread/resume`, `thread/start`, or `thread/fork` observer workaround.
- No sparse rate-limit merge; full refetch remains mandatory.
- No stable-account-key claim, account switching, authoritative cost, reset-credit detail semantics, or timezone-sensitive Usage chart claim without new validation.
- No reset-credit consume action.
- No beta/public release positioning while the official transport support boundary remains experimental/unsupported and the above capability gaps remain open.

## Conditions for later capability promotion

Capability promotion requires new retained, reproducible evidence rather than edits to this report:

1. Deliver the disposable probe and tests, record their digest/version, and retain a privacy-safe per-event correlation ledger.
2. Capture exact Thread → Turn → Item routing across at least two simultaneously active owned Threads, including negative crossover assertions.
3. Capture approval request plus authoritative resolution without the monitoring surfaces responding.
4. Capture real interrupted and controlled failed terminal outcomes.
5. Retain privacy-safe token sequences proving Thread correlation, `last`/`total` semantics, lifecycle freshness, and reconnect continuity.
6. Prove active runtime reconciliation/reattachment and the owner-UI quit/supervisor boundary.
7. Positively classify and correlate a known ordinary Desktop Chat using only approved snapshot reads before enabling Desktop rows.
8. Re-review official app-server/transport production maturity before any beta or public-release decision.

## Stop condition

AR-P0R is complete. No production code was written, H1 was not started, and no reset mutation or Desktop lifecycle workaround was run.

下一阶段建议：GPT-5.6 Terra / High — H1 Capability Contracts & Adapter Registry

