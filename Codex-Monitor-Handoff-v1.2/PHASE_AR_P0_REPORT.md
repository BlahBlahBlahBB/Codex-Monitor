# PHASE_AR_P0_REPORT

Phase: AR-P0 — Terra / High — Hybrid Capability Validation  
Date: 2026-08-10  
Architecture baseline: 14_ARCHITECTURE_REVISION_HYBRID_V1.md  
Start/end commit: N/A — workspace is not a Git repository.

## Goal

Run disposable, capability-scoped validation for Account semantics, a Monitor-owned runtime, Desktop read-only snapshots, and app-server transport maturity. Stop before H1 or production implementation.

## Completed

- Read the required Hybrid v1 architecture, AR1, final P0 revalidation, Phase 0E, and Master PRD materials.
- Read current official OpenAI app-server documentation.
- Added disposable-only Tools/AR_P0Probe tooling and three sanitizer/correlation unit tests.
- Captured sanitized Account snapshot field shapes.
- Started a separate Monitor-owned runtime; captured correlated lifecycle, Item lifecycle, successful terminals, token usage, two-Thread isolation, and client-disconnect survival.
- Ran only allowed Desktop read calls through the documented proxy.
- Produced sanitized evidence, a mock-only failed-terminal fixture, capability matrix, and reports.

## Tests / probes

| Check | Result |
|---|---|
| python3 -m unittest Tools/AR_P0Probe/test_ar_p0_probe.py | PASS — 3 tests |
| Account snapshots | PASS — field shapes |
| Owned Thread/Turn/Item correlation | PASS — 141 checked, 0 mismatches |
| Owned successful terminal | PASS — 4 completed outcomes |
| Owned token usage / multi-Thread isolation | PASS |
| Owned interrupt / failed terminal / approval lifecycle | NOT VALIDATED |
| Owned reconnect | PARTIAL — runtime survives client disconnect; active reattach unproved |
| Desktop loaded/list/read | PASS as snapshot transport, not live |
| Reset-credit consume | NOT RUN |
| Transport support/maturity record | PASS — experimental/unsupported production boundary recorded |

## Gate results

| Gate | Result |
|---|---|
| AR-P0-A Account semantics | **PARTIAL** |
| AR-P0-B Monitor-owned runtime | **PARTIAL** |
| AR-P0-C Desktop read-only snapshot | **PARTIAL** |
| AR-P0-D Transport support / maturity | **PASS** |
| AR-P0-E Reset mutation | **NOT RUN** |

See AR_P0_REPORT_DRAFT.md and AR_P0_CAPABILITY_MATRIX.json for the detailed per-capability verdicts.

## Files changed

- Tools/AR_P0Probe/ar_p0_probe.py — disposable sanitized probe only.
- Tools/AR_P0Probe/test_ar_p0_probe.py — bounded probe tests.
- AR_P0_EVIDENCE_20260810_01/ — sanitized evidence and mock-only fixture.
- AR_P0_CAPABILITY_MATRIX.json
- AR_P0_REPORT_DRAFT.md
- PHASE_AR_P0_REPORT.md

No product source, UI, database/repository, transport adapter, domain/state-engine, or old Phase 1 artifact was created or changed.

## Known limitations / blockers

- No stable account discriminator, sparse-update transition, Usage timezone/null semantics, cost, account switching, or reset mutation proof.
- No owned approval request/resolution, failed/interrupted terminal, active reconnect reconstruction, or active owner-UI exit survival proof.
- Desktop source classification as an ordinary Desktop Chat is not proved; Desktop remains snapshot/history only.
- Official app-server/WebSocket production maturity is experimental/unsupported and blocks an unqualified public v1 claim.

## Stop condition

**Stopped after AR-P0. H1 has not started.**

下一阶段建议：GPT-5.6 Sol / High — AR-P0 Decision Review

