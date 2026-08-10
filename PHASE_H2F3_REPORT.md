# PHASE_H2F3_REPORT

```text
Phase: H2F3 — Terra / High — Final Transport Closure
Date: 2026-08-10
Start commit: 16fbfc79086a241380596110e4b46244d341078e
End commit: H2F3 scoped local commit (this report is included in that commit)
Release maturity: INTERNAL / DEVELOPER ONLY
Gate: H2FR2 fixes implemented; DO NOT ENTER H3
```

## Frozen baseline

- `git remote -v`: no remotes.
- Pinned CLI: `codex-cli 0.147.0`.
- Regenerated via `codex app-server generate-json-schema --experimental`.
- Aggregate schema SHA-256: `babfd5c98cd978dd858b4762cdfbc9fba941e1a0e4053de0050e4082ae1f075a`.
- Baseline real `liveAuthoritative` capability count remains `0`.

## Files changed

- `Sources/CodexMonitorContracts/Transport.swift`
- `Sources/CodexMonitorContracts/TransportAdapters.swift`
- `Sources/CodexMonitorContracts/RuntimeSupervisor.swift`
- `Sources/CodexMonitorContracts/CoreTypes.swift`
- `Tests/CodexMonitorContractsTests/TransportAdaptersTests.swift`
- `PHASE_H2F3_REPORT.md`

## Five-blocker closure matrix

| Blocker | Closure evidence |
|---|---|
| RFC6455 Unix WebSocket | Production AF_UNIX/SOCK_STREAM path now sends a random 16-byte Base64 key, validates `101`, `Upgrade`, tokenized `Connection`, and SHA-1 `Sec-WebSocket-Accept`. The real listener reads Upgrade and two masked opcode `0x1` frames, validates frame boundaries/payload decoding, preserves close status/reason, rejects invalid/missing headers, and exercises a non-FIN real fragment. Socket receive runs off-actor; close uses `shutdown` to unblock it before reconnect can continue. |
| Socket provenance issuance | The official issuer has no path input and resolves the CLI 0.147.0 daemon control socket at `~/.codex/app-server-control/app-server-control.sock`. Test-only paths emit `.testHarness`, never official provenance. Monitor-owned capability records require an actually launched `Process` still running plus post-launch filesystem validation; raw runtime ID/path minting no longer exists. Existing type/owner/mode/parent/symlink/inode replacement checks remain. |
| Pinned 0.147.0 DTOs | The generated-equivalent validator now checks Initialize, RequestId/error behavior, Thread, Turn status/items, all 18 tagged ThreadItem variants, commandExecution required fields and enums, tokenUsage, and the seven lifecycle layouts. Generated fixtures pass; `items: true`, invalid turn status, incomplete commandExecution, and invalid tokenUsage reject. Only an exact successful terminal can become a candidate. |
| Supervisor receipt origin | Receipt issuance has no Thread-ID path. The adapter performs authorized `thread/start`, validates the authoritative returned Thread, produces opaque one-time creation result state, and the supervisor consumes it once against the current connected context before registration. Disconnected and non-result issuance reject. |
| SourceHealth/provenance sanitizer | `SourceHealth` transitively serializes the unified Provenance/Evidence encoded-output boundary. Raw IDs become SHA-256-derived opaque tags; evidence fields encode only closed vocabulary; freshness reasons do not serialize. Diagnostics retain the closed field-name allow-list. Seeded secret/path/e-mail/content/title/preview corpus is asserted absent from diagnostics, provenance, evidence, SourceHealth, and fixtures. |

## Area 4 regression

Exclusive client ownership was not redesigned. Existing lease/binding regression remains green: a second adapter cannot replace the handler; account/lifecycle crossovers reject; old connection context cannot relabel traffic.

## Verification

```text
swift build
Build complete! (0.10s)

swift test
Executed 46 tests, with 0 failures (0 unexpected)
required tests skipped: 0

git diff --check
exit 0
```

## Boundary audit

- No H3 reducer/UI/SQLite/notification/reset mutation was added.
- No capability was promoted; baseline real `liveAuthoritative` remains zero.
- Desktop remains snapshot-only; Future Observer remains zero-data; approval/session token/live multi-Thread/failed-interrupted projection/reconnect reconstruction remain disabled.
- Historical AR-P0 evidence is unchanged. Release remains **INTERNAL / DEVELOPER ONLY**.

## Remaining blockers

No H2F3 implementation blocker is claimed remaining. H3 remains prohibited pending the independent H2FR3 transport gate review.

下一阶段建议：GPT-5.6 Sol / High — H2FR3 Transport Gate Review
