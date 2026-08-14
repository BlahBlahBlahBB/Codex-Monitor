# Codex Monitor — Architecture Revision 1: Hybrid v1

> Status: **ARCHITECTURE REVISION — Ready for review; not implementation authorization**  
> Revision date: 2026-08-10  
> Historical inputs (retained only on `codex/github-readiness-audit`): `FINAL_P0_REVALIDATION_REPORT.md`, `PHASE_0E_REPORT.md`, specifications 04–11
> Supersedes: every conflicting runtime-observation, Desktop-state, reconnect, Session Token, approval, and phase-order statement in specifications 04–11  
> Does not authorize: old Phase 1, production code, UI implementation, `thread/resume`-as-observer, private APIs, scraping, or credential extraction

---

## 1. Decision

Codex Monitor v1 is revised from a universal secondary observer into a capability-driven Hybrid product with four explicit layers:

1. **Account Layer** — retain verified account, rate-limit, Usage, and reset-credit snapshot reads, with field-level capability and freshness.
2. **Monitor-owned Runtime Layer** — provide complete realtime state only for app-server instances, Threads, and Turns whose lifecycle Codex Monitor intentionally owns.
3. **Codex Desktop Layer** — treat ordinary Desktop Chats as snapshot/history sources only when stable read/discovery methods have been separately proved. Never present them as live.
4. **Future Observer Adapter** — reserve a source-neutral Adapter boundary for a future official passive Desktop subscription contract.

The old full-v1 claim — “a secondary Monitor connection can authoritatively observe any existing Codex Desktop Turn” — is removed.

The revision does not weaken the P0 decision. It changes the product so that a failed Desktop observer capability is no longer fabricated or required for Monitor-owned runtime functionality.

---

## 2. Evidence baseline

Hybrid v1 may rely only on the following P0 facts.

### 2.1 Proven

- Standalone Codex CLI `0.147.0` and the managed owner-only local control socket were reachable.
- WebSocket Upgrade and `initialize` / `initialized` succeeded.
- Successful stable-schema responses returned for `account/read`, `account/rateLimits/read`, and `account/usage/read`.
- `thread/loaded/list` returned a response, although retained evidence discarded the identities and counts.
- The stable schema contains the expected account reads, rate-limit update notification, reset-credit consume request, Thread reads/discovery, runtime notifications, and `thread/unsubscribe`.
- The tested stable schema contains no `thread/subscribe` request.

### 2.2 Not proven

- Discovery of the specific Desktop test Thread through `thread/loaded/list`.
- Desktop Thread discovery/history through `thread/list` and `thread/read`; these calls were not executed in Phase 0D.1.
- Secondary-client delivery of Desktop-created Thread, Turn, Item, approval, token, or terminal events.
- Passive approval request/resolution visibility.
- Desktop Session Token correlation.
- Desktop missed-event recovery or state reconstruction.
- Sparse rate-limit update semantics in a real transition.
- Stable cross-account identity, account switching, reset-credit consumption, or reset idempotency.
- Complete Usage field semantics, timezone behavior, or authoritative cost.
- Production support maturity of the app-server/WebSocket transport; current documentation classifies it as experimental/unsupported for production workloads.

### 2.3 Prohibited conclusion

The evidence does not prove that cross-client observation is impossible in every future implementation. It proves that the tested Desktop path failed and that the installed stable schema exposes no permitted passive subscription method. Hybrid v1 must encode that narrower conclusion.

---

## 3. Product modes and source identity

Hybrid v1 does not have one global “Codex connection.” It has independent sources.

| Source kind | Meaning | May produce realtime task state? | May own lifecycle? |
|---|---|---:|---:|
| `account` | Active account, limits, Usage, reset-credit data | No | No |
| `monitorOwnedRuntime` | Runtime instance and Threads explicitly created/managed by Monitor | Yes, when required capabilities pass | Yes |
| `desktopSnapshot` | Stable read-only Desktop discovery/history | No | No |
| `futureObserver` | Future official passive subscription Adapter | Yes, only after its own validation | No |

Every runtime record and observation must carry:

- `sourceID`
- `sourceKind`
- `adapterID` and adapter version
- account scope/epoch when known
- connection epoch
- Thread/Turn/Item identity when supplied
- observation mode: `snapshot` or `live`
- authority: `authoritative`, `partial`, or `unavailable`
- observed time and freshness/staleness
- the capability that authorizes the observation

IDs from different sources are namespaced. A Desktop Thread ID must never be silently reclassified as Monitor-owned.

---

## 4. Capability model

### 4.1 Capability states

Each Adapter reports a runtime `CapabilitySnapshot`. A capability is one of:

| State | Meaning |
|---|---|
| `unsupported` | Adapter/installed schema has no allowed implementation path. |
| `unvalidated` | A plausible stable method exists, but this environment has not proved the behavior. |
| `snapshot` | Authoritative only at a stated read time; no live claim. |
| `liveAuthoritative` | Correlated push lifecycle is proved for this source. |
| `mutationValidated` | A state-changing operation and its safety/idempotency semantics are proved. |

`unvalidated` is not equivalent to enabled. Product surfaces must behave as if the feature is unavailable until validation passes.

### 4.2 Required granular capabilities

Account capabilities:

- account identity snapshot
- plan/auth-mode fields
- stable local account discriminator
- rate-limit full snapshot
- sparse rate-limit updates
- Usage summary
- Usage daily buckets
- authoritative cost
- reset-credit count/details
- reset-credit consume
- account-change notification
- official account switching

Runtime capabilities:

- Thread discovery
- Thread snapshot/history read
- live Thread/Turn lifecycle
- Item lifecycle/current activity
- approval request/resolution lifecycle
- terminal outcome
- Session Token usage
- multi-Thread correlation
- reconnect/reconciliation
- lifecycle control for owned Threads

### 4.3 Initial capability posture from current evidence

| Capability | Initial state | Hybrid v1 decision |
|---|---|---|
| Account identity response | `snapshot` | Show returned fields only; no unproved stable identity claim. |
| Rate-limit full response | `snapshot` | Show authoritative returned windows with freshness. |
| Sparse rate-limit update | `unvalidated` | Prefer refetch; do not rely on live merge until tested. |
| Usage response | `snapshot`, field-partial | Map only schema/runtime-proved fields; unsupported cost stays `$--`. |
| Reset-credit count/details read | `snapshot`, field-partial | Show returned count/details only. |
| Reset-credit consume | `unvalidated` | Keep the domain contract, but hide/disable production action until an explicitly authorized mutation test passes. |
| Desktop Thread discovery/history | `unvalidated` | Disabled by default pending the bounded read-only probe. |
| Desktop realtime lifecycle | `unsupported` | Never emit live state. |
| Desktop approval | `unsupported` | Never emit `WAITING_APPROVAL`. |
| Desktop Session Token | `unsupported` | Omit. |
| Monitor-owned realtime lifecycle | `unvalidated` | Target capability; must pass the new owned-runtime gate before implementation claims full support. |
| Future official observer | `unsupported` today | Adapter slot only; no placeholder data. |

---

## 5. Layer A — Account Layer

### 5.1 Retained behavior

The Account Layer remains source-independent and may operate while no realtime runtime source exists.

Retain:

- `account/read`
- `account/rateLimits/read`
- `account/usage/read`
- dynamic quota windows rather than hard-coded 5-hour/weekly assumptions
- quota remaining derived only from authoritative `usedPercent`
- Orb center as the minimum remaining value among current authoritative quota windows
- reset-credit authoritative count and optional details
- `$--` when authoritative cost is unavailable
- 30 local calendar-day zero-filled chart when daily bucket semantics are validated
- account and connection epochs
- cache/staleness handling
- privacy masking and prohibition on credential storage

### 5.2 Required honesty

- Account connectivity is not runtime observability.
- Fresh quota does not mean Desktop task state is known.
- Usage daily buckets do not provide a current Session Token total.
- Reset-credit schema presence does not prove safe consumption.
- Email is not a stable account key unless the protocol explicitly guarantees it.
- Missing fields remain absent/`nil`; they are not synthesized.

### 5.3 Reset-credit mutation gate

The read capability is retained. The “立即重置” mutation remains in the domain design but is production-disabled until a separate, explicitly authorized validation proves:

- result mapping;
- same-attempt idempotency-key reuse;
- timeout behavior;
- mandatory rate-limit refetch;
- account-epoch isolation;
- no accidental real-credit consumption in CI.

---

## 6. Layer B — Monitor-owned Runtime Layer

### 6.1 Definition of ownership

A runtime is Monitor-owned only when Monitor deliberately starts or registers the app-server instance and records a unique runtime instance ID.

A Thread is Monitor-owned only when one of these is true:

- Monitor created it through the owned runtime; or
- Monitor previously created it and resumes it through the same owned-runtime lifecycle using a persisted ownership record.

The ownership record must include source ID, runtime instance ID, Thread ID, creation provenance, account epoch, and lifecycle epoch.

Seeing a Desktop Thread ID in `thread/list`, `thread/loaded/list`, or `thread/read` never establishes ownership.

### 6.2 Allowed lifecycle operations

Within the owned-runtime boundary, `thread/start`, Turn start, interruption, and resuming an already Monitor-owned Thread are lifecycle operations, not observer workarounds.

Hard prohibition:

```text
Desktop-discovered Thread
→ thread/resume
→ claim Monitor ownership or live observation
```

This path is never allowed.

### 6.3 Full realtime contract

The owned-runtime Adapter may advertise “full realtime” only when all of these are validated together:

- correlated Thread/Turn/Item identities;
- `THINKING` and `WORKING` from authoritative lifecycle events;
- current activity from Item events;
- approval request and resolution lifecycle;
- successful, failed, and interrupted terminal outcomes;
- current Session Token usage;
- multi-Thread aggregation;
- reconnect behavior and a defined recovery strategy;
- stale-event rejection by connection/lifecycle epoch.

If any capability is missing, it is downgraded individually. The Adapter must not advertise a composite “full realtime” flag that hides gaps.

### 6.4 Approval ownership and monitoring UI

`WAITING_APPROVAL` may be emitted for a Monitor-owned Turn when an authoritative unresolved approval request exists.

The Menu Bar, Orb, and Quick View remain read-only and never show approve/decline controls. The response path belongs to the owning runtime control surface and is outside these monitoring surfaces. Adding approval controls to Codex Monitor requires a separate product revision and safety review.

### 6.5 Runtime process lifecycle

The old “Quit Monitor never quits Codex” rule remains absolute for Codex Desktop.

For a Monitor-owned runtime:

- quitting the UI must never silently interrupt an active owned Turn;
- if the managed runtime can safely survive UI exit, the supervisor keeps it alive and permits later reattachment;
- if survival cannot be guaranteed, Quit must require explicit confirmation that the owned Turn will be interrupted;
- terminal/idle owned runtimes may be shut down by the supervisor according to a documented cleanup policy;
- Codex Desktop and Desktop-owned app-server processes are never killed.

This lifecycle behavior is a validation requirement, not an assumption.

---

## 7. Layer C — Codex Desktop snapshot/history

### 7.1 Allowed operations

Only stable, read-only operations may be used:

- `thread/loaded/list`
- `thread/list`
- `thread/read(includeTurns: true)`
- account reads from Layer A

Desktop discovery is enabled only after a new probe proves visibility and sanitized correlation on the installed build.

### 7.2 Forbidden operations and inferences

For ordinary Desktop Chats, Hybrid v1 must never:

- use `thread/resume`, `thread/start`, or `thread/fork` to obtain event ownership;
- label snapshot `active` as `WORKING` or `THINKING`;
- infer approval from silence, duration, status, or missing progress;
- infer completion time from polling deltas;
- infer current activity from recent history;
- show Session Token from account Usage;
- present a snapshot as a live subscription;
- claim missed-event recovery;
- use private endpoints, credential extraction, screen/accessibility scraping, or continuous JSONL tailing.

### 7.3 Permitted presentation after validation

The Desktop Adapter may expose:

- discovered Thread title/preview;
- last snapshot status using a clearly labeled raw/coarse representation;
- persisted Turn/history content that the stable read returns and the product has approved for display;
- last refreshed time;
- stale/error state.

It may say:

```text
最后读取状态：active · 18:56
仅快照，不代表当前仍在运行
```

It may not translate that into:

```text
工作中
正在运行命令
等待授权
```

### 7.4 Refresh semantics

Desktop snapshot refresh is bounded and explicitly labeled. It may occur on manual refresh, app launch, wake, or a conservative product-approved interval. It never drives the 0.8-second animation, live duration, notifications, or terminal-retention timers.

---

## 8. Layer D — Future Observer Adapter

The future Adapter is intentionally empty until OpenAI supplies an official, stable, passive subscription/broadcast contract.

To qualify, the contract must prove:

- passive attachment without lifecycle ownership;
- Desktop Thread/Turn/Item correlation;
- approval request/resolution visibility without Monitor responding;
- token and terminal events;
- unsubscribe and reconnect/reconciliation semantics;
- production support and privacy boundaries.

When available, the Adapter will:

1. report its capabilities;
2. emit the same normalized observation envelopes as the owned-runtime Adapter;
3. use `sourceKind = futureObserver`;
4. reuse the State Engine, presentation models, Usage/account stores, and SQLite schema.

No UI, State Engine, Usage, or database redesign should be required. Only the Adapter and version-specific transport/decoder are added, followed by capability validation.

---

## 9. Transport architecture

### 9.1 Adapter boundaries

Transport is split into four responsibilities:

| Component | Responsibility |
|---|---|
| Account Adapter | Account/rate-limit/Usage/reset-credit snapshots and supported account notifications. |
| Monitor-owned Runtime Adapter | Own runtime lifecycle and emit correlated live observations. |
| Desktop Snapshot Adapter | Perform stable read-only discovery/history; never emit live task events. |
| Future Observer Adapter | Reserved official passive live source. |

Transport components decode protocol data but do not format UI, reduce state, or write SQLite directly.

### 9.2 Shared normalized output

All Adapters output only:

- capability snapshots and changes;
- connection/source health;
- account snapshots;
- runtime observation envelopes;
- snapshot/history records;
- sanitized diagnostics.

Raw JSON-RPC types remain inside the Adapter.

### 9.3 Reconnect is per Adapter

There is no single global reconnect result.

- Account reconnect refreshes account/limits/Usage.
- Owned-runtime reconnect restores only owned source state using its validated recovery contract.
- Desktop reconnect repeats read-only discovery/snapshots and remains snapshot-only.
- Future observer reconnect follows its official subscription/replay contract.

Successful account refresh must not turn a runtime source green or mark it idle.

---

## 10. Domain architecture

### 10.1 Separate domain concepts

The Domain must keep these distinct:

- `AccountAvailability`
- `RuntimeSourceAvailability`
- `ObservationMode`
- `RuntimeState`
- `SnapshotSummary`
- `CapabilitySnapshot`
- `Freshness`

`DISCONNECTED`, `PAUSED`, and “realtime unsupported” are not interchangeable.

### 10.2 Runtime state eligibility

The existing runtime states remain valid semantics, but a source can enter them only when its capabilities authorize the required evidence.

| State | Minimum required evidence |
|---|---|
| `IDLE` | Live lifecycle source proves no active Turn after reconciliation. |
| `THINKING` | Live Turn plus reasoning/generic active evidence. |
| `WORKING` | Live correlated work Item evidence. |
| `WAITING_APPROVAL` | Live authoritative unresolved approval request. |
| `COMPLETED` | Live authoritative successful terminal outcome. |
| `INTERRUPTED` | Live authoritative interrupted outcome. |
| `FAILED` | Live authoritative failed outcome. |
| `SYSTEM_ERROR` | Authoritative source/system error for that runtime. |
| `DISCONNECTED` | A configured live runtime source lost connection. |
| `PAUSED` | User paused an otherwise capable live source. |

If no live-capable source exists, the global presentation is `runtimeUnavailable`, not `IDLE` and not `DISCONNECTED`.

### 10.3 Desktop snapshots bypass live reduction

Desktop snapshot/history records are stored and presented through `SnapshotSummary`. They never enter the live event reducer and never participate in realtime global priority.

### 10.4 Capability loss

If an Adapter loses or withdraws a capability:

- clear derived live activity that depended on it;
- clear pending approval presentation if approval authority is gone;
- hide Session Token if correlation authority is gone;
- retain the last fact only as explicitly stale history;
- recompute global presentation atomically;
- never keep an old live state breathing.

---

## 11. State Engine and aggregation

### 11.1 Live aggregation scope

Global runtime aggregation considers only sources with `liveTurnLifecycle = liveAuthoritative`.

Within those sources, the frozen priority remains:

```text
SYSTEM_ERROR / FAILED / INTERRUPTED
> WAITING_APPROVAL
> WORKING / THINKING
> COMPLETED
> IDLE
> DISCONNECTED
```

Desktop snapshot rows are excluded even if their last read status is `active`.

### 11.2 Frozen timing retained with scope

- `COMPLETED`: constant green for 5 seconds.
- `FAILED` / `INTERRUPTED` / `SYSTEM_ERROR`: constant red for 15 seconds.
- `THINKING` / `WORKING`: approximately 0.8-second brightness-only breathing.
- `WAITING_APPROVAL`: approximately 0.8-second yellow brightness-only breathing.

These rules apply only to an eligible live source. Snapshot refreshes never start these timers or animations.

### 11.3 Current activity

Current activity is emitted only from authoritative Item lifecycle data. One-line sanitization, truncation, and hidden-reasoning rules remain unchanged.

### 11.4 Session Token

Session Token is shown only when all three are true:

- the source advertises authoritative Session Token usage;
- the update correlates to the selected Thread;
- the update is current for the active lifecycle epoch.

Account Usage is never substituted.

### 11.5 `WAITING_APPROVAL`

Keep `WAITING_APPROVAL` in the state enum and all future-compatible presentation models.

Enable it only when the source capability is `liveAuthoritative` for approval request and resolution. It is enabled for a validated Monitor-owned runtime and a future validated observer. It is permanently disabled for the current Desktop Snapshot Adapter.

The approval notification setting is visible/enabled only when at least one configured source supports this capability; otherwise it is hidden or shown disabled with an explanation.

---

## 12. Honest UI degradation

### 12.1 Source selection rule

When one or more Monitor-owned live Turns exist, compact runtime surfaces show and aggregate only those managed Turns. They must label the scope as “Monitor 管理的任务” in Quick View/Menu popup/accessibility text.

Ordinary Desktop Chats never silently join that aggregation.

### 12.2 Floating Orb in Desktop-only mode

When there is no live-capable runtime source:

- ring: static system gray/neutral;
- no breathing, yellow, red, or green runtime claim;
- center: fresh authoritative account quota percentage when available, otherwise `--`;
- quota staleness is exposed in Quick View/Menu popup;
- VoiceOver: “Codex Desktop 实时状态不可用，剩余额度 42%” or the corresponding unavailable message.

A fresh account quota may coexist with a gray ring. The ring means runtime observability, not account connectivity.

### 12.3 Quick View in Desktop-only mode

Replace the old live layout with:

```text
Codex Desktop                     18:56
○ 仅快照 · 实时状态不可用

最近发现的对话标题（仅在 discovery 已验证时）
最后读取状态：active · 18:55
不代表当前仍在运行

账户额度剩余 42% · 更新于 18:56
```

Omit:

- `工作中` / `思考中` / `等待授权`;
- current activity;
- running duration;
- Session Token;
- completion/failure retention;
- approval and completion notifications.

If Desktop discovery is not validated or fails, omit the Thread rows and say “Desktop 对话发现不可用.”

### 12.4 Menu Bar capsule in Desktop-only mode

- retain the B capsule and white outline;
- all three dots remain static gray/inactive;
- do not use all-green `IDLE`;
- do not animate;
- accessibility text explicitly says Desktop realtime state is unavailable;
- the popup, not dot color, distinguishes fresh account data, stale account data, and transport failure.

### 12.5 Menu Bar popup in Desktop-only mode

Block 1 becomes:

```text
Codex Desktop
实时任务状态不可用
仅显示稳定协议快照 · 更新于 18:56
```

If validated, it may show a recent Thread snapshot with the same non-live disclaimer.

Block 2 retains capability-supported account, plan, quota, Usage/reset-credit summary, and freshness.

Block 3 retains Usage, Settings, Show/Hide Floating Window, and Quit. Refresh requests account snapshots and any validated Desktop read-only snapshots; it does not subscribe or resume.

### 12.6 Mixed mode

If Monitor-owned runtime and Desktop snapshot data both exist:

- Menu Bar/Orb live state represents Monitor-owned runtime only;
- Quick View identifies the managed Thread/source;
- Desktop snapshot history remains accessible only in explicitly labeled non-live content;
- account quota remains shared Account Layer data and is not attributed to a specific Thread unless the protocol proves that scope.

---

## 13. SQLite and repositories

### 13.1 Keep the existing storage principles

Retain SQLite, WAL, migrations, serialized writes, permanent Usage history, credential prohibition, AppStorage for preferences, account/connection epochs, immediate cached rendering, and migration-failure preservation.

### 13.2 Make provenance first-class now

Before storing new Thread/runtime data, the schema must support:

- runtime sources and source kinds;
- Adapter identity/version;
- capability snapshots and their effective times;
- observation mode and authority;
- namespaced Thread/Turn identities;
- runtime ownership provenance;
- snapshot refresh time and staleness;
- connection/lifecycle epochs.

Existing `threads`, `turns`, `thread_usage`, and `monitor_events` records require source linkage. Desktop snapshot records and live owned-runtime records must be distinguishable by query, not by inference.

### 13.3 Storage rules by source

| Data | Storage rule |
|---|---|
| Account/Usage/rate-limit/reset-credit snapshots | Source-independent account tables with capability/freshness metadata. |
| Owned runtime Thread/Turn/token | May use live Thread/Turn tables with source and ownership linkage. |
| Desktop snapshot/history | Store only as snapshot/history with observed time; do not synthesize live Turns or timers. |
| Future observer data | Reuse live Thread/Turn tables with `futureObserver` source kind. |

This is what prevents a future observer API from requiring a SQLite rewrite.

### 13.4 Repository contracts

Repositories expose domain facts plus provenance/capability. They do not promise a field merely because some Adapter might support it.

Presentation queries ask for:

- current live runtime projection;
- Desktop snapshot summary;
- account/quota/Usage projection;
- capability availability and reason;
- last updated/stale state.

---

## 14. Audit of specifications 04–11

### 14.1 FROZEN rules retained unchanged

These remain valid in all modes unless explicitly scoped below:

- no Hover information behavior;
- Quick View is read-only and has no approval controls or pointer triangle;
- B · Balanced Menu Bar capsule and retained white outline;
- default Orb 90 pt, proportional ring/content scaling, synchronized direct resize and native Slider;
- ring color represents runtime state; center value represents authoritative quota;
- minimum remaining percentage across authoritative dynamic quota windows;
- low quota never recolors the runtime ring;
- native SwiftUI + AppKit window architecture;
- real `NSWindow` traffic lights, native Toggles/Slider/Picker/NSMenu;
- native Liquid Glass only on appropriate floating/custom surfaces;
- Usage and Settings remain restrained content windows;
- Usage section order and 2 × 2 metrics structure;
- 30 local calendar days including zero-use days;
- authoritative cost only; otherwise `$--`;
- no credential storage, private backend, scraping, or JSONL tailing as primary truth;
- account/quota/token/cost concepts remain separate;
- SQLite migration safety, account epochs, connection epochs, and cache/staleness principles;
- Menu/Usage/Settings single-instance and window-lifecycle behavior;
- Monitor quitting never terminates Codex Desktop;
- accessibility, Reduce Motion, Reduce Transparency, Light/Dark, and multi-display placement rules;
- no 0.5-second data polling tied to animation.

### 14.2 FROZEN semantics retained but capability-scoped

The following semantics are unchanged, but only for a validated live source:

- `THINKING`, `WORKING`, `WAITING_APPROVAL`, `COMPLETED`, `FAILED`, `INTERRUPTED`, `SYSTEM_ERROR`;
- global priority order;
- green/yellow/red dot and Orb mapping;
- 0.8-second brightness-only breathing;
- 5-second completion retention;
- 15-second red terminal retention;
- current activity selection/sanitization;
- Session Token display;
- approval/completion notifications;
- multi-Thread priority aggregation;
- state reconstruction after reconnect.

### 14.3 Rules that must change because of P0

- “all Codex Desktop Threads participate in realtime state” becomes “only live-capable sources participate.”
- “connected + no active Turn = IDLE” becomes source-specific; account connectivity alone never produces `IDLE`.
- “`thread.status = active` → THINKING fallback” is prohibited for Desktop snapshots.
- `thread/loaded/list` is no longer treated as enough to reconstruct Desktop runtime state.
- Desktop reconnect becomes snapshot refresh, not event recovery.
- Desktop current activity, duration, terminal retention, Session Token, approval state, and notifications are removed.
- `WAITING_APPROVAL` is no longer globally enabled.
- the approval notification Setting is capability-gated.
- Quick View’s full live layout is no longer universal.
- all-green Menu Bar/Orb `IDLE` is no longer shown in Desktop-only snapshot mode.
- “Quit Monitor never affects any Codex runtime” is split: absolute for Desktop; owned-runtime exit follows the explicit safe lifecycle rule in §6.5.
- the old single `CodexConnectionActor` assumption becomes a set of independent Adapters and source health states.
- old `ThreadRuntimeState` and database records require source/provenance/capability fields.
- P0 fixtures and acceptance tests can no longer imply Desktop live events that were not captured.
- old full-v1 Definition of Done is retired.

### 14.4 Hybrid v1 features limited to Monitor-owned runtime

- live `IDLE` / `THINKING` / `WORKING`;
- current activity;
- live duration;
- `WAITING_APPROVAL` and approval notification;
- completion/failure/interruption/system-error projection and timers;
- Session Token;
- live multi-Thread aggregation;
- task-complete notification;
- lossless event ordering/reconciliation claims;
- lifecycle operations such as start/resume/interrupt for owned Threads.

The same features may later apply to a validated Future Observer Adapter without changing their semantics.

### 14.5 Per-document disposition

| Spec | Disposition |
|---|---|
| 04 State Engine | **Major revision.** Keep state semantics/timing; replace universal Desktop reducer with capability/source eligibility. |
| 05 Account/Usage | **Partial revision.** Keep normalized models and honesty rules; mark current evidence partial and mutation/account-switch features gated. Desktop Session Token sections become owned/future-only. |
| 06 Database/Data Layer | **Major architecture revision.** Keep SQLite/repository separation; add sources, capabilities, provenance, observation mode, and ownership. Replace single transport actor. |
| 07 macOS Architecture | **Minor structural, major presentation-state revision.** Native shell remains; AppEnvironment receives Adapter registry/source coordinator; compact surfaces gain snapshot-only mode. |
| 08 Design System | **Minor visual revision.** Keep frozen design constants; add neutral snapshot-only variants and remove Desktop-only yellow/green/red claims. |
| 09 User Flows | **Major flow revision.** Split Desktop snapshot, owned runtime, mixed mode, and capability-loss/recovery flows. |
| 10 P0 Plan | **Retired as execution plan.** Preserve evidence/safety principles; replace with Hybrid capability validation gates. |
| 11 Master PRD | **Major product revision.** Core definition, scope, state availability, Definition of Done, architecture, fixtures, and build order must point to this document. |

---

## 15. Replacement validation gates

No production implementation begins until a new bounded Hybrid validation phase reports these gates separately.

### AR-P0-A — Account semantics

Validate field-level account, rate-limit, Usage, reset-credit read capabilities; stable local account discriminator; timezone/null behavior; and sparse update handling.

### AR-P0-B — Monitor-owned runtime

Using only Monitor-created runtime/Thread/Turn identities, prove full realtime lifecycle, current activity, approval request/resolution, Session Token, terminal outcomes, multi-Thread correlation, reconnect, and safe runtime shutdown/reattachment behavior.

### AR-P0-C — Desktop read-only snapshot

Run `thread/loaded/list`, complete-source-kind `thread/list`, and before/after `thread/read(includeTurns: true)` without `thread/resume`. Retain privacy-safe counts/correlation digests and document exactly what can be discovered.

Failure of AR-P0-C removes Desktop Thread snapshot content; it does not block Account Layer or a passing owned runtime.

### AR-P0-D — Transport support decision

Record the production support boundary of the selected app-server transport. Experimental/unsupported transport maturity must be an explicit release risk and release gate, not hidden by stable message names.

### AR-P0-E — Reset mutation, optional and explicit

Run only with separate user authorization to consume a real credit. Until then, keep consume disabled and validate with mocks only.

---

## 16. Old Phase 1–11 disposition

The old execution-pack prompts for Phase 1–11 must not be run as written.

| Old Phase | Required change |
|---|---|
| 1 Headless Transport | **Replace.** Build Adapter registry, Account Adapter, owned-runtime Adapter, Desktop snapshot Adapter, and future-observer seam; remove passive Desktop subscription goal. |
| 2 Domain/State Engine | **Replace.** Add source scope, capability eligibility, `runtimeUnavailable`, snapshot bypass, and atomic capability loss. Keep live state semantics/timers. |
| 3 Account/Quota/Usage/Reset | **Modify.** Implement field-level capabilities; keep cost/usage honesty; keep reset consume disabled until mutation validation. |
| 4 SQLite/Repositories | **Modify before schema freeze.** Add source/provenance/capability/ownership columns/tables and snapshot/live separation. |
| 5 AppKit Utility Shell | **Modify.** Keep native windows/controllers; accept mode-aware presentation and independent source health. |
| 6 Functional UI | **Replace acceptance scope.** Implement owned-live, Desktop-only, mixed, unavailable, stale, and capability-loss projections. |
| 7 Design Fidelity | **Modify.** Preserve visual constants; visually validate neutral snapshot-only states and source labels. |
| 8 System Integrations | **Modify.** Capability-gate notifications; reconnect/wake each Adapter independently; never notify for Desktop inferred states. |
| 9 QA | **Replace matrix.** Test by capability/source mode, not only by state. Include forbidden-inference tests. |
| 10 RC Audit | **Modify.** Audit product claims, Adapter provenance, transport maturity, Desktop non-observation, and owned-runtime lifecycle safety. |
| 11 RC Fixes | **Modify.** Fix only against revised audit; packaging must disclose supported modes/capabilities. |

---

## 17. New development Phase order and model allocation

This Architecture Revision is the new prerequisite. Each phase ends with a report and stops.

| New Phase | Scope / exit gate | Primary model | Review/support |
|---|---|---|---|
| AR1 | Architecture/spec revision only; produce this document and report | **Sol / High** | — |
| AR-P0 | Build/run disposable Hybrid probes for account, owned runtime, Desktop snapshots, and transport maturity; no production modules | **Terra / High** | **Sol / High** GO/PARTIAL/NO-GO per capability |
| H1 | Capability contracts, Adapter registry, source/provenance models, sanitized fixtures | **Terra / High** | **Sol / High** architecture review; Luna only fixture normalization |
| H2 | Transport Adapters and owned-runtime supervisor; future Adapter stub has no fake data | **Terra / High** | **Sol / High** for lifecycle/concurrency/security |
| H3 | Capability-driven Domain/State Engine and forbidden-inference tests | **Terra / High** | **Sol / High** semantics review; **Luna / Medium** bounded fixture tests |
| H4 | Account/rate-limit/Usage/reset-credit read adapters; mutation remains gated | **Terra / High** | **Sol / High** account isolation/reset safety; Luna formatter tests |
| H5 | SQLite migrations/repositories with source/capability/provenance schema | **Terra / Medium**, High for migrations | **Luna / Medium** CRUD/zero-fill tests; Sol only if architecture changes |
| H6 | AppKit utility shell wired to immutable capability-driven presentation models | **Terra / High** | **Sol / High** native lifecycle review |
| H7 | Functional UI for owned-live, Desktop-only, mixed, stale, and unsupported modes | **Terra / Medium** | **Luna / Medium** localization/repetitive UI tests; Terra High review |
| H8 | Native Liquid Glass and design fidelity, including neutral snapshot-only variants | **Terra / High** | **Sol / High** visual/system review |
| H9 | Notifications, Launch at Login, Open Codex, sleep/wake, accessibility, display restoration | **Terra / Medium** | **Luna / Medium** accessibility matrix; Terra High review |
| H10 | Full capability/source regression, performance, migrations, packaging rehearsal | **Luna / Medium** executes bounded matrix; **Terra / Medium/High** fixes | Sol only for architecture/product escalation |
| H11 | Release candidate truth/safety/design audit, targeted fixes, final sign-off | **Sol / High** audit → **Terra / Medium/High** fixes | **Sol / High** final sign-off |

Model rules remain:

- Sol decides architecture, product degradation, protocol ambiguity, and release gates.
- Terra implements and debugs production modules.
- Luna receives only exact, bounded, mechanical test/fixture/localization work and never changes architecture or state semantics.

---

## 18. Hybrid v1 Definition of Done

Hybrid v1 is complete only when:

- Account fields are shown only to validated field-level capability and freshness.
- Owned-runtime full realtime gates pass or unsupported sub-capabilities degrade explicitly.
- Desktop mode never claims live Working, Thinking, Approval, current activity, Session Token, terminal timing, or recovery.
- No Desktop Thread is resumed/started/forked to manufacture observation.
- Desktop snapshots, if shipped, are validated and labeled with last refresh/non-live semantics.
- `WAITING_APPROVAL` activates only for an authoritative-capable source.
- Future Observer Adapter can be added without rewriting UI contracts, State Engine semantics, Usage/account stores, or the source-aware SQLite schema.
- all original privacy, cost, quota, native-UI, accessibility, and persistence safety rules pass.
- release notes disclose the difference between Monitor-owned realtime and Desktop snapshot-only behavior.

---

## 19. Stop condition

Architecture Revision 1 ends with this specification and `evidence/PHASE_AR1_REPORT.md`.

Do not execute old Phase 1. Do not write production code. Do not modify UI. Do not run `thread/resume` or any further observer workaround. The next authorized activity, if separately requested, is the disposable AR-P0 Hybrid capability validation plan/execution.
