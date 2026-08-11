# PHASE_V3_2F2_REPORT

```text
Phase: V3-2F2 — Production Path Closure
Blocker source: PHASE_V3_2FR_REPORT.md (only)
Scope: the six reported V3-2 production-path blockers only
Result: CLOSED — DO NOT ENTER V3-3
Date: 2026-08-11
```

## Closure

1. `ApprovalLocalAdapter` now filters the exact installed logger target in
   SQLite before materializing rows.  A malformed approval-looking row emits
   closed unavailable evidence and advances only with that evidence; it cannot
   pin the cursor before a later verified request/resolution.  Known request
   and resolution wrappers are structurally bounded, and lifecycle storage is
   keyed by exact `(thread, turn, request)`.

2. `ApprovalLifecycleRuntimeOwner` persists the opaque cursor and unresolved
   lifecycle after each admitted poll.  The new reconciliation installer uses
   that stored lifecycle rather than requiring a test-supplied pending list.
   Exact function/custom-tool output remains the verified fallback that clears
   the matching pending approval only.

3. `LocalRuntimeReconciliationInstaller` is the production restart and
   pause/resume installation path.  It performs the approval poll, exact State
   DB/rollout checkpoint rebind, hydration construction, and one atomic reducer
   installation.  A fresh `RuntimeStateEngine` begins reconciling, so it cannot
   expose live state before this occurs.

4. Function and custom-tool output decodes as `.agentResponse`, which uses the
   reducer's exact completion branch to clear only the active matching item and
   approval.

5. Terminal decode accepts the observed successful `task_complete` shape with
   omitted `error` as well as the older explicit-null form.  It preserves a
   source terminal time (outer timestamp when decodable, otherwise payload
   `completed_at`) and derives stable replay identity from source values only.

6. Rollout checkpoint hydration now carries the cumulative authoritative token
   total to the production reconciliation installer.  That value is preferred
   over the State DB token seed and retains rollout provenance after restart.

No UI, Account, Quota, Usage, Reset, H2/WebSocket audit, or V3-3 work was
changed.

## Verification

All local-source validation was read-only and emitted no log body, prompt,
tool input/output, title, path, or production identifier.

```text
swift test                                      PASS — 103 tests, 0 failures
                                                (2 opt-in local probes skipped)
swift test --filter ProductionPathValidationTests
  with installed logs_2.sqlite + rollout JSONL  PASS — 2 tests, 0 failures
git diff --check                                PASS
```

The opt-in installed-source probes verify:

- real `logs_2.sqlite` request admission and recovery after malformed rows;
- real function/custom-tool output completion mapping;
- real terminal source time and non-decode-time identity;
- synthetic production-owner restart installation with authoritative Session
  Token restoration and default startup reconciliation.

## Gate

**CLOSED — stop here.  Do not enter V3-3.**
