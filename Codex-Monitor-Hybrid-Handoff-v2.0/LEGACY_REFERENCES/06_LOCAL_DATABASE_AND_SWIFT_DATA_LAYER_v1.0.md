# Codex Monitor — Local Database & Swift Data Layer v1.0

> Status: Draft for implementation review  
> Platform: macOS  
> Stack: SwiftUI + AppKit + Swift Concurrency + SQLite  
> Depends on:
> - `04_STATE_ENGINE_AND_EVENT_MAPPING_v1.1_FROZEN.md`
> - `05_ACCOUNT_USAGE_QUOTA_AND_RESET_MODEL_v1.0.md`

---

## 1. Goal

This document defines the local persistence layer and the Swift data architecture used by Codex Monitor.

The design must satisfy these product requirements:

- Usage history persists locally across app restarts.
- Thread/session Token history can be retained permanently.
- Account/quota snapshots are cached locally.
- No Codex credentials are stored by Monitor.
- UI can render immediately from local cache, then refresh in background.
- Multiple asynchronous Codex event streams cannot corrupt local state.
- App crash/restart must not damage the database.
- Old account data must never leak into a newly active account.
- Monitor quitting/crashing must not affect Codex itself.

---

## 2. Storage Technology

Primary storage:

```text
SQLite
```

Recommended Swift wrapper:

```text
GRDB.swift
```

Rationale:

- native-feeling Swift API
- mature migrations
- transactions
- typed records
- WAL support
- good Swift Concurrency integration
- appropriate for local desktop utility data

Alternative:

```text
raw sqlite3
```

is allowed only if dependency policy requires zero third-party packages.

Do not use:

```text
UserDefaults
```

for historical Usage or event data.

UserDefaults is reserved for lightweight preferences only.

---

## 3. Storage Separation

Use two persistence mechanisms:

### 3.1 UserDefaults / AppStorage

For preferences:

```text
language
launchAtLogin
monitoringPaused
approvalNotificationEnabled
completionNotificationEnabled
hideAccountInfo
orbVisible
orbAlwaysOnTop
orbLocked
orbSize
orbPosition
lastSelectedSettingsSection
```

### 3.2 SQLite

For durable data:

```text
account history
daily usage
thread usage
rate-limit snapshots
reset-credit snapshots
monitor lifecycle events
schema metadata
```

---

## 4. Database Location

Use an Application Support directory.

Recommended path:

```text
~/Library/Application Support/Codex Monitor/
```

Database:

```text
codex-monitor.sqlite
```

Optional log directory:

```text
~/Library/Logs/Codex Monitor/
```

Do not write application data into:

```text
~/.codex
```

Codex Monitor must treat Codex-owned files as external resources.

---

## 5. SQLite Configuration

At startup:

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
```

Reasoning:

- WAL supports concurrent readers and serialized writes well.
- `NORMAL` is appropriate for a local utility while maintaining crash safety.
- foreign keys enforce account/thread relationships.
- busy timeout avoids needless failures during short write contention.

All writes must occur through one serialized database writer abstraction.

---

## 6. Schema Versioning

Maintain explicit schema migrations.

Metadata table:

```sql
CREATE TABLE app_metadata (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
);
```

Examples:

```text
schema_version
app_first_launched_at
last_successful_compaction_at
```

Never silently destroy and recreate the user's database when a migration fails.

On migration failure:

```text
1. stop writes
2. preserve database file
3. create diagnostic log
4. show recoverable error UI
```

---

## 7. Accounts Table

```sql
CREATE TABLE accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    local_account_key TEXT NOT NULL UNIQUE,
    account_kind TEXT NOT NULL,
    email_display TEXT,
    plan_type TEXT,
    auth_mode TEXT,
    first_seen_at REAL NOT NULL,
    last_seen_at REAL NOT NULL
);
```

Rules:

- `local_account_key` must not contain a credential.
- `email_display` is display metadata only.
- full account secrets are never stored.
- when `Hide Account Info` is enabled, the database does not need to rewrite historical rows; masking happens at presentation time.

---

## 8. Daily Usage Table

```sql
CREATE TABLE account_usage_daily (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER NOT NULL,
    local_date TEXT NOT NULL,

    input_tokens INTEGER,
    cached_input_tokens INTEGER,
    output_tokens INTEGER,
    reasoning_output_tokens INTEGER,
    total_tokens INTEGER,
    cost_usd TEXT,

    source_updated_at REAL,
    stored_at REAL NOT NULL,

    FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE,
    UNIQUE(account_id, local_date)
);
```

`local_date` format:

```text
YYYY-MM-DD
```

using the user’s local calendar at normalization time.

Cost uses decimal text rather than binary floating point.

Example:

```text
"77.53"
```

---

## 9. Rate-Limit Snapshot Table

```sql
CREATE TABLE rate_limit_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER NOT NULL,
    captured_at REAL NOT NULL,

    primary_used_percent REAL,
    primary_remaining_percent REAL,
    primary_window_minutes INTEGER,
    primary_resets_at REAL,

    secondary_used_percent REAL,
    secondary_remaining_percent REAL,
    secondary_window_minutes INTEGER,
    secondary_resets_at REAL,

    rate_limit_reached_type TEXT,
    reset_credit_available_count INTEGER,

    FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE
);
```

These records are historical snapshots.

Do not use an old snapshot as if it were a live quota reading.

---

## 10. Reset Credit Snapshot Table

```sql
CREATE TABLE reset_credit_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER NOT NULL,
    captured_at REAL NOT NULL,
    available_count INTEGER NOT NULL,
    details_json TEXT,

    FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE
);
```

`details_json` is acceptable because detail rows are protocol-driven and may evolve.

Top-level count remains normalized.

---

## 11. Thread Table

```sql
CREATE TABLE threads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER,
    codex_thread_id TEXT NOT NULL UNIQUE,
    title TEXT,
    first_user_message_preview TEXT,
    model TEXT,
    first_seen_at REAL NOT NULL,
    last_seen_at REAL NOT NULL,

    FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE SET NULL
);
```

Title priority:

```text
thread title
>
first user message preview
```

Store only a short preview, not the entire conversation.

---

## 12. Thread Usage Table

```sql
CREATE TABLE thread_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,

    input_tokens INTEGER NOT NULL DEFAULT 0,
    cached_input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    reasoning_output_tokens INTEGER NOT NULL DEFAULT 0,
    total_tokens INTEGER NOT NULL DEFAULT 0,

    updated_at REAL NOT NULL,

    FOREIGN KEY(thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    UNIQUE(thread_id)
);
```

This table stores the latest authoritative cumulative usage for each thread.

Do not sum repeated cumulative updates.

Use UPSERT:

```sql
INSERT ...
ON CONFLICT(thread_id)
DO UPDATE SET ...
```

---

## 13. Turn History Table

Recommended for v1 diagnostics and future Usage expansion:

```sql
CREATE TABLE turns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    codex_turn_id TEXT NOT NULL UNIQUE,

    started_at REAL,
    completed_at REAL,

    terminal_status TEXT,
    final_error_summary TEXT,

    FOREIGN KEY(thread_id) REFERENCES threads(id) ON DELETE CASCADE
);
```

Allowed terminal status:

```text
completed
interrupted
failed
systemError
```

Do not store hidden reasoning.

---

## 14. Monitor Events Table

Purpose:

- diagnostics
- reconnect investigation
- user-visible “last updated”
- state-machine debugging

```sql
CREATE TABLE monitor_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at REAL NOT NULL,
    severity TEXT NOT NULL,
    category TEXT NOT NULL,
    event_name TEXT NOT NULL,
    thread_id TEXT,
    turn_id TEXT,
    summary TEXT
);
```

Examples:

```text
connection.connected
connection.disconnected
account.changed
rate_limit.updated
turn.started
turn.completed
approval.requested
approval.resolved
database.migration_failed
```

Do not persist raw sensitive event payloads by default.

---

## 15. Event Retention

Product history:

```text
account_usage_daily -> permanent
thread_usage        -> permanent
threads             -> permanent
turns               -> permanent
```

Diagnostics:

```text
monitor_events -> default 90 days
```

Reason:

Monitor events are implementation diagnostics, not user Usage history.

Future Settings can expose:

```text
Clear Diagnostic History
Clear All Local Usage History
```

but v1 does not need to expose these unless desired.

---

## 16. Database Actor

Recommended:

```swift
actor DatabaseActor {
    private let dbQueue: DatabaseQueue

    func migrate() async throws
    func upsertAccount(_ snapshot: AccountSnapshot) async throws -> AccountRecord
    func upsertDailyUsage(...) async throws
    func saveRateLimitSnapshot(...) async throws
    func upsertThread(...) async throws
    func upsertThreadUsage(...) async throws
    func saveTurn(...) async throws
    func appendMonitorEvent(...) async throws
}
```

Only this actor performs writes.

Presentation/UI code never writes SQL directly.

---

## 17. Repository Layer

Keep transport, domain, persistence and UI separate.

Recommended modules:

```text
CodexTransport
Domain
Persistence
Repositories
Presentation
UI
```

Repositories:

```swift
protocol AccountRepository {
    func currentAccount() async -> AccountSnapshot?
    func refreshAccount() async throws -> AccountSnapshot
}

protocol RateLimitRepository {
    func currentSnapshot() async -> RateLimitSnapshot?
    func refresh() async throws -> RateLimitSnapshot
}

protocol UsageRepository {
    func usageSnapshot(days: Int) async -> AccountUsageSnapshot
    func refreshUsage() async throws -> AccountUsageSnapshot
}

protocol ThreadRepository {
    func loadedThreads() async -> [ThreadRuntimeState]
}

protocol ResetCreditRepository {
    func consumeCredit(idempotencyKey: UUID) async throws -> ResetResult
}
```

UI depends on repositories or presentation stores, never on JSON-RPC types.

---

## 18. Codex Transport Layer

Recommended actor:

```swift
actor CodexConnectionActor
```

Responsibilities:

```text
connect
initialize protocol
send JSON-RPC requests
receive notifications
receive server requests
reconnect
decode protocol types
route events
```

It must not:

```text
format UI strings
write SwiftUI state directly
write SQLite directly
```

Transport emits normalized domain events.

Example:

```swift
enum CodexDomainEvent: Sendable {
    case accountUpdated(AccountSnapshot)
    case rateLimitsUpdated(RateLimitSparseUpdate)
    case threadStatusChanged(...)
    case turnStarted(...)
    case turnCompleted(...)
    case itemStarted(...)
    case itemCompleted(...)
    case approvalRequested(...)
    case approvalResolved(...)
    case threadTokenUsageUpdated(ThreadTokenUsage)
    case connectionStateChanged(ConnectionState)
}
```

---

## 19. Domain Coordinator

Central orchestration actor:

```swift
actor MonitorCoordinator
```

Consumes:

```text
CodexDomainEvent
```

Updates:

```text
StateEngine
AccountStore
RateLimitStore
UsageStore
ThreadStore
DatabaseActor
```

Then publishes immutable presentation snapshots.

This prevents event callbacks from independently mutating global state.

---

## 20. Presentation Store

Use one MainActor observable store.

Example:

```swift
@MainActor
@Observable
final class AppPresentationStore {
    var menuBar: MenuBarViewState
    var orb: OrbViewState
    var quickView: QuickViewState
    var menuPopup: MenuPopupViewState
    var usage: UsageViewState
    var settings: SettingsViewState
}
```

Views render only presentation models.

They do not decode protocol data.

---

## 21. Immutable Presentation Models

Example:

```swift
struct OrbViewState: Equatable {
    var runtimeState: MonitorState
    var quotaText: String
    var isBreathing: Bool
    var isConnected: Bool
}

struct QuickViewState: Equatable {
    var statusText: String
    var taskTitle: String?
    var activityText: String?
    var modelText: String?
    var runtimeText: String?
    var tokenText: String?
    var quotaText: String?
}
```

Formatting belongs in a dedicated presentation formatter.

---

## 22. App Settings Model

Recommended:

```swift
struct AppSettings: Codable, Sendable {
    var language: AppLanguage
    var launchAtLogin: Bool

    var orbVisible: Bool
    var orbAlwaysOnTop: Bool
    var orbLocked: Bool
    var orbSize: Double

    var monitoringPaused: Bool

    var approvalNotificationEnabled: Bool
    var completionNotificationEnabled: Bool

    var hideAccountInfo: Bool
}
```

Floating position is screen-aware:

```swift
struct OrbPlacement: Codable, Sendable {
    var displayIdentifier: String?
    var normalizedX: Double
    var normalizedY: Double
}
```

Use normalized coordinates rather than storing only absolute pixels.

This makes restoration safer after display resolution changes.

---

## 23. Floating Orb Size Persistence

Current product behavior:

```text
default = 90 px
continuous proportional scaling
```

Settings slider updates the same source of truth as direct resize.

Architecture:

```text
Settings slider
        \
         -> OrbSizeStore -> NSPanel frame update
        /
direct window resize
```

Both paths must update:

```text
AppSettings.orbSize
```

and the UI must stay synchronized in realtime.

Do not maintain separate “slider size” and “window size” values.

---

## 24. Orb Position Restoration

On drag end:

```text
1. determine containing NSScreen.visibleFrame
2. convert orb center to normalized coordinates
3. persist screen identifier + normalized X/Y
```

On launch:

```text
1. try matching display identifier
2. if unavailable, use current main screen
3. reconstruct point from normalized coordinates
4. clamp entire orb into visibleFrame
```

Never restore the orb fully off-screen.

---

## 25. Account Generation / Epoch

Critical concurrency rule.

Maintain:

```swift
var accountEpoch: UInt64
```

Increment when:

```text
active account changes
auth mode changes in a way that invalidates old requests
```

Every async account-scoped request captures the epoch.

On completion:

```text
if capturedEpoch != currentEpoch:
    discard response
```

This prevents:

```text
old account usage response
```

from overwriting:

```text
new account UI
```

---

## 26. Connection Generation / Epoch

Similarly maintain:

```swift
connectionEpoch
```

Increment on reconnect.

Events/responses tied to a prior connection can be ignored after a new authoritative session starts.

---

## 27. Startup Sequence

Recommended:

```text
App launch
↓
Load UserDefaults/AppSettings
↓
Open SQLite
↓
Run migrations
↓
Load cached account/usage/quota/thread summaries
↓
Render menu bar + orb immediately
↓
Start Codex connection
↓
Initialize app-server
↓
Fetch fresh snapshots
↓
Reconcile cached/local state
↓
Begin realtime event processing
```

UI should not wait for network connection before appearing.

---

## 28. Shutdown Sequence

On normal quit:

```text
stop accepting new requests
flush pending DB writes
persist orb position/size
close monitor connection
close windows
quit
```

Codex itself must not be terminated.

No kill signal is sent to Codex Desktop or a Codex-owned app-server.

---

## 29. Crash Recovery

SQLite WAL handles durable commits.

On next launch:

```text
load last committed cache
mark network-derived values stale
reconnect
refresh authoritative snapshots
```

Never assume:

```text
WORKING
```

from a previous process run.

Runtime state is reconstructed from current Codex thread state.

---

## 30. Privacy Rules

Never persist:

```text
OAuth access token
OAuth refresh token
API key
session cookie
authorization header
full raw app-server payloads containing secrets
```

Redact sensitive information from diagnostic logs.

When `Hide Account Info` is enabled:

```text
abc@gmail.com
```

may render as:

```text
a•••@gmail.com
```

or:

```text
账户已隐藏
```

Exact presentation can be finalized later.

---

## 31. Log Redaction

Before writing any diagnostic string:

```text
remove/tokenize:
Authorization headers
Bearer tokens
API keys
JWT-like strings
home-directory-sensitive credential paths
```

Commands shown in Quick View should use the sanitized/display form from Codex when available.

---

## 32. Usage Query API

SQLite should expose a local query that always returns exactly 30 date rows.

Example:

```swift
func dailyUsage(
    accountID: Int64,
    endingOn date: Date,
    days: Int = 30,
    calendar: Calendar
) async throws -> [DailyUsage]
```

The repository constructs zero rows for missing dates.

Do not require the database itself to contain zero-usage records.

---

## 33. Formatting Layer

Create:

```swift
struct UsageFormatter
struct QuotaFormatter
struct DurationFormatter
struct AccountFormatter
```

Examples:

```text
6_243_800 -> 624.38万 token
0.42 remaining -> 42%
763 sec -> 12:43
```

Formatting code is unit tested independently from UI.

---

## 34. Time Zone Handling

Daily Usage is a presentation/calendar concept.

Store:

```text
local_date
```

derived using the user’s active local calendar when ingesting account usage buckets.

If Codex returns an explicit server date already representing a daily bucket, preserve that semantic date rather than shifting it by arbitrary UTC conversion.

P0 must verify the exact schema semantics of `account/usage/read`.

---

## 35. Notification Coordinator

Separate actor/service:

```swift
NotificationCoordinator
```

Receives state transitions.

Rules:

```text
WAITING_APPROVAL:
    notify only if setting enabled

COMPLETED:
    notify only if setting enabled

FAILED/INTERRUPTED:
    no new product decision has enabled notifications yet
```

Do not send duplicate notifications for the same Turn transition.

Keep a transient dedupe key:

```text
(threadID, turnID, notificationType)
```

---

## 36. Settings Synchronization

Settings changes should apply immediately.

Examples:

```text
Always on Top toggle
-> update NSPanel level immediately
-> persist setting

Lock Position toggle
-> update drag behavior immediately
-> persist setting

Orb size slider
-> resize panel immediately
-> persist continuously/debounced

Pause Monitoring
-> transition presentation to PAUSED
-> persist setting
```

Use a short debounce for high-frequency slider persistence, e.g. ~150–250 ms.

Do not debounce the visual resize itself.

---

## 37. Suggested Project Structure

```text
CodexMonitor/
├── App/
│   ├── CodexMonitorApp.swift
│   ├── AppDelegate.swift
│   └── AppEnvironment.swift
│
├── Transport/
│   ├── CodexConnectionActor.swift
│   ├── JSONRPCClient.swift
│   ├── CodexProtocolTypes.swift
│   └── CodexProtocolAdapter.swift
│
├── Domain/
│   ├── MonitorState.swift
│   ├── StateEngine.swift
│   ├── MonitorCoordinator.swift
│   ├── AccountModels.swift
│   ├── UsageModels.swift
│   └── DomainEvents.swift
│
├── Persistence/
│   ├── DatabaseActor.swift
│   ├── DatabaseMigrator.swift
│   ├── Records/
│   └── Queries/
│
├── Repositories/
│   ├── AccountRepository.swift
│   ├── RateLimitRepository.swift
│   ├── UsageRepository.swift
│   ├── ThreadRepository.swift
│   └── ResetCreditRepository.swift
│
├── Presentation/
│   ├── AppPresentationStore.swift
│   ├── ViewStates/
│   └── Formatters/
│
├── UI/
│   ├── MenuBar/
│   ├── FloatingOrb/
│   ├── QuickView/
│   ├── MenuPopup/
│   ├── Usage/
│   └── Settings/
│
├── System/
│   ├── LaunchAtLoginService.swift
│   ├── NotificationCoordinator.swift
│   ├── WindowCoordinator.swift
│   └── ScreenPlacementService.swift
│
└── Tests/
    ├── StateEngineTests/
    ├── RepositoryTests/
    ├── PersistenceTests/
    ├── FormatterTests/
    └── ProtocolAdapterTests/
```

---

## 38. Unit Test Requirements

At minimum test:

```text
database migrations
daily usage UPSERT
thread usage cumulative update replacement
account epoch stale-response rejection
connection epoch stale-event rejection
30-day zero-fill
Chinese Token formatting
quota min-remaining selection
slider/orb-size synchronization
position restoration after display resolution change
privacy masking
redaction
```

---

## 39. Integration Test Requirements

Using a mock app-server:

```text
connect
load cached UI
receive account
receive rate limits
receive usage
receive thread state
receive token update
disconnect
reconnect
account switch
sparse rate-limit merge
reset consume
```

CI should not require a real Codex account.

Real Codex Desktop tests are P0/manual integration tests.

---

## 40. Performance Targets

Menu bar utility should remain lightweight.

Targets:

```text
idle CPU: effectively negligible
no 0.5s polling loop
no continuous database writes while idle
UI state updates only when normalized state changes
chart data queried only when needed/cached
```

Animation cadence is visual only and must not trigger data polling.

---

## 41. Acceptance Criteria

The data layer passes when:

1. App launches and renders cached state before live connection completes.
2. SQLite survives restart with Usage history intact.
3. Token and quota data remain separate.
4. Old-account async responses cannot overwrite a new account.
5. Sparse rate-limit updates merge correctly.
6. 30-day chart always returns 30 calendar positions.
7. Missing cost remains `nil` and renders `$--`.
8. Floating Orb size slider and manual resize remain synchronized.
9. Orb position is restored on valid screen coordinates.
10. No credentials exist in SQLite/UserDefaults/logs.
11. App exit leaves Codex running.
12. Reconnect reconstructs runtime state instead of trusting old active state.
13. UI never writes directly to SQLite.
14. JSON-RPC transport types never leak directly into SwiftUI views.
15. Database migration failure does not destroy user history.

---

## 42. Freeze Status

The database architecture and layering are suitable to freeze after:

```text
- P0 account/usage schema validation
- final decision on whether GRDB dependency is accepted
- final macOS deployment target is selected
```

No additional product behavior decision is required for this document at this stage.
