# Managed remote-control daemon result (sanitized)

- `codex remote-control --help` and `codex remote-control start --help` were available in standalone CLI `0.147.0`.
- A sandboxed first start attempt was denied while opening the daemon runtime lock; it did not start a daemon.
- The approved local `codex remote-control start --json` retry created the managed runtime/socket, then reported that remote-control connectivity was errored.
- The resulting official Unix control socket existed and accepted the P0Probe WebSocket upgrade and initialize lifecycle. Local socket reachability, not the failed external remote-control connection, is the transport evidence used in this phase.
