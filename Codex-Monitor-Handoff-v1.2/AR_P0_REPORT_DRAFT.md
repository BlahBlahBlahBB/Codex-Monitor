# AR-P0 Report Draft — Hybrid Capability Validation

Phase: AR-P0 — Terra / High  
Date: 2026-08-10  
Architecture baseline: 14_ARCHITECTURE_REVISION_HYBRID_V1.md  
Scope: disposable probes, sanitized fixtures, and evidence only.

## Executive result

| Gate | Result |
|---|---|
| AR-P0-A Account semantics | **PARTIAL** |
| AR-P0-B Monitor-owned runtime | **PARTIAL** |
| AR-P0-C Desktop read-only snapshot | **PARTIAL** |
| AR-P0-D Transport support / maturity | **PASS** |
| AR-P0-E Reset mutation | **NOT RUN** |

The Hybrid v1 split is evidence-backed: Account snapshots, Monitor-owned realtime events, and Desktop read-only snapshots are separate capabilities. Desktop snapshots were not promoted to realtime. Owned-runtime core lifecycle succeeded, but the complete realtime contract remains incomplete.

## Evidence

- AR_P0_EVIDENCE_20260810_01/sanitized/probe_summary.json records only field shapes, event methods, correlation booleans, and salted digests.
- AR_P0_EVIDENCE_20260810_01/environment/runtime_transport.md records the sanitized transport inventory.
- AR_P0_EVIDENCE_20260810_01/fixtures/owned_runtime_failed_terminal_fixture.json is explicitly mock-only.
- AR_P0_CAPABILITY_MATRIX.json contains the field-level capability verdicts.

## AR-P0-A — Account semantics: PARTIAL

Live snapshots succeeded for account/read, account/rateLimits/read, and account/usage/read.

- Account shape contained email, planType, type, and requiresOpenaiAuth. Values were not retained. No non-secret stable discriminator was proved; email is not promoted to a stable key.
- Dynamic rate-limit data contained rateLimits/rateLimitsByLimitId, primary usedPercent, numeric resetsAt, windowDurationMins, plus reset-credit availableCount/credits shape. Secondary was null in the captured snapshot.
- Usage contained summary and dailyUsageBuckets with startDate:string and tokens:number. No authoritative cost field was present, so cost remains unavailable.
- A rate-limit update notification was observed, but no controlled transition was captured; sparse-update semantics remain unvalidated and full refetch remains required.
- Daily-bucket timezone/null behavior, account changes/switching, and reset consumption remain unvalidated.

## AR-P0-B — Monitor-owned runtime: PARTIAL

The probe started an independent owned app-server runtime, assigned source/runtime identity in memory, and created only new ephemeral owned Threads and Turns.

Proved:

- thread/started, thread/status/changed, turn/started, turn/completed, item/started, item/completed, and thread/tokenUsage/updated were captured.
- 141 Thread-correlated events had zero mismatches against the owned set.
- Item lifecycle covered commandExecution, agentMessage, reasoning, and userMessage. Only type was retained; hidden reasoning, commands, paths, and content were withheld.
- Two owned Threads were exercised without crossover; four completed successful terminal outcomes were captured.
- Closing the first client did not terminate the owned runtime. A new client initialized and completed thread/loaded/list.

Not proved:

- Safe interruption raced terminal completion; no interrupted terminal was captured.
- No controlled real failed terminal was captured. The fixture cannot upgrade this capability.
- No approval request or serverRequest/resolved was captured. The probe did not approve or decline.
- Reattachment proved a snapshot/list boundary only. Active reconstruction and owner-UI exit survival are unvalidated. The ephemeral owned Thread could not be read on the replacement connection.

Conclusion: core owned lifecycle did not fail. Its captured success/correlation/item/token capabilities are live-authoritative, but no composite full-realtime claim is allowed.

## AR-P0-C — Desktop read-only snapshot: PARTIAL

Only the three approved operations were used through the documented local proxy:

- thread/loaded/list
- thread/list
- thread/read(includeTurns:true)

thread/list returned 50 stored summaries. Three sanitized history reads succeeded. thread/loaded/list returned no loaded Threads, and before/after salted digests were unchanged. The captured source classification does not prove that a result is an ordinary Codex Desktop Chat.

The only permitted product meaning is snapshot/history with explicit last refresh and non-live labeling. No Desktop Thread was resumed, started, or forked. This evidence cannot infer WORKING, THINKING, approval, current activity, token usage, terminal timing, or recovery.

## AR-P0-D — Transport support / maturity: PASS

The installed standalone CLI is 0.147.0. Installed help advertises stdio, loopback WebSocket, Unix socket, and off transports. The owned-runtime probe used app-server WebSocket; Desktop snapshot reads used the documented app-server proxy.

Official OpenAI documentation says thread/start automatically subscribes its creator, while thread/read reads without resuming/subscribing. It also says the app-server command and WebSocket transport are experimental and unsupported for production workloads. See [Codex App Server documentation](https://developers.openai.com/codex/app-server).

This is acceptable only for Internal/Developer validation. It is a Public Hybrid v1 release blocker/warning.

## AR-P0-E — Reset mutation: NOT RUN

No account/rateLimitResetCredit/consume request was sent. No reset credit was consumed. The production mutation remains disabled.

## Safety and stop condition

- No H1, old Phase 1, formal UI, production Transport/Domain/SQLite module, private backend, credential extraction, scraping, or JSONL tailing occurred.
- No Desktop lifecycle operation was used.
- No approval response was sent.
- No raw account value, identity, title, preview, prompt, command, path, credential, or raw JSON-RPC payload was retained.

AR-P0 ends here. Do not start H1.

下一阶段建议：GPT-5.6 Sol / High — AR-P0 Decision Review

