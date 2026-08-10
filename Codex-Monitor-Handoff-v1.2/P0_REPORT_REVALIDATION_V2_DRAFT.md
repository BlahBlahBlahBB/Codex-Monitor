# Codex Monitor P0 Report — Revalidation V2 Draft

Phase: 0D.1 — Terra / High — Standalone CLI Environment Remediation  
Execution date: 2026-08-10  
Model / reasoning: GPT-5.6 Terra / High  
Evidence: `P0_EVIDENCE_20260810_0D1/`  
Overall decision: **NO-GO — P0 remains incomplete. Stop; do not enter Phase 1.**

## Scope and safety result

This phase performed only the authorized standalone CLI remediation and P0 revalidation. The OpenAI official standalone installer was run after explicit user approval. It installed `codex-cli 0.147.0`, updated the user PATH for the standalone executable, and created the installer-managed standalone package. No `sudo` was used. ChatGPT.app was not deleted, moved, replaced, or modified. No credential, `auth.json`, token, cookie, API key, authorization header, or account identifier was read or written.

The existing P0Probe was extended only as disposable Phase 0 tooling to implement a bounded local Unix-socket WebSocket observer. It records sanitized method/shape summaries only; all protocol values and identities remain in memory and are discarded. It contains no Turn creation/resume/interrupt path, no approval response path, no reset-credit action, and no daemon lifecycle control.

## Environment remediation result

| Check | Status | Actual evidence |
|---|---|---|
| Official standalone installer | **PASS** | OpenAI installer completed after user approval; standalone CLI `0.147.0` installed. |
| PATH points to standalone CLI | **PASS** | `which codex` resolved to `<HOME>/.local/bin/codex`, linked to `<CODEX_HOME>/packages/standalone/current/bin/codex`. |
| Standalone managed package/cache | **PASS** | `current` links to the Apple Silicon `0.147.0` standalone release. |
| `remote-control start` availability | **PASS** | Standalone CLI help advertises `remote-control start --json`. |
| Managed daemon/control socket | **PARTIAL** | Start created the official socket, but reported errored remote-control connectivity. The local socket was nevertheless live and usable. |
| Control-socket security | **PASS** | Socket mode is owner-only (`srw-------`). |

## Live P0 transport evidence

The Probe connected to the official managed Unix socket and completed, in order:

1. HTTP WebSocket Upgrade — PASS.
2. `initialize` response — PASS.
3. `initialized` notification — PASS.
4. `account/read` — live response received; only field names retained.
5. `account/rateLimits/read` — live response received; only field names retained.
6. `account/usage/read` — live response received; only field names retained.
7. `thread/loaded/list` — live response received; only field names retained.

The standalone CLI generated the stable JSON and TypeScript schemas into the evidence directory (927 files) without passing `--experimental`.

## Desktop-created Turn hard gate

The user confirmed sending a harmless Desktop-created test task. Passive Probe windows were opened without the Probe itself creating or changing any Turn. The retained observer summaries include only `remoteControl/status/changed` plus the initialization and read responses. They contain **no** `thread/status/changed`, `turn/started`, item-lifecycle, or `turn/completed` notification and no identity correlation for a Desktop-created Turn.

The missing evidence may reflect timing/delivery behavior, but its cause is not inferred. Under the P0 hard-gate rule, the outcome is still **FAIL**: a secondary client did not prove passive observation of a Desktop-created Turn. A socket, a read snapshot, or a successful account request is not equivalent evidence.

## Gate matrix

| Gate | Status | Evidence / decision |
|---|---|---|
| P0-A Local supported app-server attach | **PASS** | Official control socket accepted WebSocket Upgrade and initialize lifecycle. |
| P0-B Observe Desktop-created Turn | **FAIL** | No actual event evidence for identity, status change, turn start, item lifecycle, or completion. Hard stop. |
| P0-C Passive approval lifecycle | **NOT TESTED** | Correctly skipped because P0-B did not PASS. Probe sent no approval response. |
| P0-D `account/read` | **PASS** | Live response received after initialization; values were not retained. |
| P0-E Rate limits / reset-credit read | **PARTIAL** | Live snapshot response included rate-limit/reset-credit top-level fields; update semantics and any consumption remain untested. |
| P0-F Account Usage | **PARTIAL** | Live response included `dailyUsageBuckets` and `summary`; date/account correlation semantics remain untested. |
| P0-G Thread/session token usage | **NOT TESTED** | No Desktop Turn/token-usage event delivered. |
| P0-H Account change detection | **NOT TESTED** | No account action was induced. |
| P0-I Safe official active account switching | **NOT TESTED** | No saved-account list/select/switch surface was exercised. |
| P0-J Reconnect / reconciliation | **PARTIAL** | Only P0Probe was disconnected/reconnected; re-initialize and all four snapshots succeeded. Event-race and Desktop-thread reconciliation remain unproved. |

## Required prohibitions and decision

**NO-GO. Do not enter Phase 1.** The blocker rules require an immediate stop when a Desktop-created Turn cannot be observed. Keep runtime-monitoring claims, yellow `WAITING_APPROVAL`, approval notifications, session-token monitoring, and any production observer transport disabled. Do not substitute a Monitor-owned app-server, thread lifecycle ownership, screen/accessibility scraping, JSONL tailing, credentials, or a private backend.

No passive approval test, reset-credit consumption, account mutation, task mutation, desktop restart, or daemon stop/restart was performed.

## Next step

Stop after Phase 0D.1. The only suggested follow-up is **GPT-5.6 Sol / High — Phase 0E Final Revalidation Review**. It must preserve this NO-GO result unless it has real passive secondary-client evidence for every required Desktop-created Turn event.
