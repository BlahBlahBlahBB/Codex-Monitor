import CSQLite
import CodexMonitorContracts
import Foundation

/// A monitor-owned, read-only-from-Codex usage lane.  It persists only closed
/// numeric deltas and the structured provenance needed to reject replay; no
/// rollout body, prompt, message, reasoning, command or tool data is stored.
public struct LocalUsageLedgerSnapshot: Sendable, Equatable {
    public let availability: MonitorDataAvailability
    public let days: [LocalUsageDay]
    public let priceCatalogVersion: String
    public let priceCatalogEffectiveDate: String

    public init(availability: MonitorDataAvailability, days: [LocalUsageDay], priceCatalogVersion: String = "openai-standard-token-rate-2026-08-13", priceCatalogEffectiveDate: String = "2026-08-13") {
        self.availability = availability; self.days = days
        self.priceCatalogVersion = priceCatalogVersion; self.priceCatalogEffectiveDate = priceCatalogEffectiveDate
    }

    public var today: LocalUsageDay? { days.last }
    public var last30TokenTotal: Int64? { availability == .available ? days.reduce(0) { $0 + $1.totalTokens } : nil }
    public var last30EstimatedCostUSD: Double? { aggregateCost(days) }

    public func day(named key: String) -> LocalUsageDay? { days.first { $0.dateKey == key } }

    private func aggregateCost(_ values: [LocalUsageDay]) -> Double? {
        let rows = values.flatMap(\.models)
        guard !rows.isEmpty, rows.allSatisfy({ $0.estimatedCostUSD != nil }) else { return nil }
        return rows.reduce(0) { $0 + ($1.estimatedCostUSD ?? 0) }
    }
}

public struct LocalUsageDay: Sendable, Equatable, Identifiable {
    public let dateKey: String
    public let totalTokens: Int64
    public let models: [LocalUsageModelTotal]
    public var id: String { dateKey }

    public init(dateKey: String, totalTokens: Int64, models: [LocalUsageModelTotal]) {
        self.dateKey = dateKey; self.totalTokens = max(0, totalTokens)
        self.models = models.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public var estimatedCostUSD: Double? {
        guard !models.isEmpty, models.allSatisfy({ $0.estimatedCostUSD != nil }) else { return nil }
        return models.reduce(0) { $0 + ($1.estimatedCostUSD ?? 0) }
    }
}

public struct LocalUsageModelTotal: Sendable, Equatable, Identifiable {
    public let modelID: String
    public let displayName: String
    public let totalTokens: Int64
    public let estimatedCostUSD: Double?
    public let estimatedCredits: Double?
    public var id: String { modelID }
}

/// The visible 30-day account lane has deliberately different ownership from
/// local realtime/model attribution.  This value preserves that distinction
/// through presentation without asking a chart or view to infer it.
enum HybridUsageProvenance: String, Sendable, Equatable {
    case authoritativeAccount
    case localRealtimeProvisional
    case sourceAbsent
}

struct HybridUsageDay: Sendable, Equatable, Identifiable {
    let dateKey: String
    /// Nil means the Account source did not return this historical day and no
    /// permitted today-only provisional replacement exists.
    let tokens: Int64?
    let provenance: HybridUsageProvenance
    var id: String { dateKey }
    var chartTokens: Int64 { tokens ?? 0 }
}

struct HybridUsageWindow: Sendable, Equatable {
    let days: [HybridUsageDay]
    let headlineTokens: Int64?
    /// Account-scoped 30-day Token has no complete account-scoped token-type
    /// cost attribution, so partial local cost is intentionally ineligible.
    var headlineEstimatedCostUSD: Double? { nil }

    var today: HybridUsageDay? { days.last }
}

enum HybridUsageComposer {
    /// Historical Account absences remain absent. Only the current local day
    /// is eligible for a provisional replacement, and an authoritative today
    /// always wins instead of being added to it.
    static func compose(
        accountDailyBuckets: [AccountUsageDailyBucket]?,
        accountAvailability: MonitorDataAvailability,
        localLedger: LocalUsageLedgerSnapshot?,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> HybridUsageWindow? {
        guard accountAvailability == .available, let accountDailyBuckets else { return nil }
        let byDate = Dictionary(uniqueKeysWithValues: accountDailyBuckets.map { ($0.startDate, $0) })
        let todayKey = LocalUsageDateKey.value(for: now, calendar: calendar)
        let localToday = localLedger?.availability == .available ? localLedger?.day(named: todayKey)?.totalTokens : nil
        let today = calendar.startOfDay(for: now)
        let keys = (0..<30).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today).map { LocalUsageDateKey.value(for: $0, calendar: calendar) }
        }
        let days = keys.map { key -> HybridUsageDay in
            if let authoritative = byDate[key]?.authoritativeTokens {
                return HybridUsageDay(dateKey: key, tokens: Int64(authoritative), provenance: .authoritativeAccount)
            }
            if key == todayKey, let localToday {
                return HybridUsageDay(dateKey: key, tokens: localToday, provenance: .localRealtimeProvisional)
            }
            return HybridUsageDay(dateKey: key, tokens: nil, provenance: .sourceAbsent)
        }
        return HybridUsageWindow(days: days, headlineTokens: days.compactMap(\.tokens).reduce(0, +))
    }
}

enum LocalUsagePriceCatalog {
    static let version = "openai-standard-token-rate-2026-08-13"
    static let effectiveDate = "2026-08-13"

    struct Rate { let inputUSD: Double; let cachedUSD: Double; let outputUSD: Double; let inputCredits: Double; let cachedCredits: Double; let outputCredits: Double }

    static func normalizedModel(_ raw: String?) -> (id: String, display: String, rate: Rate?) {
        let compact = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch compact?.lowercased() {
        case "gpt-5.6", "gpt-5.6-sol": return ("gpt-5.6-sol", "GPT-5.6 Sol", Rate(inputUSD: 5, cachedUSD: 0.5, outputUSD: 30, inputCredits: 125, cachedCredits: 12.5, outputCredits: 750))
        case "gpt-5.6-terra": return ("gpt-5.6-terra", "GPT-5.6 Terra", Rate(inputUSD: 2.5, cachedUSD: 0.25, outputUSD: 15, inputCredits: 62.5, cachedCredits: 6.25, outputCredits: 375))
        case "gpt-5.6-luna": return ("gpt-5.6-luna", "GPT-5.6 Luna", Rate(inputUSD: 1, cachedUSD: 0.1, outputUSD: 6, inputCredits: 25, cachedCredits: 2.5, outputCredits: 150))
        case .none, .some(""): return ("unknown-model", "Unknown model", nil)
        default:
            let safe = String(compact!.prefix(128))
            return (safe, safe, nil)
        }
    }
}

public actor LocalUsageLedgerProvider {
    public enum Admission: Sendable, Equatable {
        /// A reader joined an existing or bounded historical rollout. Its first
        /// cumulative observation is a baseline, never inferred usage.
        case midstreamBaseline
        /// The live monitor admitted a new session from its authoritative
        /// start record during this lifecycle. Its first cumulative token
        /// event is a proven 0 → cumulative delta.
        case completeFromSessionStart
    }

    private struct TurnKey: Hashable, Sendable {
        let threadID: NamespacedID
        let turnID: NamespacedID
    }

    private struct Sample: Sendable {
        let identity: String
        let sourceKey: String
        let cumulativeTotal: Int64
        let dateKey: String
        let modelID: String
        let displayModel: String
        let total: Int64
        let estimatedCostUSD: Double?
        let estimatedCredits: Double?
    }

    private let databaseURL: URL
    private var database: OpaquePointer?
    private var availability: MonitorDataAvailability = .unknown
    private var hasTokenEvidence = false
    private var continuations: [UUID: AsyncStream<LocalUsageLedgerSnapshot>.Continuation] = [:]
    private var modelByTurn: [TurnKey: String] = [:]
    private var registrationModelByThread: [NamespacedID: String] = [:]
    private var calendar: Calendar

    public init(databaseURL: URL? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Codex Monitor", isDirectory: true)
            .appendingPathComponent("LocalUsageLedger.sqlite", isDirectory: false)
        self.databaseURL = databaseURL ?? fallback
    }

    public func start() {
        guard database == nil else { return }
        do {
            try openAndMigrate()
            availability = hasTokenEvidence ? .available : .unknown
        } catch {
            availability = .unavailable
        }
        publish()
    }

    public func stop() {
        if let database { sqlite3_close(database) }
        database = nil
    }

    public func snapshots() -> AsyncStream<LocalUsageLedgerSnapshot> {
        let id = UUID()
        let stream = AsyncStream<LocalUsageLedgerSnapshot>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in Task { await self?.removeContinuation(id) } }
        }
        continuations[id]?.yield(snapshot())
        return stream
    }

    public func snapshot(now: Date = Date()) -> LocalUsageLedgerSnapshot {
        guard availability != .unavailable, hasTokenEvidence else {
            return LocalUsageLedgerSnapshot(availability: availability == .unavailable ? .unavailable : .unknown, days: [])
        }
        return LocalUsageLedgerSnapshot(availability: .available, days: dailyTotals(now: now))
    }

    /// Stable identity for the rollout/session cumulative counter.  A turn is
    /// deliberately excluded because `total_token_usage` can span turns.
    public static func cursorSourceKey(for record: RolloutRecordEnvelope) -> String? {
        guard let session = record.sessionID else { return nil }
        return "\(record.threadID.sourceID.rawValue)|\(record.threadID.rawID)|\(session)"
    }

    /// Feeds already-admitted desktop observations.  This lane never opens or
    /// writes Codex state/log databases and does not inspect transcript data.
    public func ingest(registrations: [DesktopThreadSnapshot], observations: [DesktopObservation], admission: Admission = .midstreamBaseline, completeFromSessionStartSessions: Set<String> = []) {
        guard database != nil || initializeForIngest() else { return }
        for registration in registrations {
            if let model = registration.model { registrationModelByThread[registration.threadID] = model }
        }
        var changed = false
        for observation in observations {
            guard case let .rollout(record) = observation else { continue }
            if record.kind == .turnContext, let turn = record.turnID, let model = record.model {
                modelByTurn[TurnKey(threadID: record.threadID, turnID: turn)] = model
            }
            guard record.kind == .tokenCount,
                  record.tokenSnapshot != nil,
                  record.sessionID != nil,
                  record.turnID != nil,
                  record.authoritativeEventAt != nil else { continue }
            hasTokenEvidence = true
            let recordAdmission: Admission = Self.cursorSourceKey(for: record).map { completeFromSessionStartSessions.contains($0) } == true ? .completeFromSessionStart : admission
            guard let sample = sample(from: record, admission: recordAdmission) else { continue }
            if admit(sample) { changed = true }
        }
        availability = hasTokenEvidence ? .available : .unknown
        if changed || hasTokenEvidence { publish() }
    }

    private func initializeForIngest() -> Bool {
        start()
        return database != nil
    }

    private func sample(from record: RolloutRecordEnvelope, admission: Admission) -> Sample? {
        guard let turn = record.turnID,
              let token = record.tokenSnapshot,
              token.totalTokens >= 0,
              let eventAt = record.authoritativeEventAt else { return nil }
        // `total_token_usage` is cumulative at the validated rollout/session
        // scope, never turn scope. Turn stays in sample identity/model
        // attribution, but must not reset the cumulative cursor.
        let sourceKey = Self.cursorSourceKey(for: record)!
        let turnKey = TurnKey(threadID: record.threadID, turnID: turn)
        let resolved = LocalUsagePriceCatalog.normalizedModel(record.model ?? modelByTurn[turnKey] ?? registrationModelByThread[record.threadID])
        let key = LocalUsageDateKey.value(for: eventAt, calendar: calendar)
        let identity = "\(sourceKey)|\(turn.rawID)|\(record.fileOffset)|\(token.totalTokens)"
        let delta = tokenDelta(sourceKey: sourceKey, cumulative: token.totalTokens, admission: admission)
        guard let delta, delta > 0 else { return nil }
        // Older records establish the cumulative baseline but are never kept
        // as UI history. This makes first-launch backfill bounded to exactly
        // the 30 local calendar days requested by the product.
        guard key >= (last30DayKeys(now: Date()).first ?? key) else { return nil }
        let estimate = estimate(for: token.lastCallBreakdown, expectedDelta: delta, rate: resolved.rate)
        return Sample(identity: identity, sourceKey: sourceKey, cumulativeTotal: token.totalTokens, dateKey: key, modelID: resolved.id, displayModel: resolved.display, total: delta, estimatedCostUSD: estimate?.cost, estimatedCredits: estimate?.credits)
    }

    /// The session cursor is monotonic. A lower historical replay is ignored;
    /// it never lowers the known cumulative total and can therefore never make
    /// a later replay look like newly consumed Token.
    private func tokenDelta(sourceKey: String, cumulative: Int64, admission: Admission) -> Int64? {
        guard let previous = cursorTotal(sourceKey: sourceKey) else {
            upsertCursor(sourceKey: sourceKey, cumulative: cumulative)
            return admission == .completeFromSessionStart ? cumulative : nil
        }
        guard cumulative > previous else { return nil }
        upsertCursor(sourceKey: sourceKey, cumulative: cumulative)
        return cumulative - previous
    }

    private func estimate(for breakdown: TokenUsageBreakdown?, expectedDelta: Int64, rate: LocalUsagePriceCatalog.Rate?) -> (cost: Double, credits: Double)? {
        guard let breakdown, let rate,
              breakdown.totalTokens == expectedDelta,
              let input = breakdown.inputTokens,
              let cached = breakdown.cachedInputTokens,
              let output = breakdown.outputTokens,
              let reasoning = breakdown.reasoningOutputTokens,
              input >= cached,
              reasoning <= output else { return nil }
        let sum = input.addingReportingOverflow(output)
        guard !sum.overflow, sum.partialValue == breakdown.totalTokens else { return nil }
        // Cached input is a subset of input. Reasoning tokens are deliberately
        // not added: the source's output category already owns them.
        let uncached = Double(input - cached) / 1_000_000
        let cachedValue = Double(cached) / 1_000_000
        let outputValue = Double(output) / 1_000_000
        return (
            uncached * rate.inputUSD + cachedValue * rate.cachedUSD + outputValue * rate.outputUSD,
            uncached * rate.inputCredits + cachedValue * rate.cachedCredits + outputValue * rate.outputCredits
        )
    }

    private func admit(_ sample: Sample) -> Bool {
        guard let database else { return false }
        var statement: OpaquePointer?
        let sql = "INSERT OR IGNORE INTO usage_samples (sample_id, source_key, cumulative_total, date_key, model_id, display_model, total_tokens, estimated_cost_usd, estimated_credits) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        bind(sample.identity, statement, 1); bind(sample.sourceKey, statement, 2)
        sqlite3_bind_int64(statement, 3, sample.cumulativeTotal); bind(sample.dateKey, statement, 4)
        bind(sample.modelID, statement, 5); bind(sample.displayModel, statement, 6); sqlite3_bind_int64(statement, 7, sample.total)
        if let cost = sample.estimatedCostUSD { sqlite3_bind_double(statement, 8, cost) } else { sqlite3_bind_null(statement, 8) }
        if let credits = sample.estimatedCredits { sqlite3_bind_double(statement, 9, credits) } else { sqlite3_bind_null(statement, 9) }
        guard sqlite3_step(statement) == SQLITE_DONE else { return false }
        return sqlite3_changes(database) == 1
    }

    private func dailyTotals(now: Date) -> [LocalUsageDay] {
        guard let database else { return [] }
        let keys = last30DayKeys(now: now)
        var rows: [String: [String: (display: String, tokens: Int64, cost: Double?, credits: Double?)]] = [:]
        var statement: OpaquePointer?
        let sql = "SELECT date_key, model_id, display_model, total_tokens, estimated_cost_usd, estimated_credits FROM usage_samples WHERE date_key >= ?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(keys.first ?? "", statement, 1)
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let day = sqliteText(statement, 0), keys.contains(day), let model = sqliteText(statement, 1), let display = sqliteText(statement, 2) else { continue }
            let tokens = sqlite3_column_int64(statement, 3)
            let hasCost = sqlite3_column_type(statement, 4) != SQLITE_NULL
            let hasCredits = sqlite3_column_type(statement, 5) != SQLITE_NULL
            let existing = rows[day]?[model]
            let mergedCost: Double?
            if let existing {
                mergedCost = existing.cost.flatMap { hasCost ? $0 + sqlite3_column_double(statement, 4) : nil }
            } else {
                mergedCost = hasCost ? sqlite3_column_double(statement, 4) : nil
            }
            let mergedCredits: Double?
            if let existing {
                mergedCredits = existing.credits.flatMap { hasCredits ? $0 + sqlite3_column_double(statement, 5) : nil }
            } else {
                mergedCredits = hasCredits ? sqlite3_column_double(statement, 5) : nil
            }
            rows[day, default: [:]][model] = (display, (existing?.tokens ?? 0) + tokens, mergedCost, mergedCredits)
        }
        return keys.map { day in
            let models = (rows[day] ?? [:]).map { model, value in LocalUsageModelTotal(modelID: model, displayName: value.display, totalTokens: value.tokens, estimatedCostUSD: value.cost, estimatedCredits: value.credits) }
            return LocalUsageDay(dateKey: day, totalTokens: models.reduce(0) { $0 + $1.totalTokens }, models: models)
        }
    }

    private func last30DayKeys(now: Date) -> [String] {
        let today = calendar.startOfDay(for: now)
        return (0..<30).reversed().compactMap { offset in calendar.date(byAdding: .day, value: -offset, to: today).map { LocalUsageDateKey.value(for: $0, calendar: calendar) } }
    }

    private func openAndMigrate() throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var opened: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let opened else { throw LedgerError.open }
        database = opened
        guard execute("PRAGMA foreign_keys = ON"), execute("PRAGMA journal_mode = WAL") else { throw LedgerError.schema }
        let version = scalar("PRAGMA user_version")
        guard version <= 2 else { throw LedgerError.futureSchema }
        if version == 0 {
            guard execute("CREATE TABLE IF NOT EXISTS usage_samples (sample_id TEXT PRIMARY KEY NOT NULL, source_key TEXT NOT NULL, cumulative_total INTEGER NOT NULL, date_key TEXT NOT NULL, model_id TEXT NOT NULL, display_model TEXT NOT NULL, total_tokens INTEGER NOT NULL CHECK(total_tokens >= 0), estimated_cost_usd REAL, estimated_credits REAL)"),
                  execute("CREATE INDEX IF NOT EXISTS usage_samples_day_idx ON usage_samples(date_key)"),
                  execute("CREATE TABLE IF NOT EXISTS usage_cursors (source_key TEXT PRIMARY KEY NOT NULL, cumulative_total INTEGER NOT NULL)"),
                  execute("CREATE TABLE IF NOT EXISTS usage_ledger_migrations (schema_version INTEGER PRIMARY KEY NOT NULL, migrated_at REAL NOT NULL, invalidation_reason TEXT NOT NULL)"),
                  execute("PRAGMA user_version = 2") else { throw LedgerError.schema }
        }
        if version == 1 {
            // V1 cursors were turn-scoped and could roll back; every sample
            // derived from them is therefore invalid. Keep only migration
            // metadata, atomically discard derived tables, and let the
            // existing read-only active/archive backfill rebuild v2 facts.
            guard execute("BEGIN IMMEDIATE"),
                  execute("CREATE TABLE IF NOT EXISTS usage_ledger_migrations (schema_version INTEGER PRIMARY KEY NOT NULL, migrated_at REAL NOT NULL, invalidation_reason TEXT NOT NULL)"),
                  execute("INSERT OR REPLACE INTO usage_ledger_migrations(schema_version, migrated_at, invalidation_reason) VALUES (2, strftime('%s','now'), 'v1_turn_scoped_cursor_invalidation')"),
                  execute("DELETE FROM usage_samples"),
                  execute("DELETE FROM usage_cursors"),
                  execute("PRAGMA user_version = 2"),
                  execute("COMMIT") else {
                _ = execute("ROLLBACK")
                throw LedgerError.schema
            }
        }
        hasTokenEvidence = scalar("SELECT COUNT(*) FROM usage_cursors") > 0
    }

    private func cursorTotal(sourceKey: String) -> Int64? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT cumulative_total FROM usage_cursors WHERE source_key = ?", -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }; bind(sourceKey, statement, 1)
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : nil
    }

    private func upsertCursor(sourceKey: String, cumulative: Int64) {
        guard let database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO usage_cursors(source_key, cumulative_total) VALUES (?, ?) ON CONFLICT(source_key) DO UPDATE SET cumulative_total = excluded.cumulative_total", -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }; bind(sourceKey, statement, 1); sqlite3_bind_int64(statement, 2, cumulative); _ = sqlite3_step(statement)
    }

    private func execute(_ sql: String) -> Bool { guard let database else { return false }; return sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK }
    private func scalar(_ sql: String) -> Int64 { guard let database else { return -1 }; var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return -1 }; defer { sqlite3_finalize(statement) }; return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : -1 }
    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) { sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) }
    private func sqliteText(_ statement: OpaquePointer, _ index: Int32) -> String? { sqlite3_column_text(statement, index).map { String(cString: $0) } }
    private func publish() { let value = snapshot(); for continuation in continuations.values { continuation.yield(value) } }
    private func removeContinuation(_ id: UUID) { continuations.removeValue(forKey: id) }

    private enum LedgerError: Error { case open, schema, futureSchema }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
