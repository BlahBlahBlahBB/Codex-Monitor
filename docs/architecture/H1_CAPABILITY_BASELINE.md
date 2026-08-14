# H1 Capability Baseline

> Phase: H1 — Capability Contracts & Adapter Registry  
> Architecture: **CONDITIONAL GO**  
> Release maturity: **INTERNAL / DEVELOPER ONLY**  
> Scope: contract baseline only; no transport, reducer, persistence, UI, or mutation implementation.

## 1. Authority and non-promotion rule

This baseline is derived from `17_MASTER_PRD_V2_HYBRID.md`, `FINAL_AR_P0_REPORT.md`, and `14_ARCHITECTURE_REVISION_HYBRID_V1.md`. A capability state is an evidence claim, not a decoder, fixture, schema name, or UI preference.

| State | Meaning | Product eligibility |
|---|---|---|
| `unsupported` | No allowed implementation path is evidenced for this Adapter. | Unavailable; do not emit a substitute. |
| `unvalidated` | A possible method or shape exists, but the required behavior is not proved. | Treat as unavailable. |
| `snapshot` | A fact is authoritative only at its declared observation time. | May be shown with freshness/staleness and source scope. |
| `liveAuthoritative` | Correlated push lifecycle behavior is retained and reproducibly proved for that exact source. | May feed a later live reducer only after that phase is authorized. |
| `mutationValidated` | A state change, response mapping, safety and idempotency semantics are proved. | May be considered by a later authorized mutation phase. |

There is deliberately no composite realtime capability or boolean shortcut. A fixture, mock, stable-schema member, event-name presence, or aggregate event count never promotes a real Adapter capability.

## 2. Shared identity, provenance, and freshness contracts

### 2.1 Namespaced identity

Every protocol-provided identifier is an opaque value inside a source namespace. Equality requires both values.

```text
NamespacedID = {
  sourceID: SourceID,
  entityKind: thread | turn | item,
  rawID: opaque non-empty string
}
```

The canonical storage/display key is an escaped serialization of all three fields; raw IDs are never compared across sources. A Desktop Thread ID is never reclassified as a Monitor-owned Thread because its raw value matches.

```text
SourceID = opaque, process-scoped source identifier
SourceKind = account | monitorOwnedRuntime | desktopSnapshot | futureObserver
```

`sourceID` is not a stable account key. An account source may be created per account epoch; it is only an observation scope.

### 2.2 Required observation provenance

All normalized observations and snapshots carry the following contract. Fields marked optional are omitted rather than invented.

| Field | Contract |
|---|---|
| `sourceID`, `sourceKind` | Required source namespace and layer. |
| `adapterID`, `adapterVersion` | Required producing Adapter identity and version. |
| `runtimeInstanceID` | Required for Monitor-owned runtime observations; otherwise absent. |
| `observationMode` | `snapshot` or `live`; it describes the observation, not a global product mode. |
| `authority` | `authoritative`, `partial`, or `unavailable`. |
| `observedAt` | Required source observation time. |
| `freshness` | Required freshness scope described below. |
| `accountEpoch`, `connectionEpoch`, `lifecycleEpoch` | Required when the relevant scope exists; otherwise absent. |
| `threadID`, `turnID`, `itemID` | Namespaced and optional, only when supplied by retained evidence. |
| `capability` | Required granular capability that authorizes this exact fact. |

```text
Freshness = {
  state: fresh | stale | unknown,
  assessedAt: timestamp,
  observedAt: timestamp,
  reason: optional machine-readable reason
}
```

Freshness never creates runtime availability. Stale values remain historical facts, not current live state.

### 2.3 Evidence metadata

All fixtures and capability records include:

```text
evidenceRun              = AR-P0 retained evidence decision
cliVersion               = 0.147.0 (reported by retained evidence)
transportEvidenceLabel   = unresolved in AR-P0: loopback-IP WebSocket or Unix-socket WebSocket
probeOrHarnessVersion    = unavailable; harness/digest was not retained
sanitizerVersion         = unavailable; retained evidence did not record a version
confidence               = bounded contract evidence only
limitations              = required field-specific limitations
```

The H2 candidate transport selected in `H1_TRANSPORT_DECISION.md` is a forward decision, not retroactive evidence that the AR-P0 harness used it.

## 3. Capability registry

### 3.1 Account Adapter

| Capability | State | H1 contract and gate |
|---|---|---|
| account returned fields | `snapshot` | Model only returned optional fields with freshness. |
| plan/auth-mode returned fields | `snapshot` | Optional; no inferred plan or identity. |
| stable local account discriminator | `unvalidated` | No stable-account-key claim. |
| primary rate-limit full snapshot | `snapshot` | Model as optional primary window. |
| secondary rate-limit snapshot | `unvalidated` | May be absent; no required secondary semantics. |
| sparse rate-limit update merge | `unvalidated` | Notification requires a full `account/rateLimits/read` refetch; no merge. |
| Usage response presence | `snapshot` | Preserve only proved optional fields; no timezone-sensitive 30-day claim. |
| authoritative cost | `unsupported` | Preserve `nil`; presentation is `$--`. |
| reset-credit count | `snapshot` | Optional returned count only. |
| reset-credit details semantics | `unvalidated` | No detail meaning or inferred count. |
| reset-credit consume | `unvalidated` | Disabled; no request is made. |
| account switching | `unvalidated` | No product action. |

### 3.2 Monitor-owned Runtime Adapter

| Capability | State | H1 contract and gate |
|---|---|---|
| owned runtime provenance | `unvalidated` | Contract may record self-attested ownership; release claims require reproducible proof. |
| Thread start observation | `unvalidated` | Normalized envelope/fixture only. |
| Thread status change observation | `unvalidated` | Normalized envelope/fixture only; no source-independent state inference. |
| Turn start observation | `unvalidated` | Normalized envelope/fixture only. |
| Item start/completion observation | `unvalidated` | Only retained Item kinds are represented. |
| success turn completion observation | `unvalidated` | Fixture-only contract; no product terminal projection in H1. |
| token-usage update shape | `unvalidated` | No user-visible Session Token and no cumulative/delta assumption. |
| exact Thread → Turn → Item correlation | `unvalidated` | Owned-set membership is insufficient. |
| THINKING / WORKING product reduction | `unvalidated` | H3-gated; no reducer exists in H1. |
| current activity text | `unvalidated` | Hidden/unavailable. |
| approval lifecycle | `unvalidated` | `WAITING_APPROVAL` and notifications disabled. |
| failed / interrupted terminal projection | `unvalidated` | Disabled pending real captures. |
| live multi-Thread aggregation | `unvalidated` | Disabled. |
| reconnect/reconstruction | `unvalidated` | No active recovery or missed-event claim. |
| owner-UI survival/reattachment | `unvalidated` | No safe-survival claim. |

### 3.3 Desktop Snapshot Adapter

| Capability | State | H1 contract and gate |
|---|---|---|
| stable read-only summary/history method availability | `snapshot` | Read shape only; source classification remains separate. |
| ordinary Desktop source classification | `unvalidated` | Product-visible Desktop rows disabled. |
| title/preview/raw status/history availability | `snapshot` | Optional coarse snapshot facts only. |
| Desktop realtime lifecycle | `unsupported` | Never emit live state or feed a live reducer. |
| Desktop approval / `WAITING_APPROVAL` | `unsupported` | Never infer or emit. |
| Desktop Session Token | `unsupported` | Omit. |
| Desktop terminal retention, duration, notifications, recovery | `unsupported` | Never emit or claim. |

### 3.4 Future Observer Adapter

Every product capability is `unsupported` today. The registry slot exists only to preserve a source-neutral boundary. It emits no observations, snapshots, placeholder Thread rows, simulated health, or fake capability data.

## 4. Snapshot-only account contract

The Account Adapter models only runtime shapes retained by the evidence decision. All values are optional and freshness-scoped. Absence remains absence.

```text
AccountSnapshot = {
  provenance: Provenance,
  email: optional string,
  planType: optional string,
  authMode: optional string,
  primaryRateLimit: optional RateLimitWindow,
  secondaryRateLimit: optional RateLimitWindow,
  usage: optional UsagePresence,
  resetCreditCount: optional integer
}

RateLimitWindow = {
  usedPercent: optional number,
  windowDurationMinutes: optional integer,
  resetsAt: optional timestamp,
  reachedType: optional string
}

UsagePresence = {
  summaryAvailable: optional boolean,
  dailyBucketsAvailable: optional boolean,
  inputTokens: optional integer,
  cachedInputTokens: optional integer,
  outputTokens: optional integer,
  reasoningOutputTokens: optional integer,
  totalTokens: optional integer,
  costUSD: nil
}
```

`UsagePresence` is a forward-compatible optional-field shape, not a claim that any token field, bucket date, time-zone meaning, or range semantics were captured. `costUSD` is fixed to `nil` under the current baseline. No sparse merge, account switching, stable key, cost derivation, reset consumption, or 30-day chart semantics are defined here.

## 5. Desktop SnapshotSummary contract

```text
SnapshotSummary = {
  provenance: Provenance(observationMode = snapshot),
  readAt: timestamp,
  rawStatus: optional opaque string,
  titleAvailability: available | unavailable | unknown,
  previewAvailability: available | unavailable | unknown,
  historyAvailability: available | unavailable | unknown,
  sourceClassification: unclassified | unvalidated | validated,
  staleness: Freshness
}
```

At H1, `sourceClassification` is `unvalidated` or `unclassified`; `validated` is not instantiated by any H1 fixture. `rawStatus` is intentionally coarse and is never mapped to `THINKING`, `WORKING`, `IDLE`, terminal status, current activity, duration, approval, or token usage.

## 6. Sanitized fixture catalogue

Fixtures validate domain-contract handling only. They do not implement adapters or promote their capability.

| Fixture ID | Source | Evidence-supported shape | Provenance requirement |
|---|---|---|---|
| `account-snapshot-minimal-v1` | Account | optional returned account/rate-limit/Usage-presence fields | AR-P0 evidence metadata; redacted values; `snapshot`. |
| `owned-thread-started-v1` | Monitor-owned runtime | Thread identity and start envelope | AR-P0 bounded method evidence; `partial`; lifecycle epoch. |
| `owned-thread-status-changed-v1` | Monitor-owned runtime | opaque Thread status change | AR-P0 bounded method evidence; no state mapping. |
| `owned-turn-started-v1` | Monitor-owned runtime | Thread/Turn identities when supplied | AR-P0 bounded method evidence. |
| `owned-item-started-v1` | Monitor-owned runtime | `reasoning`, `commandExecution`, `agentMessage`, or `userMessage` | Item payload omitted/redacted; no activity text. |
| `owned-item-completed-v1` | Monitor-owned runtime | correlated-or-partial completion envelope | Correlation confidence is `partial`. |
| `owned-turn-completed-success-v1` | Monitor-owned runtime | success completion shape | No failed/interrupted representation. |
| `owned-token-usage-shape-v1` | Monitor-owned runtime | token-update shape presence | No user display or total/delta meaning. |
| `desktop-summary-unclassified-v1` | Desktop snapshot | read time, optional raw/coarse status and availability fields | `snapshot`; source classification unvalidated. |
| `future-observer-empty-v1` | Future observer | zero observations and zero snapshots | Explicit no-data assertion. |

Fixture payloads must contain synthetic values or redacted placeholders, the fixture ID, the metadata in §2.3, a source kind, and its exact capability state. They must not use a real e-mail, raw Thread/Turn/Item ID, credential, conversation content, token total, or a value that looks like a live product claim.

## 7. H1 contract-test matrix

This repository has no application target or test runner yet. The H1 tests are deterministic contract assertions to be implemented by the later authorized test target; H1 validates the written baseline and fixture requirements only.

| Test ID | Required assertion |
|---|---|
| `capability-states-are-granular` | Only the five defined states authorize a capability; no composite realtime member exists. |
| `namespaced-identity-is-source-sensitive` | Same raw Thread/Turn/Item ID from two sources is not equal. |
| `provenance-is-required` | Every normalized observation/snapshot has required provenance and its authorizing capability. |
| `account-connectivity-is-not-runtime` | A fresh Account snapshot cannot produce runtime availability or `IDLE`. |
| `fresh-quota-is-not-runtime` | Fresh quota cannot color/animate the runtime ring or establish task state. |
| `desktop-active-is-not-live-state` | Desktop raw `active` cannot become `THINKING` or `WORKING`. |
| `usage-is-not-session-token` | Account Usage never populates a Session Token value. |
| `schema-is-not-reset-mutation` | Method/schema presence does not change reset consume from `unvalidated`. |
| `desktop-bypasses-live-reducer` | A `SnapshotSummary` is rejected by the live observation/reducer input boundary. |
| `fixture-cannot-promote-live-authority` | Fixture/mocks cannot change an Adapter capability to `liveAuthoritative`. |
| `future-observer-has-no-data` | Future Observer emits no observation, snapshot, placeholder Thread, or fake health record. |
| `account-absence-remains-absence` | Missing secondary window/cost/detail fields remain `nil` and are not synthesized. |

## 8. Explicit H1 exclusions

H1 does not implement a transport, protocol decoder, owned-runtime supervisor, live reducer, UI, database, reconnect, mutation, Desktop discovery workflow, notification, or a product-visible row. It does not invoke `thread/resume`, `thread/start`, or `thread/fork` for observation, and it does not make public or beta release claims.
