# PHASE_0D1_REPORT

Phase: 0D.1 — Terra / High — Standalone CLI Environment Remediation  
Model used: GPT-5.6 Terra  
Reasoning level: High  
Date: 2026-08-10  
Start commit: N/A — workspace is not a Git repository  
End commit: N/A — workspace is not a Git repository

Specs read:

- `11_MASTER_PRD_AND_CODEX_BUILD_INSTRUCTIONS_v1.0.md`
- `10_P0_PROTOCOL_VALIDATION_AND_IMPLEMENTATION_PLAN_v1.0.md`
- `P0_REPORT.md`
- `PHASE_0C_REPORT.md`
- `P0_REPORT_REVALIDATION_DRAFT.md`
- `PHASE_0D_REPORT.md`
- `P0_EVIDENCE_20260810_0D/`
- `13_EXECUTION_PACK/03A1_PHASE_0D1_TERRA_STANDALONE_CLI_REMEDIATION.md`
- `13_EXECUTION_PACK/91_PHASE_REPORT_TEMPLATE.md`
- `13_EXECUTION_PACK/92_BLOCKER_ESCALATION_RULES.md`

Goal:

- Repair only the standalone CLI precondition using the OpenAI official installer.
- Revalidate P0 transport and passive observer gates without entering Phase 1.

Implemented:

- Recorded that the original PATH target was ChatGPT.app-bundled Codex CLI `0.147.0-alpha.6.5`.
- Paused for and received user approval before running the only permitted installer: `curl -fsSL https://chatgpt.com/codex/install.sh | sh`.
- Verified PATH now resolves to standalone Codex CLI `0.147.0` and the standalone managed package is present.
- Verified `remote-control` and `remote-control start` help, then started the managed daemon through the locally advertised command. Its external remote-control connection errored, but the local owner-only control socket appeared and accepted a supported local connection.
- Generated current stable schema artifacts from standalone CLI without `--experimental`.
- Extended the disposable P0Probe with a bounded, read-only Unix-socket WebSocket lifecycle. It performed Upgrade, initialize/initialized, four required read calls, and a Probe-only reconnect snapshot. All retained output is sanitizer-only.
- Requested and received user confirmation of a harmless Desktop-created test task. Multiple passive observer windows recorded no Desktop Turn notification sequence. No approval observation was attempted because the prerequisite hard gate did not pass.
- Produced this report, `P0_REPORT_REVALIDATION_V2_DRAFT.md`, and `P0_EVIDENCE_20260810_0D1/`; stopped before Phase 1.

Files changed:

- `Tools/P0Probe/p0_probe.py`
- `Codex-Monitor-Handoff-v1.2/P0_EVIDENCE_20260810_0D1/`
- `Codex-Monitor-Handoff-v1.2/P0_REPORT_REVALIDATION_V2_DRAFT.md`
- `Codex-Monitor-Handoff-v1.2/PHASE_0D1_REPORT.md`

Tests run:

- OpenAI standalone installer — PASS; standalone CLI `0.147.0` installed after explicit approval.
- `which codex`, version, symlink/package inspection — PASS; PATH uses standalone CLI.
- `codex remote-control --help`, `codex remote-control start --help` — PASS.
- `codex remote-control start --json` — PARTIAL; daemon/socket appeared, external remote-control connection reported errored.
- Socket metadata and P0Probe status — PASS; official socket present, Unix socket, owner-only mode.
- Current stable `generate-json-schema` / `generate-ts` — PASS; 927 schema files, no `--experimental`.
- P0Probe WebSocket Upgrade, initialize/initialized, `account/read`, `account/rateLimits/read`, `account/usage/read`, `thread/loaded/list` — PASS for live read transport.
- Desktop-created Turn passive observer — FAIL; no required event evidence delivered in retained passive windows.
- P0Probe-only reconnect + snapshot — PARTIAL; reconnect succeeded, but Desktop event reconciliation remains unproved.
- `python3 -m unittest Tools/P0Probe/test_p0_probe.py` — PASS; 5 passed.

Test result:

**PARTIAL for Phase 0D.1 environment remediation; FAIL / NO-GO for the P0 product gate.**

P0/Frozen deviations:

- None. The Desktop-created Turn hard gate was not relaxed; a live socket/read snapshot was not promoted to observer success.

Known issues:

- `remote-control start` reported errored external remote-control connectivity even though the official local socket was available.
- P0Probe passive windows did not receive the required Desktop-created Turn event family following the user-confirmed test task. Cause is unproven and is not guessed.
- Approval, token-usage events, account-change, account-switching, rate-limit update semantics, Usage semantics, and full reconnect event-race behavior remain unvalidated.

Blockers:

- Secondary client did not prove observation of Desktop-created thread identity, `thread/status/changed`, `turn/started`, item lifecycle, or `turn/completed`.
- Under `92_BLOCKER_ESCALATION_RULES.md`, this requires an immediate stop and prohibits Phase 1.

Security/privacy notes:

- No `sudo`; no ChatGPT.app deletion, replacement, movement, restart, or process termination.
- No credential/auth-file/token/API-key/cookie/authorization-header access or mutation.
- No private backend, scraping, JSONL tailing, Monitor-owned app-server, Probe-owned Turn, approval response, reset-credit consumption, account mutation, or desktop daemon shutdown/restart.
- Evidence retains only sanitized transport summaries and schema artifacts.

Next phase:

- **Stop. Phase 1 is not authorized.**
- Only a later **Phase 0E Final Revalidation Review** may evaluate this evidence; it must retain NO-GO unless required live Desktop-observer evidence exists.

Recommended next model:

GPT-5.6 Sol  
Reasoning: High
