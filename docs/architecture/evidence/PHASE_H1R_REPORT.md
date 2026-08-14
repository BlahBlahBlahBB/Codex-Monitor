# PHASE_H1R_REPORT

```text
Phase: H1R — H1 Architecture Review
Model: Codex task runtime (H1R allocation requested by the execution pack: GPT-5.6 Sol / High)
Reasoning: High
Date: 2026-08-10
Start commit: none (workspace is not a Git repository)
End commit: none (this review did not initialize Git)
Review type: architecture / contract / phase-gate review only
```

## Final decision

**PASS WITH REQUIRED FIXES — REQUIRE H1F BEFORE H2**

Canonical gate meaning: **PASS WITH REQUIRED FIXES — DO NOT ENTER H2.**

The four H1 Markdown deliverables pass as a bounded **contract specification**. H1 is **not implementation-complete**: there is no local Git repository, Swift application/package target, compilable contract implementation, executable test target, fixture implementation, or executable contract-test result. Master PRD v2 authorizes H1 to implement contract/types/registry/fixtures/tests, not merely describe them. Therefore an H1F / H1.1 **Bootstrap & Contract Implementation** is mandatory before H2.

No capability is promoted by this review. Architecture remains **CONDITIONAL GO** and release maturity remains **INTERNAL / DEVELOPER ONLY**.

## Sources reviewed

Primary sources:

- `../../product/17_MASTER_PRD_V2_HYBRID.md`
- `FINAL_AR_P0_REPORT.md`
- `../14_ARCHITECTURE_REVISION_HYBRID_V1.md`
- `../19_CAPABILITY_BASELINE_AND_GATES.md`
- `../../product/20_HYBRID_PHASE_MODEL_PLAYBOOK.md`
- Historical material; retained only on `codex/github-readiness-audit`: `21_HYBRID_EXECUTION_PACK/01_H1_TERRA_CAPABILITY_CONTRACTS.md`
- Historical material; retained only on `codex/github-readiness-audit`: `21_HYBRID_EXECUTION_PACK/02_H1R_SOL_ARCHITECTURE_REVIEW.md`
- Historical material; retained only on `codex/github-readiness-audit`: `21_HYBRID_EXECUTION_PACK/03_H2_TERRA_TRANSPORT_ADAPTERS.md`
- Historical material; retained only on `codex/github-readiness-audit`: `21_HYBRID_EXECUTION_PACK/91_PHASE_REPORT_TEMPLATE_V2.md`
- Historical material; retained only on `codex/github-readiness-audit`: `21_HYBRID_EXECUTION_PACK/92_HYBRID_STOP_GATES.md`
- Historical material; retained only on `codex/github-readiness-audit`: `21_HYBRID_EXECUTION_PACK/93_MASTER_CHECKLIST_V2.md`
- `../../release/RELEASE_MATURITY_GATES.md`

H1 deliverables reviewed completely:

- `../H1_CAPABILITY_BASELINE.md`
- `../H1_ADAPTER_CONTRACTS.md`
- `../H1_TRANSPORT_DECISION.md`
- `PHASE_H1_REPORT.md`

Current official transport support boundary was checked against the [official OpenAI Codex App Server documentation](https://developers.openai.com/codex/app-server/).

## Repository and implementation evidence

Read-only workspace inspection found:

```text
git rev-parse: fatal — not a Git repository
Git remote: none, because no repository exists
Package.swift: absent
.xcodeproj/project.pbxproj: absent
Swift source files: absent
Sources directory: absent
Tests directory / test plan: absent
Executable contract tests: absent
H1 sanitized fixture files: absent
H1 diff / start and end commits: unavailable
```

`PHASE_H1_REPORT.md` accurately discloses these omissions, but its statement “H1 documentation/contract baseline complete” cannot be upgraded to “H1 implementation complete.” Static Markdown checks are not substitutes for compilation or executable contract tests.

## Blocking findings

### H1R-01 — H1 is specification-complete, not implementation-complete

**Severity: blocking H2 entry.**

Master PRD v2 §20 explicitly authorizes implementation of granular capability contracts, Adapter registry boundaries, source/provenance and namespaced identity models, normalized envelope and `SnapshotSummary` types, an empty Future Observer Adapter, sanitized fixtures, forbidden-inference tests, and evidence metadata. The H1 execution prompt likewise says “实现” and requires capability, namespace, provenance, forbidden-inference, fixture-provenance, and Future Observer tests.

The current files describe these objects and enumerate tests, but do not provide any compilable Swift type or executable assertion. H2 would otherwise be forced to invent foundational types while simultaneously implementing transport, weakening the phase boundary and making transport code the de facto contract definition. H1F must establish and test the contract layer first.

### H1R-02 — `RuntimeObservationEnvelope` needs an explicit product-admission boundary

**Severity: blocking H2 entry.**

The written intent is mostly correct:

- `unvalidated` is defined as unavailable;
- only `liveAuthoritative` may feed a later live reducer;
- the current owned-runtime capabilities remain `unvalidated`;
- a fixture/mock cannot promote real Adapter capability.

However, `../H1_ADAPTER_CONTRACTS.md` currently also:

- lists `RuntimeObservationEnvelope` as a general `AdapterOutput` payload;
- says output is rejected when capability state does not match the descriptor, which still permits a matching `unvalidated` state;
- defines the envelope with `observationMode = live` and `authority = partial`;
- says the Adapter accepts a live observation into the owned namespace when an ownership record exists.

This is not a semantic promotion by itself, but it is not a sufficiently hard output boundary for implementation. A real Adapter must not gain product/live-reducer delivery merely because an envelope can be decoded, normalized, namespaced, or matched to an `unvalidated` descriptor.

H1F must enforce two distinct paths:

```text
decoded/normalized candidate envelope
  ├── evidence/diagnostic/fixture path (may retain unvalidated shape, sanitized)
  └── product live-admission gate
        └── succeeds only for the exact registered source + capability
            whose current state is liveAuthoritative
```

At the current baseline, every real Monitor-owned runtime observation capability is `unvalidated`; therefore the product live-admission result must always be rejection/unavailable and no reducer callback or product event may be produced. `observationMode = live` describes how a candidate was observed; it is not authorization.

### H1R-03 — No executable proof of isolation, zero-data, or forbidden inference

**Severity: blocking H2 entry.**

The written registry separation, Desktop snapshot bypass, Future Observer zero-data rule, namespaced IDs, fixture non-promotion, and forbidden-inference matrix are sound as specification. None is executable. These are architectural safety properties and must be locked before transport introduces real inputs.

### H1R-04 — Repository state is not ready for production-module phase work

**Severity: blocking H2 entry.**

Without a local repository there is no start/end commit, trustworthy phase diff, rollback point, or reviewable code boundary. H1 allowed local `git init`; choosing not to initialize it was acceptable for a documentation-only draft, but it is not acceptable before production module work starts.

## H1R checklist verdict

| Review item | Verdict | Finding |
|---|---|---|
| Composite `fullRealtime` shortcut | **PASS (spec)** | No field/boolean shortcut exists; capabilities remain granular. |
| `unvalidated` treated as enabled | **PASS WITH FIX** | Markdown says unavailable, but executable product-admission enforcement is absent and the envelope boundary needs tightening. |
| Schema presence treated as proof | **PASS (spec)** | Schema/event/fixture presence is explicitly non-promoting; reset mutation remains disabled. |
| Adapter registry isolation | **PASS (spec) / UNPROVED (implementation)** | Account, Monitor-owned Runtime, Desktop Snapshot, and Future Observer are separately modeled; no code/test proves isolation. |
| Source-namespaced IDs | **PASS (spec) / UNPROVED (implementation)** | Identity equality includes source and entity kind; no compiled `NamespacedID` exists. |
| Desktop Snapshot bypasses live reducer | **PASS (spec) / UNPROVED (implementation)** | The prohibition is explicit; executable type/admission rejection is absent. |
| Future Observer zero data | **PASS (spec) / UNPROVED (implementation)** | All capabilities are unsupported and outputs are specified empty; no Adapter implementation or zero-output test exists. |
| Fixture/mock non-promotion | **PASS (spec) / UNPROVED (implementation)** | The rule is explicit; actual sanitized fixtures and immutable/non-promoting registry tests are absent. |
| Forbidden-inference tests | **PASS as matrix / FAIL as tests** | Required assertions are well enumerated, but none is executable. |
| Provenance/evidence metadata | **PASS (spec) / UNPROVED (implementation)** | Required fields include run, CLI, transport label, harness/digest, sanitizer, confidence, and limitations; unavailable historical values are honestly preserved as unavailable. |
| Unique H2 transport and boundaries | **PASS as forward decision** | Unix-socket WebSocket is the sole candidate; lifecycle, permission, privacy, failure, and maturity assumptions are explicit. |
| H1 secretly implemented forbidden capability | **PASS** | No production implementation exists; no capability was promoted. |
| Git/repository readiness | **FAIL** | Workspace is not a Git repository and has no code/test skeleton. |

## Transport decision review

**Unix-socket WebSocket is acceptable as H2's single forward candidate**, subject to H1F completion and a later explicit H2 authorization. Official OpenAI documentation currently lists `--listen unix://` / `unix://PATH` as WebSocket over a Unix socket using the HTTP Upgrade handshake. The same documentation continues to classify the app-server command and WebSocket transport as experimental and unsupported for production workloads. This remains compatible only with the present **INTERNAL / DEVELOPER ONLY** maturity.

`../H1_TRANSPORT_DECISION.md` correctly separates:

```text
forward H2 choice: Unix-socket WebSocket
historical AR-P0 evidence: inconsistent/unresolved between loopback-IP WebSocket and Unix-socket WebSocket
```

The forward choice must never rewrite AR-P0 provenance. H1F must represent these as distinct fields/concepts and test that selecting Unix-socket WebSocket for H2 does not mutate, normalize, or relabel the retained AR-P0 evidence.

No fallback to loopback TCP, private discovery, filesystem scanning, credential extraction, or a Desktop lifecycle observer workaround is authorized.

## Capability gate audit

The Markdown baseline keeps all currently unvalidated or unsupported capability claims gated:

- Account stable discriminator, sparse merge, secondary-window semantics, reset detail semantics, reset consume, account switching, authoritative cost, and timezone-sensitive Usage semantics remain unavailable/disabled.
- Monitor-owned exact correlation, product `THINKING`/`WORKING`, current activity, approval, Session Token, real failed/interrupted projection, multi-Thread aggregation, reconnect/reconstruction, missed-event recovery, and owner-UI survival/reattachment remain unavailable/disabled.
- Desktop source classification and product-visible ordinary Desktop rows remain disabled; Desktop realtime, approval, Session Token, terminal retention, duration, notification, and recovery remain unsupported.
- Future Observer remains all-unsupported and zero-data.
- Transport reachability, account connectivity, freshness, schema presence, fixture presence, and ownership-record presence do not promote a capability.

This is a **specification-level PASS**. Enforcement remains unproved until H1F passes.

## Required H1F / H1.1 minimum scope

H1F is a bootstrap and contract-implementation phase only. It must not absorb H2 transport, H3 reduction, UI, persistence, or capability validation/promotion.

### 1. Local repository bootstrap

1. Run `git init` at the current workspace root.
2. Do not create or configure a remote; `git remote -v` must be empty.
3. Do not push.
4. Preserve all existing handoff/spec files.
5. Record H1F start and end commit IDs and a reviewable H1F diff. A local baseline commit and one scoped H1F implementation commit are acceptable.

### 2. Swift/macOS skeleton

Create a formal macOS-capable Swift Package or Xcode project skeleton. The minimum preferred layout is a Swift Package with:

```text
Package.swift
Sources/CodexMonitorContracts/
Tests/CodexMonitorContractsTests/
Tests/CodexMonitorContractsTests/Fixtures/
```

Acceptance requires one compilable library target and one `.testTarget` executable through `swift test`. No application UI target is required in H1F; if an Xcode project is chosen, it must provide equivalent buildable contract and unit-test targets. Do not add third-party dependencies unless separately justified and reviewed.

### 3. Compilable contract types

Implement, at minimum, strongly typed and testable equivalents of:

- `CapabilityState` with exactly `unsupported`, `unvalidated`, `snapshot`, `liveAuthoritative`, and `mutationValidated`;
- granular capability identifiers/names; no composite `fullRealtime` member;
- `SourceID`, `SourceKind`, `EntityKind`, and `NamespacedID` with source-sensitive equality/hash behavior and non-empty opaque raw IDs;
- `Freshness`, observation mode, authority, epochs, `EvidenceMetadata`, and `Provenance`;
- `AdapterDescriptor`, immutable capability snapshot behavior, `AdapterOutput`, and `AdapterRegistry` boundaries;
- `AccountSnapshot`, rate-limit/Usage optional shapes, with authoritative cost absent/`nil` under the baseline;
- `SnapshotSummary` with snapshot-only provenance and unclassified/unvalidated source classification;
- `OwnershipRecord`, bounded `RuntimeObservationKind`, and `RuntimeObservationEnvelope` for only the retained H1 shapes;
- an empty `FutureObserverAdapter` whose capability snapshot is all-unsupported and whose output is structurally zero.

Types must preserve absence rather than manufacture defaults. Source IDs must not become stable account keys. Fixture provenance must be distinguishable from real Adapter provenance.

### 4. Mandatory runtime-observation admission contract

Implement a typed admission boundary before any future product/live reducer input:

1. Candidate envelope construction/decoding does not imply product eligibility.
2. The product-admission API requires an exact granular capability name and the current registry state for the same Adapter/source namespace.
3. Only `liveAuthoritative` can produce a live-reducer-eligible wrapper/token.
4. `unsupported`, `unvalidated`, and `snapshot` must be rejected from the live path with a typed reason.
5. A matching `unvalidated` descriptor is still rejected.
6. `observationMode = live`, `authority = partial`, transport connectivity, ownership-record presence, method/schema presence, or a fixture cannot bypass the gate.
7. Source kind/ID, Adapter identity/version, runtime instance, connection epoch, lifecycle epoch, and supplied namespaced parent identities must match the registered ownership/provenance record.
8. Rejection must not invoke a reducer spy, product callback, notification, persistence path, or UI path.
9. The current baseline must instantiate no `liveAuthoritative` real Adapter capability.

This is a contract/admission primitive, not an H3 State Engine implementation.

### 5. Sanitized fixtures and evidence separation

Provide minimal sanitized fixtures for the evidence-supported shapes catalogued in `../H1_CAPABILITY_BASELINE.md`. Every fixture must include fixture ID, source kind, exact baseline capability state, evidence run, CLI version, historical transport evidence label, harness/digest availability, sanitizer availability/version, confidence, and limitations.

Required rules:

- no real email, credentials, home paths, private content, raw retained IDs, or plausible live product claims;
- unavailable AR-P0 harness/digest and sanitizer version remain explicitly unavailable;
- historical transport evidence remains inconsistent/unresolved;
- H2's selected Unix-socket WebSocket is a separate forward-decision value;
- the Future Observer test fixture represents an empty expectation only and must not create an observation, snapshot, placeholder Thread, or source-health record.

### 6. Executable H1 contract tests

At minimum, `swift test` must execute and pass tests equivalent to:

1. capability taxonomy is exactly the five allowed states and has no composite realtime shortcut;
2. same raw Thread/Turn/Item ID in different sources is unequal;
3. entity kind participates in identity;
4. normalized observation/snapshot provenance is mandatory and internally consistent;
5. Account connection does not create runtime availability or `IDLE`;
6. fresh quota does not create runtime state, ring color, or animation eligibility;
7. Desktop raw `active` does not create `THINKING` or `WORKING`;
8. Account Usage does not create Session Token;
9. schema/method presence does not enable reset mutation;
10. `SnapshotSummary` cannot enter the live admission/reducer boundary;
11. fixture/mock data cannot mutate or promote a real Adapter descriptor to `liveAuthoritative`;
12. Future Observer exposes all-unsupported capabilities and zero outputs/data;
13. missing Account secondary window, cost, and detail fields remain `nil`;
14. Account, Monitor-owned Runtime, Desktop Snapshot, and Future Observer outputs cannot cross Adapter/source lanes;
15. capability downgrade clears/rejects any formerly eligible derived input rather than retaining it as live;
16. source/runtime/connection/lifecycle epoch mismatch is rejected;
17. a real Adapter envelope with matching but `unvalidated` capability is rejected and invokes zero reducer/product callbacks;
18. `unsupported` and `snapshot` runtime candidates are rejected from the live path;
19. transport/source health does not promote runtime capability;
20. choosing Unix-socket WebSocket for H2 does not rewrite the unresolved AR-P0 transport evidence label.

### 7. H1F build and report gate

H1F is accepted only when all of the following are true:

```text
git rev-parse --is-inside-work-tree  => true
git remote -v                        => empty
swift build                          => exit 0
swift test                           => exit 0, zero skipped required tests
Swift/package or Xcode targets       => present and reviewable
H1 contracts                         => compile
Future Observer outputs              => zero
real liveAuthoritative capabilities  => zero
H2 transport implementation          => absent
H3 reducer implementation            => absent
UI implementation                    => absent
capability promotions                => none
```

Generate `PHASE_H1F_REPORT.md` recording model/reasoning, start/end commits, files changed, exact build/test commands and results, fixture provenance audit, forbidden-inference audit, capability gates, deviations, and confirmation that no remote/push/H2/H3/UI work occurred.

H1F is not self-authorizing for H2. After H1F, a bounded review must inspect the code, diff, and test output and explicitly issue **PASS — AUTHORIZE H2** before H2 begins.

## Explicit H1F prohibitions

H1F must not:

- open or implement Unix/TCP sockets, WebSocket framing, JSON-RPC routing, initialize/notification handling, process launch, or runtime supervision;
- implement Account/Desktop/owned-runtime transport calls;
- implement a live reducer, state projection, persistence, notification, UI, AppKit/SwiftUI surfaces, or database;
- add `WAITING_APPROVAL`, Session Token, live multi-Thread, failed/interrupted real projection, reconnect/reconstruction, current-activity text, Desktop live state, Desktop rows, reset mutation, or any other gated feature;
- promote any capability or relabel AR-P0 evidence;
- create a remote repository or push.

## Files changed by H1R

- `PHASE_H1R_REPORT.md`

No H1 source document was rewritten. No Git repository was initialized. No H1F or H2 implementation was performed.

## Next phase recommendation

Do not enter H2.

下一阶段建议：GPT-5.6 Terra / High — H1F / H1.1 Bootstrap & Contract Implementation

