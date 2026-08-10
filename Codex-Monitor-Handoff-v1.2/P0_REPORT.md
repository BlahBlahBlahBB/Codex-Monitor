# Codex Monitor P0 Report

Phase: 0C — P0 Final Decision  
Decision date: 2026-08-10  
Reviewer configuration: GPT-5.6 Sol / High  
Git commit: N/A — workspace is not a Git repository  
Evidence under review: `P0_REPORT_DRAFT.md`, `PHASE_0B_REPORT.md`, `P0_EVIDENCE_20260810_0B`, `Tools/P0Probe`

## Final decision

**NO-GO — P0 runtime validation is incomplete. Phase 1 is not authorized.**

The official control socket was reported as absent and the app-server daemon as not running. Consequently, Phase 0B did not establish a supported live connection and did not test Desktop-created Turn observation, passive approval observation, live account/quota/usage responses, identity correlation, or reconnect.

This decision does not lower the P0 evidence standard: schema presence and offline fixtures cannot substitute for live Desktop observer evidence.

## Blocker classification

The missing control socket is classified as an **environment/runtime precondition failure with an officially supported revalidation path**, not as proof of a permanent core-architecture failure.

- What the evidence proves: the required official control-plane endpoint was not available in this run, so live P0 could not begin.
- What the evidence does not prove: whether a supported secondary client can or cannot observe a Desktop-created Turn after the official endpoint is running.
- Current project effect: hard gate failure and **NO-GO**. No Phase 1 work may start.
- Acceptable revalidation: in a separate P0 run, first have Codex Desktop or another documented Codex-owned mechanism expose the official control socket, then perform a direct passive initialize/observer test.
- Core architecture becomes a confirmed hard **NO-GO** if the official runtime cannot expose a supported local observer endpoint, or if a connected secondary client cannot authoritatively observe Desktop-created Turns without credentials, private backends, scraping, log tailing, or ownership/alteration of the task lifecycle.

Starting a Monitor-owned stdio app-server is not equivalent evidence. Codex Monitor must not start, kill, replace, or assume ownership of a Codex-owned daemon merely to appear functional.

## Evidence audit

Accepted evidence:

- Codex CLI `0.147.0-alpha.6.5`, macOS `26.5.2`, and `arm64` were recorded in a redacted inventory.
- Stable-default JSON and TypeScript schemas were generated from the installed Codex binary without `--experimental`.
- The archived v2 JSON aggregate hash was reverified as `7d79fe309dd7520843459070f3884ecf0e39cee2620c1c49aad6efb4eca76ecb`.
- The archived top-level TypeScript index hash was reverified as `1cca50b4003a6661cd211dff7c655ecf03ecfe4c7bba8e72a5bbc9af33ee5086`.
- The evidence directory contains 930 files. The five offline P0Probe unit tests pass.
- No evidence shows credential access, private-backend use, real reset-credit consumption, account mutation, daemon mutation, or UI implementation.

Evidence limitations and corrections:

- The evidence retains only a summarized redacted inventory, not the raw redacted doctor/daemon command transcripts. It therefore supports the reported environment condition but is not a replayable live transport trace.
- `Tools/P0Probe/p0_probe.py` does not implement Unix-socket framing, initialize/initialized, JSON-RPC routing, or event recording. It is a socket-status, sanitizer, sparse-merge, epoch-guard, and fixture-export helper; it cannot establish observer capability.
- There are no live sanitized captures for initialize, account, rate limits, Usage, loaded threads, Desktop Turn events, approval, reset-credit read, account change, or reconnect.
- `P0_EVIDENCE_20260810_0B/schema/method_matrix.md` and `P0_REPORT_DRAFT.md` incorrectly state that `item/commandExecution/requestApproval` and `item/fileChange/requestApproval` are absent. They are present in the generated stable `ServerRequest` union. This correction improves schema accuracy but does not prove passive delivery to a secondary client.
- `thread/unsubscribe` is present while `thread/subscribe` is absent. Schema inspection alone does not establish how an independent client gains observational ownership of a Desktop-loaded thread.

These limitations do not weaken the NO-GO conclusion; they prevent any stronger positive conclusion.

## Core capability decisions

`NOT TESTED` below describes the observed execution state. The gate verdict remains `FAIL` where required proof is absent.

| Gate | Final status | Evidence state and decision |
|---|---|---|
| P0-A Local supported app-server attach | **FAIL** | NOT TESTED: official socket absent; no handshake or initialize trace. |
| P0-B Observe Desktop-created Turn | **FAIL** | NOT TESTED: the mandatory runtime-visibility proof is absent. This alone blocks Phase 1. |
| P0-C Passive approval lifecycle | **FAIL** | NOT TESTED live. Request/resolution types exist in schema, but delivery and passive non-response safety are unproved. |
| P0-D Account read | **PARTIAL** | Stable request/response types exist; no authoritative live response was captured and the archived `Account` type exposes no stable account identifier. |
| P0-E Rate limits and reset-credit read | **PARTIAL** | Exact schema and a generic offline sparse-merge test exist; no live snapshot/update/reset-credit payload. |
| P0-F Account Usage | **PARTIAL** | Exact stable schema exists; backend availability, payload semantics, local-date interpretation, and account correlation are untested. |
| P0-G Thread/session token usage | **PARTIAL** | Exact event shape exists; live delivery, total/last semantics, replay, and thread/turn correlation are untested. |
| P0-H Account change detection | **PARTIAL** | `account/updated` exists in schema; no live account epoch/change behavior was observed. |
| P0-I Safe official active multi-account switching | **FAIL** | No saved-account list/select/switch capability was proved. Login/logout surfaces are not evidence of safe active multi-account switching. Treat as **NOT SUPPORTED for v1**. |
| P0-J Reconnect/reconciliation | **FAIL** | NOT TESTED: no initial connection existed. |

Supporting capabilities:

| Capability | Final status | Basis |
|---|---|---|
| Environment inventory | **PASS** | Redacted binary/version/platform/socket status retained. |
| Stable schema archive | **PASS** | JSON/TS artifacts and hashes verified. Runtime compatibility remains unproved. |
| Offline sanitizer helper | **PARTIAL** | Five synthetic tests pass; it was not exercised on live protocol payloads. |
| Sparse merge helper | **PARTIAL** | Generic nested merge fixture passes; exact live update behavior is untested. |
| Connection epoch guard | **PARTIAL** | Boolean offline guard passes; reconnect/race behavior is untested. |

## Approval yellow-state decision

**The yellow `WAITING_APPROVAL` state cannot be implemented or shipped reliably from the current evidence.**

The stable schema contains authoritative-looking request identities:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `item/permissions/requestApproval`
- `serverRequest/resolved`

The command/file approval params carry `threadId`, `turnId`, and `itemId`, and the resolution notification carries `threadId` and `requestId`. However, P0 did not prove that these server requests are broadcast to a secondary Monitor connection, that resolution is visible there, or that the Monitor may safely leave the request unanswered without stealing or disrupting Desktop ownership.

Required degradation: remove/disable the yellow state and approval notification until a later P0 run proves the full passive request-to-resolution lifecycle. Timeouts, stalled work, item duration, or thread status must not be used to infer approval.

## Usage implementation decision

The stable schema authorizes decoder/fixture exploration only; **no live account Usage value may yet be presented as authoritative**.

Schema-confirmed account Usage fields are:

- Summary: `lifetimeTokens`, `peakDailyTokens`, `longestRunningTurnSec`, `currentStreakDays`, `longestStreakDays`.
- Daily buckets: `startDate`, `tokens`.

Schema-confirmed thread/session fields are:

- Correlation: `threadId`, `turnId`.
- `tokenUsage.total` and `tokenUsage.last`: `totalTokens`, `inputTokens`, `cachedInputTokens`, `cacheWriteInputTokens`, `outputTokens`, `reasoningOutputTokens`.
- `modelContextWindow` when present.

The account daily bucket does **not** expose per-day input/cached/output/reasoning breakdowns in this archived stable schema, and it exposes no authoritative fee/cost field. Therefore:

- `今日费用` and `近30天费用` must remain `$--`.
- Per-day token totals, `今日 token 用量`, and `近30天 token 用量` remain disabled/uncommitted until a live `account/usage/read` validates availability, `startDate` timezone/local-calendar semantics, null/empty behavior, and account correlation.
- Session Token display remains disabled/uncommitted until live `thread/tokenUsage/updated` delivery and cumulative/replay semantics are validated.
- Token usage must never be converted into quota or estimated cost.

## Multi-account switching decision

**Active multi-account switching is not supported for the v1 product on current evidence.**

The stable schema exposes `account/login/start`, `account/login/cancel`, `account/logout`, and `account/updated`. Some login variants are user-mediated; other variants explicitly carry API keys or ChatGPT auth tokens. None of this proves a safe official saved-account list/select/switch flow, and credential-bearing variants are prohibited for Monitor.

The archived `account/read` response exposes account kind and, for ChatGPT, nullable email and plan type, but no stable account identifier. `account/updated` exposes auth mode and plan type, not an account identity. Therefore reliable cross-account history scoping is also unproved.

Required degradation: hide/remove prototype save-account and switch-account actions. Account sign-in or switching, if needed, must be handed off to Codex. Do not merge or persist Usage as cross-account history until live `account/updated` behavior and an authoritative privacy-safe account identity/scoping strategy are validated.

## Required product degradations and prohibitions

- Do not begin Phase 1, formal UI, or production transport.
- Disable/remove `WAITING_APPROVAL` and approval notifications.
- Do not claim live runtime monitoring, Desktop Turn observation, or reconnect support.
- Do not display live account, plan, email, quota, reset-credit, Usage, or Session Token values from schema presence alone.
- Keep all cost fields at `$--`; never estimate cost from tokens.
- Hide active multi-account save/switch UI and hand account operations to Codex.
- Do not merge or label persisted Usage across account changes without an authoritative account-scoping key.
- Do not enable reset-credit consumption; no live read or idempotency/result/refetch proof exists.
- Do not substitute a Monitor-owned stdio server, `thread/resume`, synthetic fixtures, screen/accessibility scraping, continuous JSONL tailing, credential extraction, or private backend calls for Desktop observer evidence.
- Do not modify FROZEN state or safety rules to reduce the gate.

## Acceptable next step

Stop after Phase 0C. Do not enter Phase 1.

A future, separately authorized P0 revalidation may proceed only when the official Codex runtime exposes the documented control socket through a supported Codex-owned path. That run must use a real read-only direct-socket observer probe and prove, in order:

1. direct transport framing and initialize/initialized;
2. loaded-thread discovery and a supported observational attach/reconciliation path;
3. Desktop-created Turn, item lifecycle, terminal state, and thread/turn/item identity correlation;
4. passive approval request and authoritative resolution without Monitor responding;
5. live account, rate-limit, Usage, reset-credit read, and account-change semantics;
6. reconnect, snapshot/event race handling, and stale-epoch rejection.

If the official supported runtime cannot satisfy steps 1–3, the core architecture is a confirmed NO-GO and must be redesigned through a new product/architecture review. No prohibited fallback is acceptable.
