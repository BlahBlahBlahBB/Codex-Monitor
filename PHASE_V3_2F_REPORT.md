# PHASE_V3_2F_REPORT

```text
Phase: V3-2F — State Semantics Targeted Fixes
Start commit: b7f3f2d763f48751698a3e73cf4c50cea7e43aa5
End commit: HEAD (scoped local commit below)
Date: 2026-08-10
Scope: six P1 fixes named by PHASE_V3_2R_REPORT only
Result: PASS — TARGETED FIXES COMPLETE; DO NOT ENTER V3-3
```

## Scope and files

Changed only:

- `Sources/CodexMonitorContracts/ApprovalLocalAdapter.swift`
- `Sources/CodexMonitorContracts/DesktopLocalAdapter.swift`
- `Sources/CodexMonitorContracts/StateEngine.swift`
- `Tests/CodexMonitorContractsTests/V3StateEngineTests.swift`
- `Codex-Monitor-Hybrid-Handoff-v2.0/22_PRAGMATIC_V3:/APPROVAL_LOGS_2_SANITIZED_SHAPE_V1.md`
- this report

No Account/Plan/Quota/Usage/Reset, UI, Monitor history, notifications,
Accessibility, Desktop control, or V3-3 code was added.

## 1. Real approval source parser

The adapter now pins the LP0/V3-2R installed shape: `PRAGMA user_version = 0`,
`logs(id, thread_id, ts, target, level, feedback_log_body)`, and the exact
target `codex_core::stream_events_utils`. Target lookalikes are ignored.

`feedback_log_body` is parsed transiently as closed structured text, never as
a whole-body JSON contract. Admission requires the observed request marker pair
`requestApproval + waitingOnApproval`, or a pinned resolution marker, together
with exact thread/turn/request-or-call/item correlation. Unknown
approval-looking variants fail the approval capability closed. The parser also
rejects generic resolution words and duplicate correlation fields rather than
accepting an ambiguous lookalike. The retained
sanitized shape capture contains marker names and opaque synthetic IDs only;
it contains no body, prompt, command, output, title, or real identifier.

## 2. Approval lifecycle and three-valued semantics

`ApprovalLifecycleCheckpoint` persists both the DB cursor and unresolved exact
request identities. Batch decode/admission is transactional: malformed rows
do not advance the cursor or mutate lifecycle state, so repeated polls remain
unavailable. Approval health is separately exposed as
`AVAILABLE_KNOWN_NOT_WAITING`, `AVAILABLE_WAITING`, `UNAVAILABLE`, or `STALE`.
Source loss preserves pending requests; recovery restores known health; exact
approval resolution or exact matching item output alone clears a request.

## 3. Atomic restart and pause/resume reconciliation

`RuntimeReconciliationThread` is a closed exact-revalidation input carrying
thread/turn, active item, activity, terminal identity/time, token provenance,
approval health/pending lifecycle, and source freshness. `installReconciliation`
replaces the per-thread reducer set atomically while presentation remains
paused/stale, then enters live state. Historical terminal time is retained, so
rebuild does not replay it as a new retention interval.

## 4. Activity and capability isolation

The reducer records an active item/call identity. A different item’s response
or reasoning cannot end the current Working item; overlapping items resolve by
latest exact start and only its exact completion/output returns to Thinking.
Runtime ownership health, activity evidence, approval health, and Session Token
health are independent. Session-token or approval loss does not produce
`DISCONNECTED`; buffered rollout data cannot clear a later ownership failure.

## 5. Terminal provenance and dedupe

Terminals now carry exact turn ID, event ID, and authoritative event time.
Live admission requires the exact active turn; nil-active historical terminal
records are rejected. Reconciliation accepts terminal history only through its
explicit `ReconciledTerminal` evidence. Duplicate/replayed events do not refresh
retention, and retention uses source event time rather than decode time.

## 6. Session Token provenance and monotonic authority

Snapshots now expose token provenance. An admitted rollout cumulative total is
`ROLLOUT_CUMULATIVE` authoritative and is monotonic per exact thread/session.
State DB registration can seed/cross-check only before authoritative rollout
admission and cannot lower or overwrite it. Reconciliation preserves this
provenance, with identity still keyed by `NamespacedID`.

## Regression evidence

Focused tests now include real-shape parser/checkpoint restoration, repeated
malformed polls, exact target gating, source loss/recovery, restart with two
unresolved approvals, exact and wrong item output, overlapping work items,
reconciliation across Thinking/Working/Waiting/terminal/Idle, pause terminal
reconciliation, capability health isolation, terminal nil-active rejection and
dedupe/event-time retention, and token DB-lag/provenance preservation.

```text
swift build       PASS
swift test        PASS — 94 tests, 0 failures
git diff --check  PASS
```

## Read-only and privacy audit

The approval DB remains opened only with `SQLITE_OPEN_READONLY`. No parser
result, checkpoint, snapshot, test fixture, or report carries approval body
text, prompt, command, tool arguments, or output. The read-only mutation test
continues to compare database bytes before/after polling.

## Gate

The six V3-2R P1 fixes are complete in this scoped commit. Do not start V3-3.

下一阶段建议：GPT-5.6 Sol / High — V3-2FR Final State Semantics Gate
