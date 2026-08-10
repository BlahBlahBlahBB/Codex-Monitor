# H1 Adapter Contracts

> H1 contract-only registry. Nothing in this document opens a connection, starts a runtime, invokes a mutation, or enables a product surface.

## 1. Registry boundary

```text
AdapterRegistry
├── AccountAdapter
├── MonitorOwnedRuntimeAdapter
├── DesktopSnapshotAdapter
└── FutureObserverAdapter (empty)
```

An Adapter translates only its approved source protocol into normalized contract outputs. It must not format UI, reduce runtime state, write SQLite directly, or reclassify records from another source. Its output set is:

```text
CapabilitySnapshot / capability change
SourceHealth
AccountSnapshot
RuntimeObservationEnvelope
SnapshotSummary / snapshot-history record
SanitizedDiagnostic
```

Raw JSON-RPC messages, transport details, and private payload fields terminate at the Adapter boundary.

## 2. Common Adapter contract

```text
AdapterDescriptor = {
  adapterID: stable implementation identifier,
  adapterVersion: implementation version,
  sourceKind: account | monitorOwnedRuntime | desktopSnapshot | futureObserver,
  sourceID: opaque source namespace,
  capabilitySnapshot: map<CapabilityName, CapabilityState>,
  evidenceMetadata: EvidenceMetadata
}

AdapterOutput = {
  provenance: Provenance,
  payload: one normalized output type,
  capability: CapabilityName,
  diagnostics: sanitized optional summary
}
```

`SourceHealth` is source-local and cannot establish a task state. `AdapterOutput` is rejected when its `sourceKind`, namespace, required epoch, or capability state does not match the registry descriptor.

## 3. Account Adapter

| Contract item | H1 definition |
|---|---|
| Source | `sourceKind = account`; a source ID is observation-scoped, not a stable account identifier. |
| Allowed normalized outputs | `AccountSnapshot`, rate-limit full snapshot fact, Usage-presence snapshot fact, reset-credit-count snapshot fact, source health, sanitized diagnostic. |
| Observation mode | `snapshot` only. |
| Required capabilities | Only `snapshot` capability entries from `H1_CAPABILITY_BASELINE.md` may authorize output. |
| Field handling | Every returned field is optional and freshness-scoped. Missing is `nil`, never zero, empty, or copied from a prior account. |
| Rate-limit notification rule | An update notification schedules/requests a full refetch in a later transport phase; it never sparse-merges data. |
| Cost rule | `costUSD = nil` unless a future capability promotion supplies retained authoritative evidence. |
| Prohibited | Stable-key claim, account switching, authoritative-cost calculation, 30-day timezone semantics, reset-credit consume. |

Account health/connection and a fresh quota are independent from `RuntimeSourceAvailability`; neither permits `IDLE`, an active state, ring color, animation, Session Token, or current activity.

## 4. Monitor-owned Runtime Adapter

### 4.1 Ownership precondition

The Adapter accepts a live observation only into the *owned* namespace when an ownership record exists for the same source and lifecycle:

```text
OwnershipRecord = {
  sourceID,
  runtimeInstanceID,
  namespacedThreadID,
  creationProvenance,
  accountEpoch: optional,
  lifecycleEpoch
}
```

At H1, an ownership record is a contract field, not evidence that safe lifecycle ownership, reattachment, or exact event routing is validated. Desktop-discovered identities can never satisfy ownership by being resumed, started, or forked.

### 4.2 Normalized envelope

```text
RuntimeObservationEnvelope = {
  provenance: Provenance(
    sourceKind = monitorOwnedRuntime,
    observationMode = live,
    authority = partial,
    runtimeInstanceID = required,
    connectionEpoch = required,
    lifecycleEpoch = required
  ),
  kind: RuntimeObservationKind,
  threadID: optional NamespacedID,
  turnID: optional NamespacedID,
  itemID: optional NamespacedID,
  payload: shape limited to the kind below
}
```

| `RuntimeObservationKind` | H1 retained shape | Explicit non-claim |
|---|---|---|
| `threadStarted` | Thread identity when supplied. | No ownership promotion merely from receipt. |
| `threadStatusChanged` | Thread identity plus opaque status value when supplied. | No `active` → live-state mapping. |
| `turnStarted` | Thread/Turn identities when supplied. | No complete lifecycle/reducer claim. |
| `itemStarted` | Item identity and one of `reasoning`, `commandExecution`, `agentMessage`, `userMessage`. | No current activity text, hidden reasoning, or state projection. |
| `itemCompleted` | Item identity/type and completion fact when supplied. | No item ordering/recovery claim. |
| `turnCompletedSuccess` | Success completion fact. | No failed/interrupted support; no H1 terminal display. |
| `threadTokenUsageUpdated` | Token-update shape presence. | No selected-Thread correlation, total/delta semantics, or user-visible Session Token. |

There is no `fullRealtime` field, no approval envelope, no failed/interrupted real projection envelope, and no reconnect/reconstruction output contract. A later phase may add individually authorized kinds only after retained evidence promotes their capability.

### 4.3 Epoch rule

The consumer must reject an envelope whose source ID, runtime instance ID, connection epoch, lifecycle epoch, or supplied namespaced parent identity is incompatible with its ownership record. H1 defines this rejection rule but does not implement a reconstruction/reconnect mechanism.

## 5. Desktop Snapshot Adapter

| Contract item | H1 definition |
|---|---|
| Source | `sourceKind = desktopSnapshot`, its own namespace. |
| Allowed inputs when later authorized | Stable read-only `thread/loaded/list`, `thread/list`, and `thread/read(includeTurns: true)` only. |
| Allowed output | `SnapshotSummary`, explicitly labeled history records, source health, sanitized diagnostics. |
| Observation mode | Always `snapshot`. |
| Source classification | `unclassified` or `unvalidated` at H1. A valid method response is not a classified ordinary Desktop Chat. |
| Raw status | Opaque/coarse snapshot fact only. |
| Reducer boundary | `SnapshotSummary` never enters a live runtime reducer, runtime aggregation, animations, durations, terminal retention, notification, or recovery path. |
| Product rows | Disabled pending positive classification and privacy-safe correlation. |
| Prohibited calls | No `thread/resume`, `thread/start`, or `thread/fork` to manufacture observation. |

The Adapter cannot emit `THINKING`, `WORKING`, `WAITING_APPROVAL`, `COMPLETED`, `FAILED`, `INTERRUPTED`, current activity, Session Token, approval, completion notification, or a claimed Desktop live connection state.

## 6. Future Observer Adapter

```text
FutureObserverAdapter = {
  descriptor: registered,
  capabilitySnapshot: all unsupported,
  outputs: []
}
```

This is an intentional empty seam, not a simulator. It does not produce a placeholder source row, pseudo connection state, sample Thread, default live observation, or synthetic fixture data. Future implementation requires an official passive subscription/broadcast contract and separate capability validation.

## 7. Adapter invariants and contract-test hooks

1. Each output has exactly one producing source namespace and capability.
2. Account outputs cannot enter the runtime observation stream.
3. Desktop outputs cannot enter the live reduction stream.
4. A fixture uses the same structural contract as an Adapter output but has `fixture` evidence provenance and never changes the Adapter descriptor's state.
5. Future Observer's output count remains zero.
6. Capability downgrade clears any later-derived fact; it cannot retain a live visual state as if still authorized.
7. A raw identifier cannot cross an Adapter boundary without its source namespace.

These hooks correspond to the H1 test matrix in `H1_CAPABILITY_BASELINE.md`; they are not executable code in this documentation-only repository.
