# PHASE_V3_2_FINAL_CLOSURE_REPORT

```text
Phase: V3-2 final approval pipeline closure
Scope: only approval lifecycle/resolution and restart reconciliation catch-up
Result: BLOCKED — DO NOT ACCEPT FINAL GATE OR ENTER V3-3
```

## Implemented production safeguards

- Resolution parsing no longer requires request markers to be absent or fixed
  `turn_id`/`call_id` field counts. A resolution may retain request context,
  but it must have exactly one known resolution status plus one unambiguous
  turn and call value.
- Admission remains exact: the adapter exposes a resolution and removes durable
  state only when its source-thread + turn + request triple already exists in
  the unresolved lifecycle map. Cross-thread, cross-turn, wrong-request, and
  ambiguous rows cannot clear an approval.
- Checkpoint loss/corruption now recovers by a bounded replay from the
  read-only source. The production installer catches up until an available
  cursor is unchanged on a subsequent poll; it stays reconciling if the source
  becomes unavailable or the safety bound is reached.
- The bound is configurable, defaults to 256 polls, and does not encode a
  source-specific page count. A progressing malformed row can be passed while
  recovering later valid rows; a non-progressing unavailable source fails
  closed.

## Read-only installed-source validation

No body, prompt, command, output, path, title, or production identifier was
printed or retained.

The installed approval database was scanned through the production adapter and
the typed observations were fed to an isolated State Engine using only their
typed identities and timestamps.

```text
admitted requests                  1
admitted resolutions               0
reducer resolution transitions     0
```

The one admitted request reached `Waiting Approval`. Privacy-bounded structural
inspection found no later row that carried its exact source-thread, turn, and
request/call correlation identity. Therefore no installed row can safely be
identified as its resolution. This is an evidence limitation of the current
local snapshot, not a condition that can be repaired by weakening attribution.

The opt-in installed-source lifecycle test intentionally fails on those two
zero counters, so a synthetic resolution cannot be mistaken for production
validation.

The production installer was separately exercised against a fresh,
read-only approval checkpoint. It completed more than one approval poll before
entering live state, satisfying the catch-up-before-live requirement for the
available source snapshot.

## Definition of Done

- [x] Real request admitted and reaches `Waiting Approval`.
- [ ] Real resolution admitted: no exactly attributable installed resolution
  exists in the inspected snapshot.
- [ ] Real reducer resolution transition observed: blocked by the preceding
  evidence limit.
- [ ] Exact `Waiting Approval` cleared by a real resolution: blocked by the
  preceding evidence limit.
- [ ] Durable unresolved lifecycle removal validated with a real resolution:
  blocked by the preceding evidence limit.
- [x] Synthetic exact-lifecycle regression proves resolved approvals do not
  resurrect after restart.
- [x] Fresh production installer catches up to a stable cursor before live.
- [x] Catch-up is bounded and fail-safe for unavailable/non-stable sources.
- [x] Existing tool-completion, terminal replay, and Session Token restart
  authority regressions remain green.
- [x] `swift build` passes.
- [x] `swift test` passes (installed-source checks are opt-in and skipped
  without a local-source environment variable).
- [x] `git diff --check` passes.

## Gate decision

The restart blocker is closed by implementation and installed-source
validation. The approval-resolution blocker cannot be closed on this machine:
the required real resolution representation/correlation is absent from the
available installed data. Per the scope rule, no guessed schema or synthetic
substitute was used. Do not accept the final V3-2 gate and do not enter V3-3.
