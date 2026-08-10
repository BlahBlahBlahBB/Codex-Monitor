# Codex Monitor — Hybrid H1–H11 Model & Phase Playbook

## Fixed workflow

For every phase:

```text
1. Finish current phase
2. Generate PHASE_Hx_REPORT.md
3. Stop
4. New Codex Chat in same Project
5. Manually select next model
6. Read Master PRD v2 + relevant spec + prior report
7. Execute only current phase
```

Do not reply “continue” into the old phase chat.

## Phase/model map

| Phase | Work | Model | Reasoning | Required review |
|---|---|---|---|---|
| H1 | Capability contracts / Adapter registry / provenance / fixtures | Terra | High | H1R Sol High |
| H2 | Transport Adapters / owned-runtime supervisor | Terra | High | H2R Sol High |
| H3 | Capability-driven Domain / State Engine | Terra | High | H3R Sol High |
| H4 | Account/rate-limit/Usage read adapters | Terra | High | H4R Sol High |
| H5 | SQLite/repositories/migrations | Terra | Medium; High for migrations | Sol only if architecture changes |
| H5L | repetitive DB/fixture tests | Luna | Medium | Terra review |
| H6 | AppKit utility shell | Terra | High | H6R Sol High |
| H7 | Functional UI / all source modes | Terra | Medium | Terra High review |
| H7L | localization/repetitive UI tests | Luna | Medium | Terra |
| H8 | Liquid Glass / design fidelity | Terra | High | H8R Sol High |
| H9 | system integrations/accessibility | Terra | Medium | Terra High |
| H9L | accessibility/repetitive tests | Luna | Medium | Terra |
| H10 | capability/source QA | Luna matrix + Terra fixes | Medium/High | Sol only for escalation |
| H11 | RC truth/safety/design audit | Sol | High | Terra fixes → Sol sign-off |

## Escalation

```text
Terra Medium
→ Terra High
→ Sol High root-cause/architecture review
→ Terra implements reviewed fix
```

Escalate to Sol when:

```text
FROZEN/product meaning would change
capability promotion is proposed
protocol ambiguity affects user-visible truth
security/privacy issue
cross-module architecture change
release gate
```

## Current restriction

Only H1 is currently authorized.

H2 starts only after H1R says so.
