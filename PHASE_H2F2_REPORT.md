# PHASE_H2F2_REPORT

```text
Phase: H2F2 — Terra / High — Protocol Integration Hardening
Date: 2026-08-10
H2F2 start commit: 73613a1ccb41097873203a2d6974e291400bca4e
Previous H2F commit: 73613a1ccb41097873203a2d6974e291400bca4e
End commit: 73613a1ccb41097873203a2d6974e291400bca4e + scoped uncommitted H2F2 working-tree changes
Commit list: no new commit created (user-owned working tree retained)
Release maturity: INTERNAL / DEVELOPER ONLY
Gate: H2FR fixes complete in implementation; DO NOT ENTER H3
```

## Baseline and schema evidence

- `git remote -v`: empty.
- Pinned CLI: `codex-cli 0.147.0`.
- Generated with `codex app-server generate-json-schema --out /private/tmp/codex-monitor-0147-schema --experimental`.
- Generated aggregate schema: `codex_app_server_protocol.schemas.json`, SHA-256 `babfd5c98cd978dd858b4762cdfbc9b941e1a0e4053de0050e4082ae1f075a`.
- Directly inspected: `v1/InitializeResponse.json`, `RequestId.json`, `JSONRPCError.json`, and all seven H2 lifecycle notification schemas.
- Baseline remains `H1Baseline.registry.realLiveAuthoritativeCapabilityCount == 0`.

## H2FR blocker closure matrix

| Blocking fix | Closure |
|---|---|
| Real Unix-domain WebSocket integration | `UnixSocketWebSocketChannel` is Unix-domain only, performs HTTP Upgrade and explicit masked text-frame writes. A real `/private/tmp` Unix listener test exercises bind/listen/connect, Upgrade, two one-message text frames, binary/incomplete policy, close status/reason, and source cleanup. |
| Opaque socket provenance | Removed public path-attestation factories. `OfficialSocketResolver` produces `SocketPathCapability`; `MonitorOwnedLaunchRecord` carries an opaque capability. Endpoint construction accepts only that capability and retains type/UID/mode/parent/symlink/device/inode/reopen checks. |
| Pinned DTO/schema | `RequestID` supports integer/string; error `message` is required; initialize required fields are validated; lifecycle decoder follows each generated top-level parent layout. Nine sanitized generated fixtures cover initialize, all lifecycle events, successful/non-success terminal, and token usage. |
| Exclusive client ownership | Binding includes source, adapter, runtime, account epoch, lifecycle epoch. A permanent unique adapter lease prevents handler replacement. Lifecycle/account crossover and second-adapter attach reject. |
| Non-forgeable receipt | Receipt initializer/token are fileprivate. Boundary-held UUID issuance state validates origin, current connection, runtime, account, and lifecycle context; supervisor derives issuance provenance from current authorized connected context. |
| Closed sanitizer allow-list | Replaced sensitive-fragment blacklist with a closed machine-field set. Unknown keys drop recursively; values never serialize. Sentinel keys and values are scanned in diagnostics and fixtures. |

## Seven required adversarial regressions

| Regression | Permanent coverage |
|---|---|
| Arbitrary socket path cannot self-attest official default | `testSocketProvenanceAndFilesystemReplacementRegressions` verifies no public arbitrary-path resolver and replacement/removal/symlink/owner/mode/parent defenses. |
| Connected exact-match fabricated receipt rejected | Receipt construction is unavailable outside issuance boundary; `register` validates non-reconstructible issuance token and current context. |
| Exact generated successful terminal yields owned candidate | `testPinnedGeneratedFixturesRouteExactParentsAndOnlySuccessfulTerminal`. |
| Client cannot be shared across lifecycle adapters | `testClientLeaseAndEpochBindingRejectLifecycleAndAccountCrossovers`. |
| Generated-valid string server RequestId classification | `testServerRequestContradictionAndMalformedIDAreTypedWireRejections`. |
| Generated-invalid error missing message rejects | Same test. |
| Secret-shaped key cannot serialize | `testSanitizerAndFixturesCannotSerializeSentinels` seeds `sk_live_H2FRSentinel123`, Authorization/Bearer/token/password/e-mail/path/content/title/preview/private-key shaped corpus in keys and values. |

## Verification

```text
swift build
Build complete! (0.11s)

swift test
Executed 42 tests, with 0 failures (0 unexpected)
required tests skipped: 0

git diff --check
exit 0
```

## Boundary audit

- No TCP endpoint or fallback; no filesystem discovery scan.
- Reconnect remains transport-only. Old receiver is cancelled, channel is closed, receiver termination is awaited, then context may be replaced.
- No H3 reducer, UI, SQLite, notification, reset mutation, Desktop lifecycle/process control, recovery/reconstruction, or capability promotion was added.
- Approval, Session Token display, live multi-Thread product projection, failed/interrupted product projection, Desktop realtime, and Future Observer data remain disabled/unvalidated.
- Historical AR-P0 transport evidence remains unchanged. Release remains **INTERNAL / DEVELOPER ONLY**.

## Remaining blockers

No implementation blocker is claimed closed beyond the six authorized H2FR fixes. H3 remains blocked by process pending the independent H2FR2 final transport re-review.

下一阶段建议：GPT-5.6 Sol / High — H2FR2 Final Transport Re-review
