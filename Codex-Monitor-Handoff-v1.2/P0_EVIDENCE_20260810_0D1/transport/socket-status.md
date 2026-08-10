# Control socket status (sanitized)

- Candidate: `<CODEX_HOME>/app-server-control/app-server-control.sock`.
- Status after managed start: present and identified as a Unix socket.
- Mode: owner read/write only (`srw-------`).
- P0Probe `status`: present; policy remains `do_not_start_or_restart_daemon`.
- The Probe completed a local RFC 6455 WebSocket HTTP Upgrade, `initialize`, `initialized`, and read-only snapshot sequence over this socket.
