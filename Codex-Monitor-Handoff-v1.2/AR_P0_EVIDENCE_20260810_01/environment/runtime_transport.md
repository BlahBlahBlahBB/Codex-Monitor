# AR-P0 runtime and transport inventory (sanitized)

Captured 2026-08-10 for disposable capability validation.

- Standalone CLI: codex-cli 0.147.0.
- Installed app-server help exposes stdio, Unix socket, WebSocket, and off listener forms.
- The disposable Monitor-owned runtime was started independently of Codex Desktop, assigned in-memory sourceID/runtimeInstanceID, and connected through a Unix-socket WebSocket listener.
- A client disconnect left that owned runtime process alive; a new client completed initialize and thread/loaded/list.
- The managed Desktop control socket was accessed only through codex app-server proxy; the probe used WebSocket Upgrade plus the three permitted read methods.

No socket paths, identifiers, account values, prompts, thread content, command text, credentials, or raw JSON-RPC payloads are retained.

