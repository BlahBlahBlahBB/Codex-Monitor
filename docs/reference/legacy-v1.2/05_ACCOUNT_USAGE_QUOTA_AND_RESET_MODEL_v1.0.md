# Codex Monitor — Account, Usage, Quota & Reset Model v1.0

> Status: **Draft for technical validation**
> Platform: macOS
> Depends on: `04_STATE_ENGINE_AND_EVENT_MAPPING_v1.1_FROZEN.md`
> Primary integration: Codex app-server stable JSON-RPC surface
> Storage: local SQLite, persistent until the user explicitly clears data

---

## 1. Scope

This document defines the data model and refresh strategy for:

- active Codex account
- plan/account type
- quota windows
- Floating Orb remaining percentage
- quota reset times
- earned rate-limit reset credits
- “立即重置”
- account-level Token usage
- per-thread Token usage
- 30-day Usage chart
- locally persisted Usage history
- stale/offline behavior
- account change behavior

This is deliberately separate from the runtime state engine. A task can be `WORKING`
while quota data is stale, or `IDLE` while quota data is fresh.

---

## 2. Source-of-Truth Rules

### 2.1 Account identity

Primary source:

```text
account/read
account/updated
```

For a ChatGPT-backed account, use only fields returned by Codex, such as:

```text
email
planType
authMode
```

Do not infer a plan from quota sizes.

### 2.2 Quota / rate limits

Primary source:

```text
account/rateLimits/read
account/rateLimits/updated
```

`usedPercent` is authoritative for the reported quota window.

Do **not** calculate quota usage from local Token totals.

### 2.3 Account usage history

Primary source:

```text
account/usage/read
```

It is the preferred source for the Usage page’s account-level Token activity and
daily buckets whenever available.

### 2.4 Current thread/session Token usage

Primary source:

```text
thread/tokenUsage/updated
```

This is independent from account quota percentage.

### 2.5 Earned reset credits

Primary source:

```text
account/rateLimits/read
```

Consumption:

```text
account/rateLimitResetCredit/consume
```

After any consume result that may have changed server state, refetch
`account/rateLimits/read`.

---

## 3. Normalized Account Model

```swift
struct AccountSnapshot: Sendable, Codable {
    var authMode: AuthMode?
    var accountKind: AccountKind
    var email: String?
    var planType: String?

    var requiresOpenAIAuth: Bool

    var fetchedAt: Date
    var isStale: Bool
}

enum AccountKind: String, Codable {
    case chatGPT
    case apiKey
    case personalAccessToken
    case amazonBedrock
    case localOrOther
    case unknown
}
```

Display rules:

- Full email by default.
- If `Hide Account Info` is enabled, mask the account identity in all Monitor UI.
- If email is unavailable, do not manufacture one.
- Show plan label only when Codex reports it.
- Never display or persist OAuth tokens, access tokens, refresh tokens, API keys, or
  other Codex secrets.

---

## 4. Dynamic Quota Window Model

Do not hard-code “5 hour” + “weekly”.

Codex may return:

```text
primary
secondary
```

and either one may be absent. Window configuration can change by plan/backend.

Normalize every returned window into:

```swift
struct QuotaWindow: Sendable, Codable, Identifiable {
    var id: String
    var sourceSlot: SourceSlot       // primary / secondary / future slot
    var usedPercent: Double
    var remainingPercent: Double
    var windowDurationMinutes: Int?
    var resetsAt: Date?
    var reachedType: String?
    var fetchedAt: Date
}

enum SourceSlot: String, Codable {
    case primary
    case secondary
    case other
}
```

Normalization:

```text
remainingPercent = clamp(100 - usedPercent, 0...100)
```

Window display label:

```text
if duration is known:
    format duration naturally
else:
    “用量限额”
```

Examples:

```text
300 min   -> 5 小时
10080 min -> 1 周
43200 min -> 30 天
```

These labels are presentation only. Logic must not depend on the label.

---

## 5. Floating Orb Percentage — FROZEN RULE

The center percentage is the remaining percentage of the **most constrained
currently reported quota window**.

```text
orbRemaining =
    min(all authoritative remainingPercent values)
```

Example:

```text
primary remaining   = 78%
secondary remaining = 42%
orb                  = 42%
```

If only one window exists:

```text
orb = that window’s remainingPercent
```

If no authoritative rate-limit window exists:

```text
connected + no supported quota data -> `--`
disconnected                       -> `--`
paused                             -> retain last known % but mark data stale
```

Important:

- The ring color still represents Codex runtime state.
- The center number represents quota remaining.
- Low quota does **not** turn the state ring yellow/red.

---

## 6. Rate-Limit Snapshot Merge

`account/rateLimits/updated` is a **sparse rolling update**.

Therefore:

```text
NEVER:
newSnapshot = sparseNotification

ALWAYS:
newSnapshot = merge(lastFullSnapshot, sparseNotification)
```

Rules:

1. Missing fields in an update mean “not supplied”, not “clear the old value”.
2. Nullable account metadata in a sparse update must not erase the last known value
   unless the protocol explicitly says the null is authoritative.
3. On ambiguous merge state, perform `account/rateLimits/read`.
4. Persist the merged authoritative snapshot only after validation.

Recommended type:

```swift
actor RateLimitStore {
    private var fullSnapshot: RateLimitSnapshot?

    func replaceWithFullSnapshot(_ snapshot: RateLimitSnapshot)
    func mergeSparseUpdate(_ update: RateLimitSparseUpdate)
}
```

---

## 7. Earned Reset Credit Model

Normalized model:

```swift
struct ResetCreditSummary: Sendable, Codable {
    var availableCount: Int
    var credits: [ResetCreditDetail]?
    var fetchedAt: Date
}

struct ResetCreditDetail: Sendable, Codable, Identifiable {
    var id: String
    var resetType: String?
    var status: String?
    var grantedAt: Date?
    var expiresAt: Date?
    var title: String?
    var description: String?
}
```

Important protocol semantics:

```text
credits == nil
    -> backend supplied count but not detailed rows

credits == []
    -> detailed fetch succeeded and no available rows were returned

availableCount
    -> authoritative total count
```

The detail array can be capped by the backend. Therefore:

```text
credits.count MUST NOT replace availableCount
```

Usage page top-level display:

```text
0 次可用
1 次可用
2 次可用
```

If detailed expiry is available, it may be shown in a deeper detail view. Do not invent
expiry when the backend supplies only the count.

---

## 8. “立即重置” Transaction

This is an explicit state-changing operation.

### 8.1 Preconditions

Enable the button only when:

```text
connected
AND authenticated ChatGPT rate-limit surface is available
AND availableCount > 0
AND not currently submitting another reset
```

### 8.2 Confirmation

Before consumption, show a native macOS confirmation dialog.

Suggested content:

```text
使用 1 次限额重置额度？

这会立即消耗 1 次可用重置额度，并重置符合条件的 Codex 用量限额。
```

Buttons:

```text
取消
立即重置
```

Destructive styling should be restrained; this is consumption of a scarce credit, not
data deletion.

### 8.3 Idempotency

For each logical redemption attempt:

```text
idempotencyKey = UUID()
```

If a network retry is required for the **same** logical attempt:

```text
reuse the same idempotencyKey
```

Never create a new UUID merely because the transport timed out.

### 8.4 Response mapping

```text
reset
    -> success

alreadyRedeemed
    -> idempotent success

nothingToReset
    -> no eligible quota window currently requires reset

noCredit
    -> no earned reset credit available
```

### 8.5 Mandatory refetch

After:

```text
reset
alreadyRedeemed
nothingToReset
noCredit
```

perform:

```text
account/rateLimits/read
```

Do not decrement `availableCount` locally and assume the backend state.

---

## 9. Account-Level Usage Model

The visual Usage page is frozen around:

```text
今日费用
近 30 天费用
今日 token 用量
近 30 天 token 用量
30-day daily chart
```

Internal normalized model:

```swift
struct AccountUsageSnapshot: Sendable, Codable {
    var today: UsageAggregate
    var last30Days: UsageAggregate
    var daily: [DailyUsage]
    var fetchedAt: Date
    var isStale: Bool
}

struct UsageAggregate: Sendable, Codable {
    var inputTokens: Int64?
    var cachedInputTokens: Int64?
    var outputTokens: Int64?
    var reasoningOutputTokens: Int64?
    var totalTokens: Int64?

    // only authoritative values:
    var costUSD: Decimal?
}

struct DailyUsage: Sendable, Codable, Identifiable {
    var id: String              // local calendar date key
    var date: Date
    var inputTokens: Int64?
    var cachedInputTokens: Int64?
    var outputTokens: Int64?
    var reasoningOutputTokens: Int64?
    var totalTokens: Int64?
    var costUSD: Decimal?
}
```

### Protocol-schema caution

The app-server README currently documents `account/usage/read` as returning an
account token-activity summary and daily buckets, but the README does not fully spell
out every response field in the account section.

Therefore P0 implementation must:

1. generate the stable app-server JSON/TS schema from the installed Codex build;
2. inspect the exact `account/usage/read` response type;
3. map only fields that actually exist;
4. preserve unknown/unsupported values as `nil`.

Do not design production decoding around guessed fields.

---

## 10. Cost Display Rule — FROZEN

Cost must be authoritative.

```text
if authoritative cost exists:
    show "$77.53"

if authoritative cost does not exist:
    show "$--"
```

Do **not** calculate:

```text
token count × public model price
```

for the Usage page.

Reasons:

- quota and credits are not equivalent to raw Token count;
- model/routing/fast-mode/account pricing can change;
- cached/input/output/reasoning components may have different accounting semantics;
- the UI must not present an estimate as an account charge.

If a future version adds estimated cost, it must be explicitly labeled `估算`, and is out
of scope for v1.

---

## 11. Token Display Formatting

Chinese UI:

```text
0          -> 0 token
842        -> 842 token
12,800     -> 1.28万 token
6,243,800  -> 624.38万 token
133,000,000-> 1.33亿 token
```

English UI:

```text
842
12.8K
6.24M
133M
```

Tooltip / detail:

```text
exact integer with separators
```

Example:

```text
133,024,981 token
```

Do not round the stored value; round only for presentation.

---

## 12. 30-Day Chart — FROZEN

Always display the most recent **30 local calendar days**, including zero-use days.

Algorithm:

```text
1. Determine today using the user's current Calendar/time zone.
2. Build a 30-date sequence [today-29 ... today].
3. Index authoritative daily buckets by local date.
4. Left join buckets onto the 30-date sequence.
5. Missing day -> zero-height bar.
```

Never compress the chart to “30 days that had usage”.

Tooltip:

```text
2026年8月7日
Token：6,243,800
费用：$4.21
```

If cost unavailable:

```text
费用：$--
```

Chart axis endpoints use the actual first/last date in the 30-day sequence.

---

## 13. Current Session Token Usage

Source:

```text
thread/tokenUsage/updated
```

Used by:

- Single-click Quick View
- current session diagnostics
- local session history

Do not substitute the account-level 30-day total.

Per-thread normalized model:

```swift
struct ThreadTokenUsage: Sendable, Codable {
    var threadID: String
    var inputTokens: Int64
    var cachedInputTokens: Int64
    var outputTokens: Int64
    var reasoningOutputTokens: Int64
    var totalTokens: Int64
    var updatedAt: Date
}
```

When persisted usage exists, Codex can replay token usage when a thread is resumed.
The Monitor should treat the newest authoritative event as the current thread total.

---

## 14. Refresh Strategy

The app is event-driven. It must **not** poll every 0.5 seconds.

### 14.1 On Monitor launch / app-server connect

In parallel where safe:

```text
account/read(refreshToken: false)
account/rateLimits/read
account/usage/read
thread/loaded/list
```

Then subscribe/process realtime notifications.

### 14.2 Realtime

Update immediately on:

```text
account/updated
account/rateLimits/updated
thread/tokenUsage/updated
```

### 14.3 Usage page open

When the user opens Usage:

```text
if account usage snapshot age <= 60 seconds:
    render cache immediately
    optional background refresh

if age > 60 seconds:
    render cache immediately as stale/loading
    call account/usage/read
```

This keeps the window instant while still refreshing data.

### 14.4 Manual refresh

`刷新` performs:

```text
account/read
account/rateLimits/read
account/usage/read
loaded thread reconciliation
```

Debounce repeated clicks while a refresh is in flight.

### 14.5 After reset consumption

Always:

```text
account/rateLimits/read
```

Optionally also refresh account usage after the rate-limit snapshot resolves; reset
credits do not imply Token-history changes.

### 14.6 App foregrounding

If Monitor has been backgrounded/sleeping for a meaningful interval:

```text
age > 5 minutes -> refresh account + limits + usage
```

### 14.7 Wake from macOS sleep

On wake:

```text
revalidate app-server connection
refresh account/rate-limits snapshot
refresh Usage if snapshot is older than 5 minutes
reconcile loaded threads
```

---

## 15. Stale Data Rules

Every network/account snapshot has:

```text
fetchedAt
isStale
```

Recommended thresholds:

```text
Account identity: stale after 30 min, but remains usable until auth change
Rate limits: stale after 5 min without an update/refetch
Account usage: stale after 5 min
```

Connection loss:

- retain last known usage/quota locally;
- visually identify it as last known data where appropriate;
- Floating Orb disconnected state still shows `--`, because runtime connectivity is unknown;
- do not silently present old quota as live.

Paused monitoring:

- retain last known quota percentage;
- mark it stale;
- do not consume task events while paused.

---

## 16. Local SQLite Persistence

Usage history is retained permanently unless the user explicitly clears it.

Suggested tables:

```sql
accounts
account_usage_daily
rate_limit_snapshots
reset_credit_snapshots
thread_usage
monitor_events
app_metadata
```

### `accounts`

```text
local_account_key
account_kind
email_display
plan_type
first_seen_at
last_seen_at
```

Do not store credentials.

### `account_usage_daily`

Unique key:

```text
(local_account_key, local_date)
```

Fields:

```text
input_tokens
cached_input_tokens
output_tokens
reasoning_output_tokens
total_tokens
cost_usd
source_updated_at
stored_at
```

Use UPSERT so later authoritative data corrects the same date.

### `rate_limit_snapshots`

Keep snapshots for diagnostics/history, not for deriving billing.

Fields:

```text
timestamp
primary_used_percent
primary_duration_mins
primary_resets_at
secondary_used_percent
secondary_duration_mins
secondary_resets_at
rate_limit_reached_type
reset_credit_available_count
```

### Retention

```text
account_usage_daily -> permanent
thread_usage        -> permanent
diagnostic events   -> configurable future policy
```

The Usage UI initially renders 30 days, but storage is not limited to 30 days.

---

## 17. Account Changes

On `account/updated` or when `account/read` reveals a different active identity:

```text
1. close the old live account scope
2. preserve its local history
3. derive a new local account key
4. fetch new account/rate-limit/usage snapshots
5. switch the UI atomically to the new account
```

Do not merge two different users' daily usage into one history.

### Account key

Prefer a stable non-secret account identifier if the supported app-server schema exposes
one.

If it does not:

```text
P0 must define a safe stable local discriminator.
```

Email alone is not ideal because it can be absent/change and should not be treated as a
credential or guaranteed unique protocol identifier.

---

## 18. Multi-Account UI Safety

The visual prototype currently includes account tools such as add/save/switch.

Implementation constraint:

**Codex Monitor must never copy or persist Codex OAuth/access/refresh tokens in order to
implement multi-account switching.**

Allowed paths:

1. use an official Codex-supported account switching/auth surface if one exists in the
   installed app-server version;
2. launch/hand off to Codex's own account UI;
3. otherwise disable/defer credential switching in v1 while still preserving separate
   local usage history for accounts encountered over time.

P0 must verify the supported account-switching capability before these prototype buttons
are wired to production behavior.

---

## 19. Credits vs Earned Rate-Limit Reset Credits

Treat these as different concepts.

### Earned reset credits

Used by:

```text
account/rateLimitResetCredit/consume
```

Purpose:

```text
reset eligible rate-limit windows
```

### Flexible purchased/shared credits

OpenAI may offer a credit balance for supported agentic features/plans. These are not
the same as earned reset credits.

If app-server exposes an authoritative current balance in the installed stable schema,
the Monitor may display it as a separate field.

Do not label:

```text
$ balance
```

as:

```text
reset count
```

and do not infer one from the other.

---

## 20. Error Handling

| Failure | UI behavior |
|---|---|
| `account/read` fails | keep last account snapshot, mark stale |
| `rateLimits/read` fails | center quota becomes `--` if no fresh authoritative window |
| sparse update cannot merge | refetch full rate-limit snapshot |
| `account/usage/read` fails | show locally cached Usage + last updated time |
| reset returns `noCredit` | refresh snapshot and show concise native alert |
| reset returns `nothingToReset` | refresh snapshot; explain no eligible window |
| reset transport timeout | retry only with same idempotency key |
| account changes mid-refresh | discard response scoped to old account generation |
| app-server disconnects | cancel/re-scope in-flight requests and enter DISCONNECTED runtime state |

Use an `accountGeneration` / session epoch to prevent late responses from an old account
overwriting the new account.

---

## 21. Concurrency Architecture

Recommended actors:

```text
CodexConnectionActor
AccountStoreActor
RateLimitStoreActor
UsageStoreActor
ThreadUsageStoreActor
SQLiteStoreActor
```

UI consumes immutable snapshots through an observable presentation store on MainActor.

Never mutate shared quota/account dictionaries from notification callbacks directly on
the main thread.

---

## 22. P0 Validation Checklist

Before building the final Usage window, Codex must run these checks against the user's
installed Codex build:

### P0-1 `account/read`

Verify:

```text
account type
email availability
planType
authMode / account-updated behavior
stable account identifier availability
```

### P0-2 `account/rateLimits/read`

Capture sanitized schema:

```text
primary
secondary
individualLimit if present
spendControlReached if present
rateLimitReachedType
rateLimitResetCredits
credit detail rows if present
```

Do not assume both primary and secondary exist.

### P0-3 `account/rateLimits/updated`

Verify sparse merge behavior during real usage.

### P0-4 `account/usage/read`

Generate the stable app-server schema and capture one sanitized runtime response.

Confirm exact availability of:

```text
daily dates
input tokens
cached input tokens
output tokens
reasoning output tokens
total tokens
cost / fee fields, if any
summary range
```

Any unavailable field maps to `nil` / `$--`.

### P0-5 reset consume

Only test if the user explicitly agrees to consume a real available reset credit.

Do not burn a reset merely to satisfy automated tests.

Use protocol mocks/unit tests for normal CI.

### P0-6 account switching

Verify whether app-server provides a supported way to switch among existing signed-in
ChatGPT identities without Monitor handling raw credentials.

---

## 23. Acceptance Tests

1. One quota window only -> Orb uses that remaining percentage.
2. Two quota windows -> Orb uses the lower remaining percentage.
3. Backend removes secondary -> UI cleanly removes it; no hard-coded weekly/5h row.
4. Sparse update changes only primary -> secondary survives unchanged.
5. No quota data -> Orb center `--`; no fabricated percentage.
6. Usage response has no authoritative fee -> Usage shows `$--`.
7. All 30 calendar dates render, including zero-use days.
8. Usage tooltip shows exact tokens and authoritative fee or `$--`.
9. Thread Token update changes Quick View session tokens without changing quota %.
10. Rate-limit update changes quota % without rewriting thread Token totals.
11. Reset requires confirmation.
12. Reset retry reuses the same idempotency key.
13. `alreadyRedeemed` is treated as idempotent success.
14. After reset attempt, full rate-limit snapshot is fetched.
15. Disconnect preserves local history but does not pretend stale quota is live.
16. Account change never merges two accounts' daily usage.
17. Monitor stores no OAuth/access/refresh token/API key.
18. SQLite daily records survive app restart.
19. Usage page opens from cache instantly and refreshes in the background.
20. macOS sleep/wake causes connection and rate-limit reconciliation.

---

## 24. Product Constants Carried Forward

```text
Usage page:
  Account
  Session
  Rate-limit reset credit
  Token Usage

Token metrics:
  Today fee
  Last 30 days fee
  Today token usage
  Last 30 days token usage

Chart:
  30 local calendar days
  zero days included
  hover tooltip shows exact token + authoritative fee

Cost:
  never estimated in v1

History:
  SQLite, permanent until explicitly cleared

Floating Orb:
  minimum remaining percentage among authoritative quota windows

Privacy:
  Hide Account Info setting

Reset:
  confirmation required
```

---

## 25. Freeze Status

Product behavior in this document is largely defined, but the document remains
**Draft for technical validation** until P0-1 through P0-4 and P0-6 are run against the
installed Codex build.

After those protocol shapes are captured and the normalized adapters are confirmed,
this file can be promoted to:

```text
FROZEN — Technical Validation Passed
```
