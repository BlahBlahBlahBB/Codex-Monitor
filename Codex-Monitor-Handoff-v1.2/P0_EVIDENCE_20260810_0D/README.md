# Phase 0D sanitized evidence

This folder contains only sanitized P0 revalidation evidence captured on 2026-08-10.

- No credentials, auth files, tokens, cookies, full paths, account identifiers, thread identifiers, prompts, or message contents are retained.
- `remote-control start` was attempted only after read-only diagnostics established that no managed daemon was running. It did not start a daemon because the installed ChatGPT.app CLI requires a standalone managed install that is not present.
- No independent `codex app-server --listen unix://...` instance was started: it would not prove observation of Codex Desktop-created Turns.
- No socket transport, WebSocket upgrade, JSON-RPC initialize lifecycle, normal read, or event capture occurred because the official control socket remained absent.

See `../P0_REPORT_REVALIDATION_DRAFT.md` for the gate decision and `../PHASE_0D_REPORT.md` for the execution report.
