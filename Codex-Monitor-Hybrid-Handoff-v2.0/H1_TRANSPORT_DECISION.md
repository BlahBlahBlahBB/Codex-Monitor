# H1 Transport Decision

> Decision scope: a single proposed local transport for a later authorized H2 implementation. H1 does not implement, open, probe, or validate this transport.

## Decision

If H2 is explicitly authorized after H1R, its only candidate local app-server transport is:

```text
Unix-socket WebSocket
```

This is the exact transport label used for the H1 decision. It replaces neither the AR-P0 evidence label nor the release-maturity restriction. Retained AR-P0 evidence did not consistently identify whether its owned probe used loopback-IP WebSocket or Unix-socket WebSocket; this decision must not be reported as a fact about that probe.

## Why this transport

1. It preserves a local-only boundary without exposing an app-server listener on a TCP interface.
2. Unix filesystem ownership and permissions offer a clearer owner-only access boundary than a loopback port, subject to H2 validation of the actual socket path and permissions.
3. It matches the architecture's local control-plane model while keeping Account, Monitor-owned Runtime, Desktop Snapshot, and Future Observer capability decisions independent of transport availability.
4. It avoids manufacturing a passive Desktop observer path: transport reachability does not authorize Desktop live state, approval visibility, token correlation, or lifecycle ownership.

## Lifecycle assumptions to validate before use

H2 may not assume any of the following; it must validate and retain evidence for each applicable item:

| Assumption to validate | Required H2 outcome |
|---|---|
| Socket discovery | Obtain the path from an official/local supported mechanism; do not scan arbitrary filesystem locations or scrape credentials/configuration. |
| Ownership/permissions | Confirm the path is local, owned by the current user or expected service principal, and not group/world writable beyond the documented service contract. |
| Socket lifetime | Detect socket replacement/removal and scope connection epochs accordingly. |
| Connection lifetime | Establish initialize/close behavior without treating reconnect as runtime reconstruction. |
| Process ownership | Monitor never kills Codex Desktop or a Desktop-owned runtime. A Monitor-owned runtime lifecycle requires its own separate proof. |
| Message boundary | Validate WebSocket framing, initialization, capability probing, and unsubscribe/closure behavior using only supported operations. |
| Failure behavior | Source-local failure becomes unavailable/stale as applicable; it does not imply task failure, Desktop `IDLE`, or a fake recovery. |

## Security and privacy assumptions

- The socket is a local control channel, not a network service. H2 must reject non-Unix-socket endpoints for this Adapter path.
- No credentials, authorization headers, raw secrets, or full private payloads are persisted in diagnostics or fixtures.
- Socket path and permission diagnostics are sanitized. A path may be treated as sensitive environmental metadata when emitted outside developer diagnostics.
- The Monitor uses only documented/stable methods authorized by the current phase. It does not access private endpoints, screen/accessibility data, continuous JSONL files, or credentials.
- Transport success proves only a connected source. Capability states remain separate and start at the H1 baseline.

## Capability and release consequences

```text
H1 transport decision  ≠ transport validation
transport validation   ≠ production support maturity
transport connectivity ≠ runtime observability
account connectivity   ≠ runtime availability
Desktop snapshot read  ≠ Desktop live observation
```

The official maturity boundary remains experimental/unsupported for production workloads. Therefore the release is still **INTERNAL / DEVELOPER ONLY**. This decision does not authorize H2, public/beta positioning, reconnect/reconstruction, or any unvalidated capability.

## H2 entry gate

H2 may begin only after an H1R Architecture Review explicitly authorizes it. At that point, the selected transport must be implemented as a source-local Adapter transport only, with its validation results recorded against the assumptions above. Any inability to prove the local path, ownership, permissions, or supported behavior is a stop/report condition, not a reason to fall back to loopback TCP, a Desktop observer workaround, or private discovery.
