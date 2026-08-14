# PHASE_AR1_REPORT

Phase: Architecture Revision 1 — Hybrid v1 redesign  
Model used: GPT-5.6 Sol  
Reasoning level: High  
Date: 2026-08-10  
Start commit: N/A — workspace is not a Git repository  
End commit: N/A — workspace is not a Git repository

## Specs and evidence read

> Historical material; original paths are retained only on `codex/github-readiness-audit`.

- `FINAL_P0_REVALIDATION_REPORT.md`
- `PHASE_0E_REPORT.md`
- `P0_EVIDENCE_20260810_0B/schema/method_matrix.md`
- `P0_EVIDENCE_20260810_0D1/environment/remote-control.md`
- `04_STATE_ENGINE_AND_EVENT_MAPPING_v1.1_FROZEN.md`
- `05_ACCOUNT_USAGE_QUOTA_AND_RESET_MODEL_v1.0.md`
- `06_LOCAL_DATABASE_AND_SWIFT_DATA_LAYER_v1.0.md`
- `07_MACOS_SWIFTUI_APPKIT_ARCHITECTURE_v1.0.md`
- `08_DESIGN_SYSTEM_AND_COMPONENT_SPEC_v1.0.md`
- `09_USER_FLOWS_INTERACTION_AND_EDGE_CASES_v1.0.md`
- `10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md`
- `11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md`
- `12_PHASE_MODEL_SWITCHING_AND_EXECUTION_PLAYBOOK_v1.0.md` for old Phase 1–11/model allocation context

## Goal

- Accept the final P0 NO-GO without weakening it.
- Replace the old universal Desktop observer architecture with Hybrid v1.
- Preserve validated Account Layer behavior.
- Define complete realtime monitoring only for Monitor-owned runtimes/Threads/Turns.
- Define an honest snapshot-only Desktop mode.
- Reserve an official future observer Adapter without requiring later UI, State Engine, Usage, or SQLite redesign.
- Revise the development order and Sol/Terra/Luna allocation.
- Stop before implementation.

## Completed

- Classified FROZEN rules into unchanged cross-mode constants, unchanged live-only semantics, and P0-invalidated assumptions.
- Defined independent Account, Monitor-owned Runtime, Desktop Snapshot, and Future Observer layers.
- Defined source identity, provenance, observation mode, capability state, freshness, and field-level availability requirements.
- Kept `WAITING_APPROVAL` in the domain while gating it on an authoritative approval lifecycle capability.
- Excluded Desktop snapshots from the live State Engine and global realtime aggregation.
- Specified honest Desktop-only degradation for the Floating Orb, Quick View, Menu Bar capsule, and Menu Bar popup.
- Prohibited `thread/resume`, `thread/start`, and `thread/fork` as Desktop observer substitutes.
- Limited Session Token, current activity, live duration, terminal retention, notifications, and multi-Thread realtime aggregation to Monitor-owned or future validated live sources.
- Preserved account/quota/Usage/reset-credit reads at their current evidence level and kept reset-credit consumption disabled pending explicit mutation validation.
- Revised Transport, Domain, State Engine, Repository, presentation, and SQLite responsibilities around capabilities and source provenance.
- Added a future Observer Adapter seam that reuses normalized events, State Engine semantics, presentation models, account/Usage stores, and source-aware persistence.
- Marked every old Phase 1–11 prompt as requiring replacement/modification.
- Produced a new AR-P0 and H1–H11 development sequence with Sol/Terra/Luna assignments.

## Files changed

- `../14_ARCHITECTURE_REVISION_HYBRID_V1.md`
- `PHASE_AR1_REPORT.md`

No production source, project configuration, UI asset, visual reference, probe, database, or existing 04–13 specification was modified.

## Validation performed

- Static traceability review against specifications 04–11 — PASS.
- P0 evidence-boundary review — PASS; no missing Desktop subscription capability was reclassified as supported.
- Forbidden-path review — PASS; no `thread/resume` observer path, private backend, credential extraction, scraping, or JSONL primary source was introduced.
- Capability matrix consistency review — PASS; Desktop snapshots cannot emit live states.
- State Engine review — PASS; `WAITING_APPROVAL` and Session Token require source capabilities.
- UI honesty review — PASS; Desktop-only surfaces use neutral/non-live presentation and omit inferred runtime data.
- Future Adapter review — PASS at specification level; Adapter boundary, normalized observations, provenance, presentation contract, and database source schema are reserved.
- Scope review — PASS; documentation-only changes.

## Result

**PASS — Architecture Revision 1 documentation is complete.**

This result does not authorize production implementation and does not convert the old P0 into GO.

## P0/FROZEN deviations

- The P0 NO-GO remains unchanged.
- Product constants unrelated to unavailable observation remain frozen.
- Runtime-state semantics remain frozen but are now capability-scoped.
- Universal Desktop realtime monitoring, Desktop approval, Desktop Session Token, and Desktop reconnect/recovery claims are removed.
- Reset-credit read support is retained; reset-credit consumption remains unvalidated and disabled until explicitly authorized validation.

## Known risks / unresolved validation

- Monitor-owned full realtime lifecycle has not yet been proved on the installed runtime.
- Desktop read-only discovery/history remains unvalidated because Phase 0D.1 omitted `thread/list` and `thread/read`.
- App-server/WebSocket production maturity remains experimental/unsupported in current documentation.
- Sparse rate-limit updates, account identity stability/change, Usage timezone/null semantics, authoritative cost, and reset-credit consumption remain partial or untested.
- Safe survival/reattachment of an active Monitor-owned runtime across UI quit must be validated.

## Next phase

None is automatically authorized.

If the user separately approves continuation, the next phase is:

```text
AR-P0 — Hybrid capability validation
Primary: GPT-5.6 Terra / High
Decision review: GPT-5.6 Sol / High
```

Do not run the old Phase 1. Stop after this report.
