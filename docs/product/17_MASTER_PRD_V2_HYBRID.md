# Codex Monitor — Master PRD v2.0 Hybrid

> **MASTER SOURCE OF TRUTH**
>
> Platform: macOS
> Product architecture: Capability-driven Hybrid v1
> UI stack: SwiftUI + AppKit
> Current implementation authorization: **CONDITIONAL GO — H1 only**
> Current release maturity: **INTERNAL / DEVELOPER ONLY**
> Visual reference: `../design/APPROVED_VISUAL_REFERENCE.html`
> Architecture baseline: `../architecture/14_ARCHITECTURE_REVISION_HYBRID_V1.md`
> Capability decision baseline: `../architecture/evidence/FINAL_AR_P0_REPORT.md`

---

## 1. Product Definition

Codex Monitor is a native macOS utility with:

```text
Menu Bar status capsule
Menu Bar popup
Floating Orb
single-click read-only Quick View
native Orb right-click menu
Usage window
Settings window
```

The product is no longer defined as a universal passive observer of every Codex Desktop Chat.

Hybrid v1 has four explicit source layers:

```text
A. Account Layer
B. Monitor-owned Runtime Layer
C. Codex Desktop Snapshot Layer
D. Future Observer Adapter
```

Every visible product claim must be authorized by the capability state of the source that produced it.

---

## 2. Source Layers

### A — Account Layer

Purpose:

```text
account identity fields
plan/auth mode where returned
rate-limit snapshots
quota remaining
Usage summary/daily buckets where semantically validated
reset-credit count/details where returned
```

Account connectivity never implies runtime observability.

Quota never implies task state.

Usage never substitutes for current Session Token.

### B — Monitor-owned Runtime

A runtime is Monitor-owned only when Monitor intentionally starts/registers it and records provenance.

A Thread is Monitor-owned only if Monitor created it, or it was previously Monitor-created and is resumed within the same owned lifecycle.

Only this layer may target complete realtime state in Hybrid v1.

### C — Codex Desktop Snapshot

Ordinary Desktop Chats are read-only snapshot/history sources only after explicit source classification validation.

This layer must never emit:

```text
THINKING
WORKING
WAITING_APPROVAL
COMPLETED retention
FAILED retention
INTERRUPTED retention
current activity
live duration
Session Token
approval/completion notifications
live reconnect/recovery claims
```

Desktop status fields remain raw/coarse snapshot facts with timestamps and disclaimers.

### D — Future Observer Adapter

Reserved for a future official passive Desktop subscription/broadcast contract.

It emits no placeholder/fake data today.

Its purpose is to let a future observer source reuse the same:

```text
normalized observations
State Engine semantics
presentation models
Usage/account stores
SQLite provenance model
```

without rewriting the product.

---

## 3. Capability Model

Every Adapter exposes granular capability states:

```text
unsupported
unvalidated
snapshot
liveAuthoritative
mutationValidated
```

There is no composite `fullRealtime = true` shortcut.

Schema presence is not capability proof.

Event-name presence is not behavioral proof.

Mock fixtures do not promote a real Adapter capability.

Every observation carries at least:

```text
sourceID
sourceKind
adapterID / adapter version
runtimeInstanceID where applicable
account epoch
connection epoch
lifecycle epoch
Thread / Turn / Item identities where supplied
observation mode
authority
observedAt
freshness/staleness
capability authorizing the observation
```

IDs are namespaced by source.

---

## 4. Current Authorized Capability Baseline

### Account

Authorized in H1 as snapshot contracts only for actually observed runtime shapes.

Must remain optional/freshness-scoped.

Not yet authorized:

```text
stable account key
account switching
authoritative cost
sparse rate-limit merge
timezone-sensitive 30-day chart semantics
reset-credit detail semantics
reset mutation
```

Until sparse update semantics are proved:

```text
account/rateLimits/updated
→ trigger full account/rateLimits/read refetch
```

### Monitor-owned Runtime

Observed evidence permits H1 to model normalized envelopes for:

```text
thread started
thread status changed
turn started
item started
item completed
thread tokenUsage updated shape
turn completed success
reasoning / commandExecution / agentMessage / userMessage item types
```

But the following remain gated:

```text
WAITING_APPROVAL
approval notification
user-visible Session Token
live multi-Thread aggregation
FAILED real projection
INTERRUPTED real projection
active reconnect/reconstruction
missed-event recovery
safe owner-UI survival/reattachment
unvalidated current-activity user text
```

### Desktop Snapshot

Desktop Adapter is snapshot-only.

Product-visible ordinary Desktop rows remain disabled until a known ordinary Desktop Chat is positively classified and privacy-safely correlated using read-only calls.

### Transport

Local app-server transport behavior has been demonstrated sufficiently for architecture work.

However the current official maturity boundary remains a release blocker.

Until a later review promotes release maturity:

```text
INTERNAL / DEVELOPER ONLY
```

---

## 5. Frozen UI/Product Constants Retained

The following remain frozen:

```text
no Hover information feature
single-click Quick View
Quick View read-only
no approval controls in Quick View
no pointer triangle
B · Balanced status capsule
white capsule outline retained
default Orb 90 pt
proportional Orb resizing
native Settings size Slider
ring means runtime state
center value means authoritative quota remaining
low quota never recolors runtime ring
native SwiftUI + AppKit
real NSWindow traffic lights
native Toggle / Slider / Picker / NSMenu
native Liquid Glass only where appropriate
Usage/Settings are restrained content windows
Usage section order
2 × 2 Token metrics
authoritative cost only, otherwise $--
no credential storage
no private backend
no scraping
no continuous JSONL primary truth
accessibility / Reduce Motion / Reduce Transparency / Light/Dark
no data polling tied to 0.8 s breathing
```

---

## 6. Live State Semantics — Capability Scoped

These semantics remain unchanged for a validated live source:

```text
IDLE
THINKING
WORKING
WAITING_APPROVAL
COMPLETED
FAILED
INTERRUPTED
SYSTEM_ERROR
DISCONNECTED
PAUSED
```

Priority:

```text
SYSTEM_ERROR / FAILED / INTERRUPTED
>
WAITING_APPROVAL
>
WORKING / THINKING
>
COMPLETED
>
IDLE
>
DISCONNECTED
```

Timing:

```text
THINKING / WORKING:
~0.8 s brightness-only green breathing

WAITING_APPROVAL:
~0.8 s brightness-only yellow breathing

COMPLETED:
constant green 5 s

FAILED / INTERRUPTED / SYSTEM_ERROR:
constant red 15 s
```

These rules can only run when the source has the required authoritative capability.

If no live-capable runtime exists, presentation is `runtimeUnavailable`, not `IDLE`.

---

## 7. Desktop-only Honest Degradation

When no live-capable runtime exists:

### Menu Bar capsule

```text
B capsule retained
white outline retained
all three dots static gray/inactive
no breathing
no all-green IDLE claim
```

### Floating Orb

```text
ring = static neutral/gray
center = fresh authoritative account quota when available, else --
```

Fresh quota may coexist with a gray ring.

### Quick View

Use:

```text
Codex Desktop
○ 仅快照 · 实时状态不可用
...
账户额度剩余 42% · 更新于 ...
```

Omit:

```text
工作中
思考中
等待授权
current activity
running duration
Session Token
completion/failure retention
approval/completion notifications
```

### Menu Bar popup

Block 1 explicitly says realtime task state is unavailable.

Block 2 may show capability-supported account/quota/Usage/reset-credit snapshot information.

Block 3 remains Usage / Settings / Show-Hide Orb / Quit.

---

## 8. Mixed Mode

If Monitor-owned live runtime and Desktop snapshot data coexist:

```text
Menu Bar / Orb live state = Monitor-owned runtime only
Quick View identifies scope as “Monitor 管理的任务”
Desktop data remains explicitly snapshot-only
Account quota remains Account Layer data
```

Desktop snapshot rows never participate in live global priority.

---

## 9. Approval

Keep `WAITING_APPROVAL` in Domain and presentation models.

Enable it only after a source is `liveAuthoritative` for:

```text
approval request
+
authoritative resolution
```

Current H1 baseline:

```text
WAITING_APPROVAL disabled
approval notification disabled
```

Monitoring surfaces never approve/decline.

---

## 10. Session Token

The protocol shape has been seen, but product display remains disabled until retained evidence proves:

```text
per-Thread numeric sequence
Thread correlation
last/total semantics
cumulative vs delta behavior
lifecycle freshness
reconnect continuity
```

Account Usage is never substituted.

---

## 11. Failed / Interrupted

Do not enable real Adapter projection until real runtime captures validate these terminal outcomes.

Fixture/mock support is allowed for domain tests.

Fixtures do not promote real Adapter capability.

---

## 12. Multi-Thread

Do not enable a live multi-Thread product claim until retained evidence proves:

```text
exact Thread → Turn → Item routing
at least two simultaneously active owned Threads
negative crossover assertions
```

An aggregate owned-set mismatch count is insufficient.

---

## 13. Reconnect / Runtime Survival

Do not claim:

```text
active reconstruction
missed-event recovery
owner-UI quit survival
safe reattachment
```

until validated.

For Codex Desktop:

```text
Quit Monitor never terminates Codex Desktop
```

For Monitor-owned runtime, final process lifecycle must be capability-driven and validated before release claims.

---

## 14. Account / Quota / Usage Rules

Retain:

```text
dynamic rate-limit windows
no hard-coded 5 h/week assumption
remaining = clamp(100 - usedPercent)
Orb center = minimum remaining across authoritative current windows
cost = $-- when authoritative cost absent
privacy masking
freshness/staleness
account/connection epochs
```

Until timezone/date-boundary semantics are validated, do not enable a confident “30 local calendar days” account chart claim based only on the current evidence.

The UI structure may be implemented internally, but semantic presentation must remain capability-gated.

---

## 15. Reset Credit

Read:

```text
availableCount snapshot may be modeled when returned
```

Mutation:

```text
disabled
```

until the user separately authorizes a live mutation validation and it proves:

```text
result mapping
idempotency reuse
timeout behavior
mandatory refetch
account-epoch isolation
```

No CI consumes real reset credits.

---

## 16. Persistence

Use SQLite + migrations + WAL.

Provenance is first-class before Thread/runtime schema freezes.

Required source-aware data includes:

```text
runtime_sources
capability_snapshots
adapter identity/version
observation mode
authority
freshness
namespaced Thread/Turn/Item IDs
runtime ownership provenance
snapshot refresh time
account/connection/lifecycle epochs
```

Desktop snapshot/history and live owned-runtime data must be distinguishable by query.

Never infer source from raw IDs.

Never store credentials.

---

## 17. Native macOS Architecture

Retain:

```text
NSStatusItem
NSPopover
NSPanel Floating Orb
NSPanel Quick View
NSWindow Usage
NSWindow Settings
NSMenu context menu
SwiftUI hosted content
Swift Concurrency actors
SMAppService
UNUserNotificationCenter
NSWorkspace
```

The AppEnvironment adds an Adapter registry and independent source coordinators.

There is no single global Codex connection assumption.

---

## 18. Liquid Glass

Production target remains native Apple visual behavior.

Use native Liquid Glass for appropriate floating/custom surfaces such as:

```text
Floating Orb
Quick View
```

Do not turn Usage/Settings into glass-card dashboards.

Use system controls before custom imitation.

The visual reference remains approved, with Hybrid neutral snapshot-only variants added.

---

## 19. Build/Release Status

### Architecture

```text
CONDITIONAL GO
```

### Current authorized phase

```text
H1 only
```

### Release

```text
INTERNAL / DEVELOPER ONLY
```

Do not call the current baseline:

```text
beta ready
public ready
production supported
```

A future release-maturity review must reassess the official transport support boundary and all product claims.

---

## 20. H1 Authorization

H1 may implement only:

```text
granular capability contracts
Adapter registry boundaries
source/provenance models
namespaced identities
observation/authority/freshness models
account snapshot contract shapes
owned-runtime normalized envelope types
Desktop SnapshotSummary types
empty Future Observer Adapter
sanitized fixtures for observed evidence
forbidden-inference tests
evidence metadata
exact transport-decision documentation
```

H1 must not enable any unvalidated product feature.

---

## 21. H1 Forbidden

H1 must not implement/enable:

```text
fullRealtime flag
WAITING_APPROVAL
approval notifications
user-visible Session Token
live multi-Thread aggregation
real FAILED/INTERRUPTED projection
active reconnect/reconstruction
missed-event recovery
owner-UI survival claim
unvalidated current-activity text
product-visible Desktop Chat rows
Desktop live state
Desktop lifecycle workaround
sparse rate-limit merge
stable account key claim
account switching
authoritative cost
timezone-sensitive Usage claim
reset-credit consume
beta/public release positioning
```

---

## 22. Development Order

New sequence:

```text
H1  Capability Contracts / Adapter Registry
H1R Sol architecture review

H2  Transport Adapters / owned-runtime supervisor
H2R Sol lifecycle/concurrency/security review

H3  Capability-driven Domain / State Engine
H3R Sol semantics review

H4  Account / Rate Limit / Usage read adapters
H4R Sol account/data honesty review

H5  SQLite / Repositories / migrations
H5R architecture review only if needed

H6  AppKit utility shell
H6R Sol native lifecycle review

H7  Functional UI for all source/capability modes
H7R Terra High functional review

H8  Native Liquid Glass / design fidelity
H8R Sol visual/system review

H9  System integrations
H9R Terra High review

H10 Full capability/source QA
H10R escalation only as needed

H11 Release-candidate truth/safety/design audit
→ targeted Terra fixes
→ Sol final sign-off
```

Every phase ends with a report and stops.

---

## 23. Model Allocation

```text
Sol High:
architecture, evidence decisions, product degradation, protocol ambiguity,
native/design gates, security/safety, release audit

Terra High:
H1/H2/H3/H4/H6/H8 and complex debugging

Terra Medium:
H5/H7/H9 and normal implementation/bug fixing

Luna Medium:
bounded fixtures, repetitive tests, localization, regression execution
```

Luna never changes architecture or state semantics.

---

## 24. Source-of-Truth Priority

If files conflict:

```text
1. 17_MASTER_PRD_V2_HYBRID.md
2. ../architecture/evidence/FINAL_AR_P0_REPORT.md
3. ../architecture/14_ARCHITECTURE_REVISION_HYBRID_V1.md
4. later Hybrid specialist/execution specification
5. retained non-conflicting rules in ../reference/legacy-v1.2/04–09
6. ../design/APPROVED_VISUAL_REFERENCE.html
7. any retired v1 / old Phase artifact
```

Never use an old Phase prompt to override this document.

---

## 25. Definition of Done — Internal Hybrid Build

An internal Hybrid build is functionally complete only when:

```text
all enabled features are capability-authorized
Desktop mode never invents live state
owned-runtime enabled features have retained evidence
Account fields are optional/freshness-scoped
SQLite preserves source/provenance
native macOS behavior passes
visual frozen constants pass
no credential/private API/scraping violations
all unsupported capabilities degrade honestly
```

This definition is not a public-release authorization.

---

## 26. Final Instruction to Codex

Build only what the active capability baseline authorizes.

When evidence is missing:

```text
gate the capability
```

Do not “complete” the UI by inventing semantics.

Do not use Desktop lifecycle operations to manufacture observation.

Do not promote mocks to real Adapter capability.

Do not begin the next phase until the required review/report explicitly authorizes it.
