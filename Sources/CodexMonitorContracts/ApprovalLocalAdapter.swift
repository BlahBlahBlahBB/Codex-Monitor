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
        timestampColumn: String = "ts",
        targetColumn: String = "target",
        levelColumn: String = "level",
        bodyColumn: String = "feedback_log_body"
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

/// Persisted by the Monitor alongside the cursor so a restart cannot forget an
/// already-admitted, unresolved approval that lies before the next cursor.
/// It intentionally contains identities and timestamps only, never log text.
public struct ApprovalLifecycleCheckpoint: Sendable, Equatable {
    public let cursor: ApprovalLogCursor?
    public let unresolved: [ApprovalRequested]
    public init(cursor: ApprovalLogCursor?, unresolved: [ApprovalRequested]) {
        self.cursor = cursor
        self.unresolved = unresolved.sorted { $0.requestID.rawID < $1.requestID.rawID }
    }
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
    case sourceHealth(ApprovalSourceHealth)
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
    private var unresolved: [NamespacedID: ApprovalRequested] = [:]
    private var stopped = false

    public init(databaseURL: URL, sourceID: ApprovalLocalSourceID, schema: ApprovalLogSchema, checkpoint: ApprovalLogCursor? = nil, retryPolicy: ApprovalDBRetryPolicy = .init()) {
        self.databaseURL = databaseURL; self.sourceID = sourceID; self.schema = schema
        self.cursor = checkpoint; self.retryPolicy = retryPolicy
    }

    public convenience init(databaseURL: URL, sourceID: ApprovalLocalSourceID, schema: ApprovalLogSchema, lifecycleCheckpoint: ApprovalLifecycleCheckpoint, retryPolicy: ApprovalDBRetryPolicy = .init()) {
        self.init(databaseURL: databaseURL, sourceID: sourceID, schema: schema, checkpoint: lifecycleCheckpoint.cursor, retryPolicy: retryPolicy)
        self.unresolved = Dictionary(uniqueKeysWithValues: lifecycleCheckpoint.unresolved.map { ($0.requestID, $0) })
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
    public func lifecycleCheckpoint() -> ApprovalLifecycleCheckpoint { ApprovalLifecycleCheckpoint(cursor: cursor, unresolved: Array(unresolved.values)) }
    public func shutdown() { stopped = true; unresolved.removeAll() }

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
        var nextUnresolved = unresolved
        while true {
            let stepped = sqlite3_step(statement)
            if stepped == SQLITE_DONE { break }
            guard stepped == SQLITE_ROW else { throw error(for: database) }
            guard let row = parseRow(statement) else { throw ApprovalReadError.malformed }
            // No cursor or lifecycle mutation occurs until the entire bounded
            // batch has decoded and been admitted.  A repeated malformed row
            // therefore stays unavailable rather than self-healing on poll 2.
            guard let observation = try decode(row: row) else { advancedID = row.id; continue }
            switch observation {
            case .requested(let request): nextUnresolved[request.requestID] = request
            case .resolved(let resolution):
                guard nextUnresolved[resolution.requestID]?.threadID == resolution.threadID,
                      nextUnresolved[resolution.requestID]?.turnID == resolution.turnID else { break }
                nextUnresolved.removeValue(forKey: resolution.requestID)
            case .sourceHealth, .sourceUnavailable: break
            }
            observations.append(observation)
            advancedID = row.id
        }
        let next = ApprovalLogCursor(fileIdentity: identity, lastLogID: advancedID)
        // This is the single successful admission commit point.
        cursor = next; unresolved = nextUnresolved
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
        // Installed 0.147 evidence pins this exact logger target.  The body is
        // structured text, not a whole-body JSON contract.  It is inspected
        // transiently by a closed marker parser and discarded immediately.
        guard row.target == installedLoggerTarget else { return nil }
        guard let structured = StructuredApprovalBody.parse(row.body) else {
            // Ordinary stream-event rows are irrelevant.  A row that claims an
            // approval marker but is not one pinned observed shape fails closed.
            if StructuredApprovalBody.mentionsApproval(row.body) { throw ApprovalReadError.malformed }
            return nil
        }
        guard let threadID = NamespacedID(sourceID: sourceID.value, entityKind: .thread, rawID: row.threadRawID),
              let requestID = NamespacedID(sourceID: sourceID.value, entityKind: .item, rawID: structured.requestID),
              let turnID = NamespacedID(sourceID: sourceID.value, entityKind: .turn, rawID: structured.turnID) else { throw ApprovalReadError.malformed }
        if let bodyThread = structured.threadID, bodyThread != row.threadRawID { throw ApprovalReadError.malformed }
        switch structured.variant {
        case .request:
            return .requested(ApprovalRequested(threadID: threadID, turnID: turnID, requestID: requestID, observedAt: row.observedAt))
        case .resolution(let status):
            return .resolved(ApprovalResolved(threadID: threadID, turnID: turnID, requestID: requestID, status: status, observedAt: row.observedAt))
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
private let installedLoggerTarget = "codex_core::stream_events_utils"

private func sqliteText(_ statement: OpaquePointer, _ column: Int32) -> String? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL, let value = sqlite3_column_text(statement, column) else { return nil }
    return String(cString: value)
}

private enum StructuredApprovalVariant { case request, resolution(ApprovalResolutionStatus) }
private struct StructuredApprovalBody {
    let variant: StructuredApprovalVariant
    let threadID: String?
    let turnID: String
    let requestID: String

    static func mentionsApproval(_ body: String) -> Bool {
        ["requestApproval", "waitingOnApproval", "approvalResolved", "approvalApproved", "approvalDeclined", "approvalCancelled", "itemCompleted", "approvalTerminal"].contains { containsMarker($0, in: body) }
    }

    static func parse(_ body: String) -> StructuredApprovalBody? {
        // Pinned observed structured-text grammar: recognized variant marker +
        // exact correlation key/value markers.  Delimiters may be logfmt (=)
        // or an embedded structured fragment (:); accepting neither JSON as a
        // whole nor arbitrary nested maps prevents target-lookalike admission.
        let fields = [
            "thread_id": field("thread_id", in: body),
            "turn_id": field("turn_id", in: body),
            "request_id": field("request_id", in: body) ?? field("call_id", in: body) ?? field("item_id", in: body)
        ]
        guard let turn = fields["turn_id"]!, let request = fields["request_id"]! else { return nil }
        let requestMarkers = containsMarker("requestApproval", in: body) && containsMarker("waitingOnApproval", in: body)
        let resolution: ApprovalResolutionStatus? = containsMarker("approvalApproved", in: body) ? .approved :
            (containsMarker("approvalDeclined", in: body) ? .declined :
            (containsMarker("approvalCancelled", in: body) ? .cancelled :
            (containsMarker("itemCompleted", in: body) ? .itemCompleted : (containsMarker("approvalTerminal", in: body) ? .terminal : nil))))
        if requestMarkers, resolution == nil { return StructuredApprovalBody(variant: .request, threadID: fields["thread_id"]!, turnID: turn, requestID: request) }
        if !requestMarkers, let resolution { return StructuredApprovalBody(variant: .resolution(resolution), threadID: fields["thread_id"]!, turnID: turn, requestID: request) }
        return nil
    }

    private static func field(_ key: String, in body: String) -> String? {
        // Closed, bounded ID grammar.  It keeps arbitrary structured-body text
        // from being transported and rejects partial/ambiguous values.
        let pattern = "(?:\\\"|\\b)" + NSRegularExpression.escapedPattern(for: key) + "(?:\\\")?\\s*(?:=|:)\\s*(?:\\\")?([A-Za-z0-9._:-]{1,256})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
        guard matches.count == 1, let match = matches.first,
              let range = Range(match.range(at: 1), in: body) else { return nil }
        return String(body[range])
    }

    private static func containsMarker(_ marker: String, in body: String) -> Bool {
        let pattern = "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: marker) + "(?![A-Za-z0-9_])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) != nil
    }
}
