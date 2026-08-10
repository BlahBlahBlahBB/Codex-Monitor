import Foundation
import Darwin
import CSQLite

/// The only approval source admitted by V3-2.  It is intentionally a local,
/// read-only, schema-gated log reader; it never responds to an approval.
public struct ApprovalLocalSourceID: Hashable, Sendable {
    public let value: SourceID
    public init?(_ value: String) { guard let value = SourceID(value) else { return nil }; self.value = value }
}

public struct ApprovalLogCursor: Hashable, Sendable, Equatable {
    public let fileIdentity: FileIdentity
    public let lastLogID: Int64
    public init(fileIdentity: FileIdentity, lastLogID: Int64) {
        self.fileIdentity = fileIdentity; self.lastLogID = lastLogID
    }
}

public struct ApprovalLogSchema: Sendable, Equatable {
    public let acceptedUserVersions: Set<Int32>
    public let tableName: String
    public let idColumn: String
    public let threadIDColumn: String
    public let timestampColumn: String
    public let targetColumn: String
    public let levelColumn: String
    public let bodyColumn: String

    public init(
        acceptedUserVersions: Set<Int32>,
        tableName: String = "logs",
        idColumn: String = "id",
        threadIDColumn: String = "thread_id",
        timestampColumn: String = "timestamp",
        targetColumn: String = "target",
        levelColumn: String = "level",
        bodyColumn: String = "body"
    ) {
        self.acceptedUserVersions = acceptedUserVersions
        self.tableName = tableName; self.idColumn = idColumn; self.threadIDColumn = threadIDColumn
        self.timestampColumn = timestampColumn; self.targetColumn = targetColumn
        self.levelColumn = levelColumn; self.bodyColumn = bodyColumn
    }

    fileprivate var requiredColumns: Set<String> {
        [idColumn, threadIDColumn, timestampColumn, targetColumn, levelColumn, bodyColumn]
    }

    fileprivate var isSafeSQLIdentifierSet: Bool {
        [tableName, idColumn, threadIDColumn, timestampColumn, targetColumn, levelColumn, bodyColumn].allSatisfy {
            !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        }
    }
}

public struct ApprovalDBRetryPolicy: Sendable, Equatable {
    public let attempts: Int
    public let busyTimeoutMilliseconds: Int32
    public let retryDelayMilliseconds: UInt32
    public let maximumRowsPerPoll: Int
    public init(attempts: Int = 3, busyTimeoutMilliseconds: Int32 = 50, retryDelayMilliseconds: UInt32 = 15, maximumRowsPerPoll: Int = 256) {
        self.attempts = max(1, attempts); self.busyTimeoutMilliseconds = max(0, busyTimeoutMilliseconds)
        self.retryDelayMilliseconds = retryDelayMilliseconds; self.maximumRowsPerPoll = max(1, maximumRowsPerPoll)
    }
}

public enum ApprovalResolutionStatus: String, CaseIterable, Sendable, Equatable {
    case approved, declined, cancelled, itemCompleted, terminal
}

public struct ApprovalRequested: Sendable, Equatable {
    public let threadID: NamespacedID
    public let turnID: NamespacedID
    public let requestID: NamespacedID
    public let observedAt: Date
}

public struct ApprovalResolved: Sendable, Equatable {
    public let threadID: NamespacedID
    public let turnID: NamespacedID
    public let requestID: NamespacedID
    public let status: ApprovalResolutionStatus
    public let observedAt: Date
}

public enum ApprovalSourceHealthState: String, Sendable, Equatable { case available, unavailable }
public enum ApprovalSourceHealthReason: String, Sendable, Equatable {
    case sourceMissing, fileIdentityChanged, schemaMismatch, busyExhausted, malformedRecord, cursorInvalid
}

public struct ApprovalSourceHealth: Sendable, Equatable {
    public let state: ApprovalSourceHealthState
    public let observedAt: Date
    public let reason: ApprovalSourceHealthReason?
    public init(state: ApprovalSourceHealthState, observedAt: Date, reason: ApprovalSourceHealthReason? = nil) {
        self.state = state; self.observedAt = observedAt; self.reason = reason
    }
}

/// Closed approval evidence.  No case transports log bodies, prompts, tool
/// arguments, command output, or chat text across the adapter boundary.
public enum ApprovalObservation: Sendable, Equatable {
    case requested(ApprovalRequested)
    case resolved(ApprovalResolved)
    case sourceUnavailable(ApprovalSourceHealth)
}

public struct ApprovalPollResult: Sendable, Equatable {
    public let observations: [ApprovalObservation]
    public let cursor: ApprovalLogCursor?
    public let health: ApprovalSourceHealth
    public init(observations: [ApprovalObservation], cursor: ApprovalLogCursor?, health: ApprovalSourceHealth) {
        self.observations = observations; self.cursor = cursor; self.health = health
    }
}

public enum ApprovalLocalAdapterError: Error, Equatable { case shutdown }

/// Incremental `logs_2.sqlite` reader.  The checkpoint is an explicit value so
/// a future Monitor-owned store can persist it without this adapter creating
/// any Monitor history or mutating Codex data.
public final class ApprovalLocalAdapter: @unchecked Sendable {
    private let databaseURL: URL
    private let sourceID: ApprovalLocalSourceID
    private let schema: ApprovalLogSchema
    private let retryPolicy: ApprovalDBRetryPolicy
    private var cursor: ApprovalLogCursor?
    private var seenLogIDs: Set<Int64> = []
    private var stopped = false

    public init(databaseURL: URL, sourceID: ApprovalLocalSourceID, schema: ApprovalLogSchema, checkpoint: ApprovalLogCursor? = nil, retryPolicy: ApprovalDBRetryPolicy = .init()) {
        self.databaseURL = databaseURL; self.sourceID = sourceID; self.schema = schema
        self.cursor = checkpoint; self.retryPolicy = retryPolicy
    }

    public func poll() throws -> ApprovalPollResult {
        guard !stopped else { throw ApprovalLocalAdapterError.shutdown }
        let now = Date()
        guard schema.isSafeSQLIdentifierSet, let identity = FileIdentity.readOnlyIdentity(of: databaseURL) else {
            return unavailable(.sourceMissing, at: now)
        }
        if let cursor, cursor.fileIdentity != identity { return unavailable(.fileIdentityChanged, at: now) }
        var lastBusy = false
        for attempt in 0..<retryPolicy.attempts {
            do { return try readOnce(identity: identity, at: now) }
            catch ApprovalReadError.busy {
                lastBusy = true
                if attempt + 1 < retryPolicy.attempts { usleep(retryPolicy.retryDelayMilliseconds * 1_000) }
            } catch ApprovalReadError.schema { return unavailable(.schemaMismatch, at: now) }
            catch ApprovalReadError.malformed { return unavailable(.malformedRecord, at: now) }
            catch { return unavailable(.sourceMissing, at: now) }
        }
        return unavailable(lastBusy ? .busyExhausted : .sourceMissing, at: now)
    }

    public func checkpoint() -> ApprovalLogCursor? { cursor }
    public func shutdown() { stopped = true; seenLogIDs.removeAll() }

    private func readOnce(identity: FileIdentity, at now: Date) throws -> ApprovalPollResult {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let database else { sqlite3_close(database); throw ApprovalReadError.source }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, retryPolicy.busyTimeoutMilliseconds)
        try validateSchema(database)
        let lastID = cursor?.lastLogID ?? 0
        let sql = "SELECT \(schema.idColumn), \(schema.threadIDColumn), \(schema.timestampColumn), \(schema.targetColumn), \(schema.levelColumn), \(schema.bodyColumn) FROM \(schema.tableName) WHERE \(schema.idColumn) > ? ORDER BY \(schema.idColumn) ASC LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error(for: database) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lastID)
        sqlite3_bind_int(statement, 2, Int32(retryPolicy.maximumRowsPerPoll))
        var observations: [ApprovalObservation] = []
        var advancedID = lastID
        while true {
            let stepped = sqlite3_step(statement)
            if stepped == SQLITE_DONE { break }
            guard stepped == SQLITE_ROW else { throw error(for: database) }
            guard let row = parseRow(statement) else { throw ApprovalReadError.malformed }
            advancedID = row.id
            guard seenLogIDs.insert(row.id).inserted else { continue }
            if let observation = try decode(row: row) { observations.append(observation) }
        }
        let next = ApprovalLogCursor(fileIdentity: identity, lastLogID: advancedID)
        cursor = next
        let health = ApprovalSourceHealth(state: .available, observedAt: now)
        return ApprovalPollResult(observations: observations, cursor: next, health: health)
    }

    private func validateSchema(_ database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK, let statement else { throw error(for: database) }
        defer { sqlite3_finalize(statement) }
        let versionStep = sqlite3_step(statement)
        guard versionStep == SQLITE_ROW else { throw error(for: database) }
        guard schema.acceptedUserVersions.contains(Int32(sqlite3_column_int64(statement, 0))) else { throw ApprovalReadError.schema }
        var columnsStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(schema.tableName))", -1, &columnsStatement, nil) == SQLITE_OK, let columnsStatement else { throw error(for: database) }
        defer { sqlite3_finalize(columnsStatement) }
        var columns = Set<String>()
        while true {
            let step = sqlite3_step(columnsStatement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw error(for: database) }
            if let value = sqliteText(columnsStatement, 1) { columns.insert(value) }
        }
        guard schema.requiredColumns.isSubset(of: columns) else { throw ApprovalReadError.schema }
    }

    private func parseRow(_ statement: OpaquePointer) -> ApprovalLogRow? {
        guard sqlite3_column_type(statement, 0) != SQLITE_NULL,
              sqlite3_column_type(statement, 1) != SQLITE_NULL,
              sqlite3_column_type(statement, 2) != SQLITE_NULL,
              let thread = sqliteText(statement, 1), let target = sqliteText(statement, 3),
              let level = sqliteText(statement, 4), let body = sqliteText(statement, 5) else { return nil }
        let timestamp = sqlite3_column_double(statement, 2)
        guard timestamp.isFinite, timestamp >= 0 else { return nil }
        let date = Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp)
        return ApprovalLogRow(id: sqlite3_column_int64(statement, 0), threadRawID: thread, observedAt: date, target: target, level: level, body: body)
    }

    private func decode(row: ApprovalLogRow) throws -> ApprovalObservation? {
        // `body` exists only inside this function and is discarded before the
        // observation escapes.  A non-allow-listed target/shape creates no
        // lifecycle fact; it can never be interpreted as a resolved approval.
        guard requestTargets.contains(row.target) || resolutionTargets.contains(row.target) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(row.body.utf8)) as? [String: Any],
              let threadID = NamespacedID(sourceID: sourceID.value, entityKind: .thread, rawID: row.threadRawID),
              let event = approvalEvent(in: object),
              let requestRaw = string(in: object, keys: ["request_id", "requestId", "call_id", "callId"]),
              let turnRaw = string(in: object, keys: ["turn_id", "turnId"]),
              let requestID = NamespacedID(sourceID: sourceID.value, entityKind: .item, rawID: requestRaw),
              let turnID = NamespacedID(sourceID: sourceID.value, entityKind: .turn, rawID: turnRaw) else { throw ApprovalReadError.malformed }
        switch event {
        case .request where requestTargets.contains(row.target):
            return .requested(ApprovalRequested(threadID: threadID, turnID: turnID, requestID: requestID, observedAt: row.observedAt))
        case .resolution(let status) where resolutionTargets.contains(row.target):
            return .resolved(ApprovalResolved(threadID: threadID, turnID: turnID, requestID: requestID, status: status, observedAt: row.observedAt))
        default:
            throw ApprovalReadError.malformed
        }
    }

    private func unavailable(_ reason: ApprovalSourceHealthReason, at date: Date) -> ApprovalPollResult {
        let health = ApprovalSourceHealth(state: .unavailable, observedAt: date, reason: reason)
        return ApprovalPollResult(observations: [.sourceUnavailable(health)], cursor: cursor, health: health)
    }

    private func error(for database: OpaquePointer) -> ApprovalReadError {
        let code = sqlite3_errcode(database)
        return code == SQLITE_BUSY || code == SQLITE_LOCKED ? .busy : .source
    }
}

private enum ApprovalReadError: Error { case source, busy, schema, malformed }
private struct ApprovalLogRow { let id: Int64; let threadRawID: String; let observedAt: Date; let target: String; let level: String; let body: String }
private enum ApprovalEvent { case request, resolution(ApprovalResolutionStatus) }
private let requestTargets: Set<String> = ["item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval", "autoReview/requestApproval"]
private let resolutionTargets: Set<String> = ["serverRequest/resolved", "item/commandExecution/approvalResolved", "item/fileChange/approvalResolved", "item/permissions/approvalResolved", "autoReview/approvalResolved"]

private func sqliteText(_ statement: OpaquePointer, _ column: Int32) -> String? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL, let value = sqlite3_column_text(statement, column) else { return nil }
    return String(cString: value)
}

private func approvalEvent(in object: [String: Any]) -> ApprovalEvent? {
    let value = string(in: object, keys: ["event", "type", "method", "status"])
    switch value {
    case "requestApproval", "waitingOnApproval": return .request
    case "approved", "approve": return .resolution(.approved)
    case "declined", "deny": return .resolution(.declined)
    case "cancelled", "canceled": return .resolution(.cancelled)
    case "itemCompleted", "item_completed": return .resolution(.itemCompleted)
    case "terminal": return .resolution(.terminal)
    default: return nil
    }
}

private func string(in object: [String: Any], keys: [String]) -> String? {
    for key in keys { if let value = object[key] as? String, !value.isEmpty { return value } }
    for nestedKey in ["params", "payload", "data"] {
        if let nested = object[nestedKey] as? [String: Any], let value = string(in: nested, keys: keys) { return value }
    }
    return nil
}
