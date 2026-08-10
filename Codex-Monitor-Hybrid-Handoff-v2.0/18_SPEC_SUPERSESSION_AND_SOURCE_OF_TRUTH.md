# Codex Monitor — Spec Supersession & Source-of-Truth Matrix v2.0

## Active

| File | Status | Rule |
|---|---|---|
| `17_MASTER_PRD_V2_HYBRID.md` | ACTIVE MASTER | Highest product/implementation source of truth. |
| `FINAL_AR_P0_REPORT.md` | ACTIVE EVIDENCE DECISION | Binding capability/release gates. |
| `14_ARCHITECTURE_REVISION_HYBRID_V1.md` | ACTIVE ARCHITECTURE | Hybrid source/capability design baseline. |
| `PHASE_AR1_REPORT.md` | ACTIVE TRACEABILITY | AR1 completion/audit trail. |
| `PHASE_AR_P0R_REPORT.md` | ACTIVE TRACEABILITY | Final AR-P0 review/audit trail. |
| `00_APPROVED_VISUAL_REFERENCE_v1.9.html` | ACTIVE VISUAL REFERENCE | Visual reference only; native behavior wins. |

## Legacy references retained only where non-conflicting

| Legacy file | Status | Retain | Superseded |
|---|---|---|---|
| 04 State Engine | PARTIAL | state enum, priority, 0.8s/5s/15s semantics | universal Desktop eligibility / fallback inference |
| 05 Account/Usage | PARTIAL | honesty, dynamic quota, optional fields, cost `$--` | unvalidated sparse merge, stable identity, Session Token assumptions, mutation readiness |
| 06 Database/Data Layer | PARTIAL | SQLite, WAL, migrations, actors/repos | single-source transport/data model; add provenance/capabilities |
| 07 macOS Architecture | PARTIAL | SwiftUI+AppKit shell/window strategy | single `CodexConnectionActor`; add Adapter registry/source health |
| 08 Design System | PARTIAL | B capsule, Orb, native controls, glass boundaries | universal live-state variants; add neutral snapshot-only mode |
| 09 User Flows | PARTIAL | window interactions, native behavior | universal Desktop live flows/reconnect/approval/session token |

## Retired

```text
10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md
11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md
12_PHASE_MODEL_SWITCHING_AND_EXECUTION_PLAYBOOK_v1.0.md
all old Phase 1–11 execution prompts
```

They are historical evidence only.

Do not execute them.

## Binding precedence

```text
Master PRD v2
>
Final AR-P0 evidence decision
>
Architecture Revision Hybrid v1
>
later Hybrid execution/specialist docs
>
non-conflicting legacy 04–09
>
visual reference
>
retired old documents
```
