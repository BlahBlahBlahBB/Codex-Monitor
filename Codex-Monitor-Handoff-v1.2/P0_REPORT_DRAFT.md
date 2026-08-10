# Codex Monitor P0 Report — Draft

Phase: 0B — P0 Protocol Validation  
Execution date: 2026-08-10  
Model / reasoning: GPT-5.6 Terra / High  
Git commit: N/A — workspace is not a Git repository  
Overall decision: **NO-GO — P0 is incomplete. Stop before Phase 0C and do not start production UI.**

## Scope and safety result

This run executed only P0 validation and disposable tooling. It did not create UI; start, restart, or stop Codex; create or resume a Turn; trigger approval; change accounts; read credential files; call private backends; or consume a reset credit.

`codex doctor --json` discovered the official socket location and reported its background app-server as not running; the socket was absent. `daemon version` then returned `No such file or directory` for that socket. Per Phase 0A safety rules, the Codex-owned runtime was not altered. No initialize, proxy, normal app-server request, or live event observation was sent.

This does not count as a successful attach. No live observer evidence exists for this machine/run, so mandatory full-v1 P0 gates are not passed.

## Environment and schema evidence

| Item | Result |
|---|---|
| Codex binary | `/Applications/ChatGPT.app/Contents/Resources/codex` |
| Codex version | `0.147.0-alpha.6.5` |
| macOS / CPU | `26.5.2` / `arm64` |
| Codex home | `<HOME>/.codex` |
| Control socket | `<CODEX_HOME>/app-server-control/app-server-control.sock` — absent |
| Daemon/app-server runtime version | NOT AVAILABLE; daemon not running |
| JSON schema | Generated without `--experimental`; v2 SHA-256 `7d79fe309dd7520843459070f3884ecf0e39cee2620c1c49aad6efb4eca76ecb` |
| TypeScript bindings | Generated without `--experimental`; index SHA-256 `1cca50b4003a6661cd211dff7c655ecf03ecfe4c7bba8e72a5bbc9af33ee5086` |
| Schema caveat | Generator command is labelled experimental; generated guardian-approval definitions are explicitly unstable. Neither is adopted as production truth. |

See [`P0_EVIDENCE_20260810_0B/schema/method_matrix.md`](P0_EVIDENCE_20260810_0B/schema/method_matrix.md). The generated schema contains core account/rate-limit/usage/thread/turn/token names and cursor pagination, but `thread/subscribe` and the legacy `item/*/requestApproval` names are absent. Schema presence cannot prove secondary-client observation or passive approval visibility.

## Gates

| Gate | Status | Evidence / required next proof |
|---|---|---|
| P0-A Local app-server attach | **NOT TESTED** | Supported socket absent; daemon was not started. Require a direct Unix-socket handshake. |
| P0-B Observe Desktop-created Turn | **NOT TESTED** | Cannot run without P0-A. No synthetic result substitutes for Desktop runtime evidence. |
| P0-C Approval lifecycle visibility | **NOT TESTED** | Cannot run without P0-A/B and a user-managed harmless approval. Yellow state remains unavailable. |
| P0-D Account read | **NOT TESTED** | Method exists in schema, but no request/capture occurred. |
| P0-E Rate limits | **PARTIAL** | Read/update/reset-credit types exist; offline sparse-merge test passes; no authoritative snapshot. |
| P0-F Account usage | **PARTIAL** | Usage types exist; no live payload, time-zone/date semantics, or fee field observed. |
| P0-G Thread token usage | **PARTIAL** | Event type exists; correlation, cumulative/delta, and replay are untested. |
| P0-H Account change detection | **NOT TESTED** | Notification exists in schema; no user-driven change observed. |
| P0-I Safe official active switching | **NOT TESTED** | No live official flow; no credential-bearing surface was invoked. |
| P0-J Reconnect | **NOT TESTED** | No connection existed; no restart or sleep/wake was induced. |

## P0 step matrix

| Step | Status | Result |
|---:|---|---|
| 1 Environment inventory | **PASS** | Binary, version, help, doctor, architecture, and redacted runtime status captured. |
| 2 Stable schema generation | **PARTIAL** | JSON/TS produced from tested binary without `--experimental`; generator/runtime compatibility remains unproven. |
| 3 Local transport discovery | **PASS** | Official candidate discovered through doctor; socket absent and daemon not running. |
| 4 Initialize probe | **NOT TESTED** | No socket; no daemon mutation performed. |
| 5 Account read | **NOT TESTED** | No initialized transport. |
| 6 Rate-limit read | **NOT TESTED** | No initialized transport. |
| 7 Sparse rate-limit update | **PARTIAL** | Schema specifies merge/refetch; offline generic sparse-merge test passes. No live notification. |
| 8 Account usage | **NOT TESTED** | No live request, date/time-zone, or fee evidence. |
| 9 Loaded threads / pagination | **NOT TESTED** | Cursor type exists; live response/reconciliation untested. |
| 10 Desktop-created Turn | **NOT TESTED** | Mandatory runtime-visibility proof unavailable. |
| 11 Thread status | **NOT TESTED** | No live notification. |
| 12 Item mapping | **NOT TESTED** | No lifecycle capture; no reasoning/command/file content retained. |
| 13 Thread token usage | **NOT TESTED** | No live event. |
| 14 Passive approval visibility | **NOT TESTED** | No approval triggered; probe has no accept/decline path. |
| 15 Terminal mapping / retention | **NOT TESTED** | No terminal events; no UI/state engine built. |
| 16 Multi-thread / race / epochs | **PARTIAL** | Offline stale-connection epoch guard passes; no live ordering/concurrency evidence. |
| 17 Reset-credit read | **NOT TESTED** | No live rate-limit response. |
| 18 Reset consume safety | **NOT TESTED** | Never invoked; real credit consumption is prohibited. |
| 19 Account change / history scoping | **NOT TESTED** | No account change or credential flow invoked. |
| 20 Reconnect / backpressure | **PARTIAL** | Offline stale-epoch guard passes; reconnect and backpressure remain untested. |
| 21 Sanitizer | **PASS** | Five unit tests pass; fixture redacts credentials, PII, commands, paths, and content fields while retaining numeric token counts. |
| 22 Report / hard-gate decision | **PASS** | Each result is recorded without promoting unavailable evidence to PASS. |

## Probe, fixtures, and tests

Created only in the workspace: `Tools/P0Probe/` (disposable probe + five unit tests) and `P0_EVIDENCE_20260810_0B/` (generated schemas, redacted inventory, method matrix, and synthetic sanitizer fixture).

Executed `python3 -m unittest Tools/P0Probe/test_p0_probe.py`: **5 tests passed**. The sanitizer fixture is synthetic, not a live protocol capture. No OAuth token, refresh token, API key, Authorization header, cookie, email, account ID, message, title, command, home path, or file content was written to evidence/report payloads.

## Required product degradations / prohibitions

- No production UI or Phase 1 work: P0-A and P0-B did not pass.
- No yellow `WAITING_APPROVAL` state: it lacks passive authoritative evidence.
- No active account-switching flow: credential-bearing login variants must not be used.
- No token, quota, account-usage, reset-credit, or account display claim from schema presence alone.
- No reset-credit consume test and no local-decrement success assumption.

## Go / No-Go

**NO-GO.** Supported local connection, Desktop-created runtime visibility, identity/event correlation, and reconnect have not passed. Do not substitute credential extraction, private backend endpoints, screen scraping, JSONL tailing, guessed approval state, or a Monitor-owned task lifecycle.

To resume P0 in a separately authorized run, Codex Desktop must already expose a running supported app-server socket. The next run must start with direct passive handshake, then user-coordinated harmless Desktop Turn and approval observation. It must still not spend a reset credit.
