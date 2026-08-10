# Codex Monitor P0 Report — Revalidation Draft

Phase: 0D — Terra / High — Control Socket / Remote-Control Revalidation  
Execution date: 2026-08-10  
Model / reasoning: GPT-5.6 Terra / High  
Git commit: N/A — workspace is not a Git repository  
Evidence: `P0_EVIDENCE_20260810_0D/`  
Overall decision: **NO-GO — P0 remains incomplete. Stop; do not enter Phase 1.**

## Scope and safety result

This was a P0 remediation revalidation only. No production UI, Phase 1 transport, private backend, credential read/write, approval response, account mutation, reset-credit action, Probe-owned Turn, or Desktop process replacement occurred.

Read-only diagnostics showed that the installed Codex CLI exposes experimental `app-server` and `remote-control` commands. `codex doctor --json` reported a missing control socket and a non-running ephemeral background server. `codex app-server daemon version` then failed only because that socket did not exist.

Because `codex remote-control start --help` is explicitly supported locally and no daemon existed, Phase 0D issued the official `codex remote-control start --json` command. It failed before daemon creation: this ChatGPT.app-bundled CLI requires the Codex-installer-managed standalone binary at `<CODEX_HOME>/packages/standalone/current/codex`, which is not present. The suggested installer command was not run. Thus no daemon, socket, or socket permission/mode became available.

## Required capability distinction

| Capability | Status | Actual evidence and boundary |
|---|---|---|
| A. Independent `codex app-server --listen unix://...` | **NOT TESTED** | Local help advertises `unix://` and `unix://PATH` listeners. No independent app-server was started because it would be Monitor-owned and cannot prove visibility into Codex Desktop-created Turns. |
| B. Managed `codex remote-control` daemon | **FAIL** | The command is advertised, but its only permitted Phase 0D start attempt failed before startup due to missing standalone managed install. No control socket appeared. |
| C. Secondary Monitor client observes a Codex Desktop-created Turn | **NOT TESTED** | With no official socket, the Probe could not open WebSocket transport or run the required passive Desktop-created-Turn observation. A or B would not automatically prove C. |

## Gate matrix

| Gate | Status | Evidence / consequence |
|---|---|---|
| P0-A Local supported app-server attach | **FAIL** | The actual candidate socket `<CODEX_HOME>/app-server-control/app-server-control.sock` was absent before and after the official remote-control start attempt. No HTTP WebSocket Upgrade or initialize lifecycle was possible. |
| P0-B Observe Desktop-created Turn | **NOT TESTED** | No secondary client connection could be established. No user action was requested because a Desktop-created Turn would not be observable without the prerequisite transport. **Hard gate remains unmet.** |
| P0-C Passive approval lifecycle | **NOT TESTED** | No connected passive observer. The Probe sent no approval response and no approval was induced. |
| P0-D `account/read` | **NOT TESTED** | Normal requests are prohibited before successful initialize; initialize was unavailable. |
| P0-E `account/rateLimits/read` | **NOT TESTED** | Same transport prerequisite failure. |
| P0-F `account/usage/read` | **NOT TESTED** | Same transport prerequisite failure. |
| P0-G `thread/tokenUsage/updated` | **NOT TESTED** | No live Turn event stream. |
| P0-H Account change detection | **NOT TESTED** | No initialized client and no account action attempted. |
| P0-I Safe official active account switching | **NOT TESTED** | No approved saved-account list/select/switch surface was tested; credential-bearing paths were not used. |
| P0-J Reconnect / reconciliation | **NOT TESTED** | A Probe connection never existed; only the Probe itself would have been disconnected/reconnected. |

## P0Probe and required protocol sequence

`Tools/P0Probe` was invoked against the actual doctor-discovered candidate socket. Its safe status command reported `absent` and made no connection attempt. The existing offline tests passed (5/5), which verifies only the helper’s sanitizer/status/merge/epoch fixtures.

The following live requirements are all **NOT TESTED**, not inferred from schema or help text: WebSocket HTTP Upgrade; `initialize`; `initialized`; `account/read`; `account/rateLimits/read`; `account/usage/read`; `thread/loaded/list`; `thread/status/changed`; `turn/started`; item lifecycle; `turn/completed`; passive approval request/resolution; and reconnect snapshot reconciliation.

## Exact local command findings

- `codex --version` → `codex-cli 0.147.0-alpha.6.5`.
- `codex app-server --help` → experimental command; advertises `--listen stdio://|unix://|unix://PATH|ws://IP:PORT|off`.
- `codex remote-control --help` → experimental command; advertises `start`, `stop`, and `pair`; no `status` subcommand.
- `codex remote-control start --help` → command supports `--json` and no alternate daemon/runtime path.
- `codex doctor --json` → daemon not running; socket and daemon state files absent (sanitized summary retained).
- `codex app-server daemon version` → connection error to absent socket.
- `codex remote-control start --json` → failed: required standalone managed install is absent; no daemon started.

Sanitized command evidence is retained under `P0_EVIDENCE_20260810_0D/environment/` and `P0_EVIDENCE_20260810_0D/transport/`.

## Required product degradations / prohibitions

- Do not enter Phase 1 or create formal UI/production transport.
- Do not claim Desktop runtime monitoring, active-thread observation, passive approval visibility, reconnect, or authoritative live account/quota/Usage/session-token data.
- Keep the yellow `WAITING_APPROVAL` state and approval notification disabled. Never infer approval from inactivity or timeouts.
- Do not use a Monitor-owned stdio/unix app-server, `thread/start`/`thread/resume`, screen scraping, JSONL tailing, credentials, or a private backend as a substitute for C.
- Do not install, replace, kill, restart, or otherwise take ownership of Codex Desktop to make this test pass.

## Go / No-Go

**NO-GO.** The failed official managed-daemon start left the supported socket unavailable, and the essential secondary-client observation of a Codex Desktop-created Turn is still **NOT TESTED**. Per the hard P0 gate, Phase 1 remains unauthorized.

## Next step

Stop after Phase 0D. The only permissible continuation is a separate review: **GPT-5.6 Sol / High — Phase 0E Revalidation Review**. It must not promote A or B to C and must retain NO-GO unless live, passive secondary observation of a Codex Desktop-created Turn is evidenced.
