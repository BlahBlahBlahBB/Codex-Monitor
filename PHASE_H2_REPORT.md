# PHASE_H2_REPORT

```text
Phase: H2 — Terra / High — Transport Adapters & Owned Runtime Supervisor
Date: 2026-08-10
Start commit: ceb19b316d99cee58038c955f0d5857c1004199a
Release maturity: INTERNAL / DEVELOPER ONLY
Selected forward transport: Unix-socket WebSocket
```

## Result

**COMPLETE — STOP BEFORE H2R/H3**

H2 implements the selected local Unix-socket WebSocket transport boundary and no other endpoint type. It validates an explicit socket path with `lstat`, Unix-domain-socket type, expected owner UID, and no group/world write permission before a `NWConnection` is created. H2 does not discover a socket path, scan the filesystem, open a real Codex connection, or retain a raw path in diagnostics.

The JSON-RPC client now performs the required per-connection `initialize` request followed by `initialized`, correlates responses by request id, routes notifications to one source-local handler, and creates a fresh connection epoch when a closed low-level connection is opened again. Reopening does not read prior state, reconstruct active work, recover missed events, reattach an owner UI, or claim any of those behaviors.

## Delivered scope

- `UnixSocketWebSocketChannel`, an injectable channel contract, exact forward transport provenance, local socket security validation, and JSON-RPC message models/routing.
- Source-local `SourceHealth`, explicitly excluded from the live observation boundary.
- Account transport boundary limited to `account/read` routing and discarded/sanitized response confirmation; H4 remains responsible for Account data semantics.
- Monitor-owned runtime notification boundary for only retained H1 lifecycle names. It emits `partial` candidate envelopes carrying their unchanged H1 capability; it does not promote any capability or invoke an H3 reducer.
- Desktop Snapshot boundary with an exhaustive read-only allow-list: `thread/loaded/list`, `thread/list`, and `thread/read(includeTurns: true)`. It exposes no Desktop start/resume/fork/write/lifecycle call or Desktop notification route.
- Monitor-owned supervisor bookkeeping that accepts only a Monitor-runtime provenance and namespace supplied through a `MonitorCreatedThreadReceipt`. It does not create, resume, fork, interrupt, or kill any Thread/process.
- Sanitized diagnostics that retain allowed method/field names only and exclude payload values, text/content, tokens, secrets, credentials, e-mail, previews/titles, and socket paths.

## Capability and safety boundary

The H1 capability baseline is unchanged: no real capability is promoted to `liveAuthoritative`. In particular, H2 does not enable approval/`WAITING_APPROVAL`, Session Token display, live multi-Thread aggregation, real FAILED/INTERRUPTED projection, active recovery/reconstruction, Desktop realtime, reset mutation, persistence/SQLite, UI, or H3 reduction.

Historical AR-P0 transport evidence remains unchanged as `unresolved/inconsistent: loopback-IP WebSocket or Unix-socket WebSocket`. H2 records `Unix-socket WebSocket` solely as the forward implementation decision.

The official OpenAI app-server documentation was checked for the H2 handshake and transport facts: Unix sockets use WebSocket over the HTTP Upgrade handshake; clients must send `initialize` then `initialized` once per connection. The project remains internal/developer only and does not treat this as a production maturity promotion.

## Verification

```text
$ env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-monitor-h2-module-cache swift build
Build complete! (0.79s)

$ env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-monitor-h2-module-cache swift test
Executed 36 tests, with 0 failures (0 unexpected)

$ git diff --check
exit 0
```

The 9 H2 transport tests cover fixture transport routing, initialize/initialized handshake, out-of-order request/response correlation, notification routing, source-health isolation, Account boundary response discard, supervisor ownership rejection, Desktop read-only prohibition, Future Observer no-data, sanitizer behavior, and forward transport provenance. No real socket or Codex lifecycle operation was run.

## Stop condition

**STOP — H2 complete. Do not begin H3.**

下一阶段建议：GPT-5.6 Sol / High — H2R Transport/Lifecycle/Security Review
