# Codex Monitor — Spec Supersession & Source-of-Truth Matrix v2.0

## Active

| File | Status | Rule |
|---|---|---|
| `../product/17_MASTER_PRD_V2_HYBRID.md` | ACTIVE MASTER | Highest product/implementation source of truth. |
| `evidence/FINAL_AR_P0_REPORT.md` | ACTIVE EVIDENCE DECISION | Binding capability/release gates. |
| `14_ARCHITECTURE_REVISION_HYBRID_V1.md` | ACTIVE ARCHITECTURE | Hybrid source/capability design baseline. |
| `evidence/PHASE_AR1_REPORT.md` | ACTIVE TRACEABILITY | AR1 completion/audit trail. |
| `evidence/PHASE_AR_P0R_REPORT.md` | ACTIVE TRACEABILITY | Final AR-P0 review/audit trail. |
| `../design/APPROVED_VISUAL_REFERENCE.html` | ACTIVE VISUAL REFERENCE | Visual reference only; native behavior wins. |

## Legacy references retained only where non-conflicting

| Legacy file | Status | Retain | Superseded |
|---|---|---|---|
| `../reference/legacy-v1.2/04_STATE_ENGINE_AND_EVENT_MAPPING_v1.1_FROZEN.md` | PARTIAL | state enum, priority, 0.8s/5s/15s semantics | universal Desktop eligibility / fallback inference |
| `../reference/legacy-v1.2/05_ACCOUNT_USAGE_QUOTA_AND_RESET_MODEL_v1.0.md` | PARTIAL | honesty, dynamic quota, optional fields, cost `$--` | unvalidated sparse merge, stable identity, Session Token assumptions, mutation readiness |
| `../reference/legacy-v1.2/06_LOCAL_DATABASE_AND_SWIFT_DATA_LAYER_v1.0.md` | PARTIAL | SQLite, WAL, migrations, actors/repos | single-source transport/data model; add provenance/capabilities |
| `../reference/legacy-v1.2/07_MACOS_SWIFTUI_APPKIT_ARCHITECTURE_v1.0.md` | PARTIAL | SwiftUI+AppKit shell/window strategy | single `CodexConnectionActor`; add Adapter registry/source health |
| `../reference/legacy-v1.2/08_DESIGN_SYSTEM_AND_COMPONENT_SPEC_v1.0.md` | PARTIAL | B capsule, Orb, native controls, glass boundaries | universal live-state variants; add neutral snapshot-only mode |
| `../reference/legacy-v1.2/09_USER_FLOWS_INTERACTION_AND_EDGE_CASES_v1.0.md` | PARTIAL | window interactions, native behavior | universal Desktop live flows/reconnect/approval/session token |

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
Master PRD v2 (`../product/17_MASTER_PRD_V2_HYBRID.md`)
>
Final AR-P0 evidence decision (`evidence/FINAL_AR_P0_REPORT.md`)
>
Architecture Revision Hybrid v1 (`14_ARCHITECTURE_REVISION_HYBRID_V1.md`)
>
later Hybrid execution/specialist docs
>
non-conflicting legacy 04–09 (`../reference/legacy-v1.2/`)
>
visual reference (`../design/APPROVED_VISUAL_REFERENCE.html`)
>
retired old documents
```
