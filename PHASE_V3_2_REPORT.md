# PHASE_V3_2_REPORT

```text
Phase: V3-2 — Approval Adapter + Deterministic State Engine
Start commit: e786f58c2ef2c64c97822fba8ec7747f274d6466
End commit: recorded by the scoped local commit below
Date: 2026-08-10
Scope: local read-only approval evidence, per-thread reducer, aggregation,
       retention, pause/resume domain contract, immutable UI-ready snapshots
Result: PASS — V3-2 IMPLEMENTATION COMPLETE
```

## Delivered

- `ApprovalLocalAdapter` reads a configured `logs_2.sqlite`-style `logs` table
  using `SQLITE_OPEN_READONLY` only. It validates a pinned `user_version` and
  an exact allow-listed column set, checks database device/inode continuity,
  bounds busy retry and page size, and emits only `ApprovalRequested`,
  `ApprovalResolved`, and source-unavailable evidence.
- Approval observations require the local source namespace, exact `thread_id`,
  exact turn ID, and exact request/call ID. Resolutions can close only the
  matching request in that same thread and turn. The public checkpoint is
  `(file identity, last logs.id)`; the adapter holds no Monitor history store.
- `RuntimeStateEngine` is a deterministic, independent reducer per
  `NamespacedID(thread)`. Its complete frozen state vocabulary is
  `DISCONNECTED`, `PAUSED`, `IDLE`, `THINKING`, `WORKING`,
  `WAITING_APPROVAL`, `COMPLETED`, `FAILED`, `INTERRUPTED`, and
  `SYSTEM_ERROR`.
- Active arbitration is evidence-only: task start defaults conservatively to
  Thinking; reasoning selects Thinking; tool/file activity selects Working;
  agent response and token updates do not flip Thinking/Working. Ambiguous or
  silent activity preserves the last proven active state. Only the Monitor's
  `recordSystemError` API can create `SYSTEM_ERROR`; Codex task failure remains
  `FAILED`.
- Global aggregation keeps every thread independent and chooses one stable
  representative by frozen priority, authoritative recency, then a stable
  namespaced ID. There is no title/time-based join or merged thread identity.
- `GlobalRuntimeSnapshot` and `ThreadRuntimeSnapshot` are immutable value
  contracts for a future UI. They expose state, state-since, representative
  thread, closed safe activity label, freshness, active/waiting counts, title,
  model, turn start, and per-thread cumulative Session Token only.
- Pause is domain-only. While paused or revalidating, reduction ignores live
  observations, returns `PAUSED` with stale freshness, and cannot fabricate a
  terminal. Resume remains paused until the owner explicitly calls
  `completeResumeReconciliation()` after the V3-1 exact checkpoint/rebind
  validation path has completed.

## Approval proof

The approved primary source is the LP0-observed structured local log DB:
incremental monotonic `logs.id`, `thread_id`, timestamp, target, level, and
body. The schema is caller-pinned and must contain exactly the required
allow-listed columns. Bodies are parsed transiently inside the reader and are
discarded before an observation is returned. Recognized target plus malformed
or missing request/turn identity downgrades the approval source to unavailable;
unknown targets produce no lifecycle fact.

Request targets: command execution, file change, permissions, and auto-review
`requestApproval`. Resolution targets include `serverRequest/resolved` and
the corresponding allow-listed approval-resolved forms. No Accessibility
fallback, permission request, approval response, mutation, or old H2 WebSocket
path was added.

## Per-thread transition matrix

| Evidence | State result |
|---|---|
| healthy source with no active turn | `IDLE` |
| task start / reasoning | `THINKING` |
| tool or file-change activity | `WORKING` |
| token only / agent response | preserves proven active state |
| exact unresolved approval for active turn | `WAITING_APPROVAL` |
| exact resolution | restores latest valid/pre-approval active state |
| explicit success terminal | `COMPLETED` |
| explicit failure terminal | `FAILED` |
| explicit interrupted abort | `INTERRUPTED` |
| Monitor-internal fatal state error | `SYSTEM_ERROR` |
| source loss with no terminal | `DISCONNECTED` |
| silence / time gap | no terminal inference |

## Aggregation and retention proof

Global order is frozen as:

```text
SYSTEM_ERROR / FAILED / INTERRUPTED
> WAITING_APPROVAL
> WORKING / THINKING
> COMPLETED
> IDLE
> DISCONNECTED
```

Pause globally overrides the aggregation only while the Monitor setting is
paused/revalidating. Equal priorities use latest state evidence, then stable
source/entity/raw ID ordering. `COMPLETED` retains exactly 5 seconds; `FAILED`,
`INTERRUPTED`, and `SYSTEM_ERROR` retain exactly 15 seconds. A later active
turn on the same thread clears any retained terminal immediately. All timer
tests use an injected deterministic clock, never a wall-clock sleep.

## Verification

```text
swift build        PASS
swift test         PASS — 86 tests, 0 failures
git diff --check   PASS
```

The new focused coverage includes reasoning/tool/token arbitration, exact and
cross-thread approval handling, terminal-over-approval, failed versus system
error, source loss and silence, all retention durations, new-turn override,
multi-thread global priority, pause/resume reconciliation, stale terminal
rejection, approval checkpoint restart/dedupe, schema/malformed/rotation
fail-closed behavior, bounded busy retry, source read-only behavior, and no raw
approval body in result diagnostics.

## Scope, privacy, and read-only audit

- The only database open in `ApprovalLocalAdapter` uses `SQLITE_OPEN_READONLY`.
  Tests compare database bytes before and after polling.
- Approval payloads, prompt bodies, tool arguments, command output, chat text,
  and private paths are absent from adapter observations and snapshots.
- No Account/Quota/Usage, Reset, UI, Monitor SQLite history, notifications,
  Accessibility, Desktop lifecycle control, or legacy H2 WebSocket work was
  implemented.
- Pre-existing unrelated untracked handoff/report files remain untouched and
  are excluded from the scoped commit.

## Known follow-up gates

- V3-2R should independently audit the concrete installed `logs_2.sqlite`
  column mapping/event variants against a retained sanitized capture and review
  the source-epoch-to-approval binding at integration boundaries.
- V3-3 may add the separately scoped Account/Quota/Usage adapter only after
  its own authorization; it must not alter runtime state or Session Token
  semantics.

下一阶段建议：GPT-5.6 Sol / High — V3-2R State Semantics Gate
