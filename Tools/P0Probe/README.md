# Codex Monitor P0 Probe

Disposable Phase 0B diagnostic tooling only. It is not production transport code and
must not be used to start, restart, stop, or otherwise take ownership of Codex.

## Safety rules

- The probe requires a pre-existing Unix control socket; it never starts a daemon.
- It sends no request before the `initialize` / `initialized` lifecycle has completed.
- It has no approval accept/decline path and must disconnect if passive observation is
  not supported.
- It does not implement reset-credit consumption.
- `export_fixture` sanitizes before writing and is intended for synthetic test inputs
  or already-authorized, in-memory protocol observations only.

## Commands

```sh
python3 -m unittest Tools/P0Probe/test_p0_probe.py
python3 Tools/P0Probe/p0_probe.py status --socket /path/to/app-server-control.sock
```

The Phase 0B run on 2026-08-10 did not invoke a live handshake because `codex doctor
--json` reported the supported control socket as absent. That result is reported as
`NOT TESTED`, not converted into a synthetic success.
