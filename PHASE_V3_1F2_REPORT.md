# PHASE_V3_1F2_REPORT

```text
Phase: V3-1F2 — Checkpoint Admission Gate Fix
Start commit: 3a9965faa9054ebda255c74e26d337f3adef7482
End commit: this scoped commit (recorded by the final git log entry)
Date: 2026-08-10
Scope: The sole V3-1FR checkpoint-pending epoch-admission P1
Result: PASS — TARGETED FIX COMPLETE; DO NOT ENTER V3-2
```

## Changed files

- `Sources/CodexMonitorContracts/DesktopLocalAdapter.swift`
- `Tests/CodexMonitorContractsTests/DesktopLocalAdapterTests.swift`
- `PHASE_V3_1F2_REPORT.md`

## Pending checkpoint admission

`open(checkpoint:)` now installs a candidate reader in a per-thread pending
admission slot. It does not replace the active reader, clear the remembered
process epoch, or clear the mismatch latch. During this interval `health(...)`
always emits unavailable `checkpointAdmissionPending` evidence and cannot bind
or return available for a supplied epoch.

The first checkpoint poll first verifies the current exact State DB thread row
and rollout path. The candidate reader then verifies its opened descriptor
device/inode against the checkpoint cursor, cursor bounds, `session_meta`
payload ID, and bounded reconstruction before yielding any appended records.
Only a poll with no invalidation reaches the single admission commit point:
the replacement reader is installed, the old latch is cleared, and the staged
observed epoch becomes the accepted owner.

## Failure and success proof

- Replacement and same-inode session mismatch on first poll produce no rollout
  records, retain unavailable health, discard the candidate epoch, and require
  an explicit fresh checkpoint open before retrying.
- A valid first poll permits the staged new epoch only after exact admission;
  the old epoch is then rejected again.
- Pending admission is namespaced per thread and does not change the other
  thread's health or epoch latch.
- EOF checkpoint revalidation remains non-replaying. Appended token, activity,
  and terminal records remain exactly-once across checkpoint recovery.

## Focused regressions

- prior mismatch → checkpoint open → pre-poll new epoch remains unavailable;
  valid admission then accepts only the new epoch and rejects the old epoch;
- checkpoint replacement rejection retains unavailable health;
- checkpoint `session_meta` mismatch retains unavailable health;
- pending checkpoint state is isolated from another thread;
- strengthened EOF checkpoint test proves health cannot be available before
  the exact first poll;
- existing checkpoint append/token/activity/terminal exactly-once regression
  remains passing.

## Verification

```text
swift test --filter DesktopLocalAdapterTests  PASS — 25 tests, 0 failures
swift build                                  PASS
swift test                                   PASS — 71 tests, 0 failures
git diff --check                             PASS
```

All pre-existing 67 tests remain; the suite now contains 71 tests. No required
tests were skipped. SwiftPM used the normal Xcode module-cache permission for
verification.

## Scope confirmation

This commit changes only V3-1 checkpoint admission behavior and its tests. It
adds no V3-2 State Engine, Waiting Approval, Account/Quota/Usage/Reset, UI,
Monitor SQLite history, old H2 WebSocket, or Codex Desktop lifecycle control.

下一阶段建议：GPT-5.6 Terra / High — V3-1FR2 Final Targeted Review
