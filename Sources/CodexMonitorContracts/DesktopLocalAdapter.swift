import Foundation
import Darwin
import CSQLite

/// A local Codex installation is a namespace, not merely a directory.  Every
/// thread, turn and item emitted by this adapter uses this source identity.
public struct DesktopLocalSourceID: Hashable, Sendable {
    public let value: SourceID
    public init?(_ value: String) { guard let value = SourceID(value) else { return nil }; self.value = value }
}

/// PID reuse is possible.  A process may be considered the same owner only
/// when both values match; this adapter never signals or otherwise controls it.
public struct ProcessEpoch: Hashable, Sendable, Equatable {
    public let pid: Int32
    public let startedAtNanoseconds: UInt64
    public init?(pid: Int32, startedAtNanoseconds: UInt64) {
        guard pid > 0 else { return nil }
        self.pid = pid; self.startedAtNanoseconds = startedAtNanoseconds
    }
}

public struct FileIdentity: Hashable, Sendable, Equatable {
    public let device: UInt64
    public let inode: UInt64
    public init(device: UInt64, inode: UInt64) { self.device = device; self.inode = inode }

    public static func readOnlyIdentity(of url: URL) -> FileIdentity? {
        var attributes = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Int(lstat(path, &attributes))
        }
        guard result == 0 else { return nil }
        return FileIdentity(device: UInt64(attributes.st_dev), inode: UInt64(attributes.st_ino))
    }
}

public struct RolloutCursor: Hashable, Sendable, Equatable {
    public let fileIdentity: FileIdentity
    public let byteOffset: UInt64
    public let modificationTime: Date
    public init(fileIdentity: FileIdentity, byteOffset: UInt64, modificationTime: Date) {
        self.fileIdentity = fileIdentity; self.byteOffset = byteOffset; self.modificationTime = modificationTime
    }
}

/// The state DB is the sole authority for this path.  It is retained in memory
/// only and deliberately has no Codable conformance, so diagnostics cannot
/// serialize a private filesystem location.
public struct ThreadRolloutBinding: Sendable, Equatable {
    public let sourceID: DesktopLocalSourceID
    public let threadID: NamespacedID
    public let rolloutURL: URL
    public let sessionID: String
    public init?(sourceID: DesktopLocalSourceID, threadRawID: String, rolloutURL: URL, sessionID: String) {
        guard let threadID = NamespacedID(sourceID: sourceID.value, entityKind: .thread, rawID: threadRawID),
              !sessionID.isEmpty else { return nil }
        self.sourceID = sourceID; self.threadID = threadID; self.rolloutURL = rolloutURL; self.sessionID = sessionID
    }
}

public enum DesktopSourceHealthState: String, Sendable, Equatable { case available, unavailable }
public enum DesktopSourceHealthReason: String, Sendable, Equatable {
    case sourceMissing, processEpochMismatch, checkpointAdmissionPending, writerOwnershipMissing, fileIdentityChanged, fileTruncated, schemaUnavailable
}

/// Health evidence only.  It deliberately has no Failed, Interrupted, or task
/// lifecycle case; a later state engine decides product projection.
public struct DesktopSourceHealth: Sendable, Equatable {
    public let threadID: NamespacedID
    public let state: DesktopSourceHealthState
    public let processEpoch: ProcessEpoch?
    public let fileIdentity: FileIdentity?
    public let reason: DesktopSourceHealthReason?
    public init(threadID: NamespacedID, state: DesktopSourceHealthState, processEpoch: ProcessEpoch?, fileIdentity: FileIdentity?, reason: DesktopSourceHealthReason? = nil) {
        self.threadID = threadID; self.state = state; self.processEpoch = processEpoch; self.fileIdentity = fileIdentity; self.reason = reason
    }
}

public struct DesktopThreadSnapshot: Sendable, Equatable {
    public let threadID: NamespacedID
    public let title: String?
    public let model: String?
    public let reasoningEffort: String?
    public let updatedAtMilliseconds: Int64?
    /// A same-thread cross-check only; it is never merged with account usage.
    public let tokensUsed: Int64?
    public init(threadID: NamespacedID, title: String?, model: String?, reasoningEffort: String?, updatedAtMilliseconds: Int64?, tokensUsed: Int64?) {
        self.threadID = threadID; self.title = title; self.model = model; self.reasoningEffort = reasoningEffort
        self.updatedAtMilliseconds = updatedAtMilliseconds; self.tokensUsed = tokensUsed
    }
}

public enum RolloutActivityCategory: String, Sendable, Equatable { case thinking, tool, fileChange, agentResponse }
public enum RolloutEventKind: String, Sendable, Equatable {
    case sessionMeta, taskStarted, activity, tokenCount, taskCompletedSuccess, taskCompletedFailure, turnAbortedInterrupted, turnContext
}

public struct TokenSnapshot: Sendable, Equatable {
    public let totalTokens: Int64
    public let lastCallTokens: Int64?
    public init(totalTokens: Int64, lastCallTokens: Int64?) { self.totalTokens = totalTokens; self.lastCallTokens = lastCallTokens }
}

public struct RolloutRecordEnvelope: Sendable, Equatable {
    public let threadID: NamespacedID
    public let turnID: NamespacedID?
    public let itemID: NamespacedID?
    public let kind: RolloutEventKind
    public let activity: RolloutActivityCategory?
    public let tokenSnapshot: TokenSnapshot?
    public let model: String?
    public let reasoningEffort: String?
    /// Stable per-record identity when the rollout source exposes one.  It is
    /// used only in-memory/checkpoints for terminal replay admission.
    public let eventID: String?
    /// Source event time, distinct from the time the monitor decoded it.
    /// Retention always uses this value when supplied.
    public let authoritativeEventAt: Date?
    public let observedAt: Date
    public let fileOffset: UInt64

    public init(threadID: NamespacedID, turnID: NamespacedID?, itemID: NamespacedID?, kind: RolloutEventKind, activity: RolloutActivityCategory?, tokenSnapshot: TokenSnapshot?, model: String?, reasoningEffort: String?, eventID: String? = nil, authoritativeEventAt: Date? = nil, observedAt: Date, fileOffset: UInt64) {
        self.threadID = threadID; self.turnID = turnID; self.itemID = itemID
        self.kind = kind; self.activity = activity; self.tokenSnapshot = tokenSnapshot
        self.model = model; self.reasoningEffort = reasoningEffort
        self.eventID = eventID; self.authoritativeEventAt = authoritativeEventAt
        self.observedAt = observedAt; self.fileOffset = fileOffset
    }
}

public enum DesktopCapability: String, Sendable, Equatable { case stateDatabase, rolloutFormat, rolloutSessionIdentity, sessionToken }
public enum DesktopObservation: Sendable, Equatable {
    case rollout(RolloutRecordEnvelope)
    case sourceHealth(DesktopSourceHealth)
    case capabilityUnavailable(threadID: NamespacedID, capability: DesktopCapability)
}

public enum StateDBError: Error, Equatable {
    case unavailable, busyExhausted, schemaMismatch, readOnlyOpenFailed, queryFailed
}

public struct StateDBSchema: Sendable, Equatable {
    public let acceptedUserVersions: Set<Int32>
    public init(acceptedUserVersions: Set<Int32>) { self.acceptedUserVersions = acceptedUserVersions }
}

public struct StateDBRetryPolicy: Sendable, Equatable {
    public let attempts: Int
    public let busyTimeoutMilliseconds: Int32
    public let retryDelayMilliseconds: UInt32
    public init(attempts: Int = 3, busyTimeoutMilliseconds: Int32 = 50, retryDelayMilliseconds: UInt32 = 15) {
        self.attempts = max(1, attempts); self.busyTimeoutMilliseconds = max(0, busyTimeoutMilliseconds)
        self.retryDelayMilliseconds = retryDelayMilliseconds
    }
}

public struct StateDBThreadRecord: Sendable, Equatable {
    public let snapshot: DesktopThreadSnapshot
    /// Retained in memory for reader binding only, never sent to diagnostics.
    public let rolloutURL: URL
}

/// The only state DB API in this phase.  It opens SQLite with SQLITE_OPEN_READONLY
/// and has no SQL execution path for mutations.
public final class StateDBReader: @unchecked Sendable {
    private let databaseURL: URL
    private let sourceID: DesktopLocalSourceID
    private let schema: StateDBSchema
    private let retryPolicy: StateDBRetryPolicy

    public init(databaseURL: URL, sourceID: DesktopLocalSourceID, schema: StateDBSchema, retryPolicy: StateDBRetryPolicy = .init()) {
        self.databaseURL = databaseURL; self.sourceID = sourceID; self.schema = schema; self.retryPolicy = retryPolicy
    }

    public func thread(rawID: String) throws -> StateDBThreadRecord? {
        var lastError: StateDBError = .unavailable
        for attempt in 0..<retryPolicy.attempts {
            do { return try readThreadOnce(rawID: rawID) }
            catch let error as StateDBError where error == .busyExhausted {
                lastError = error
                if attempt + 1 < retryPolicy.attempts { usleep(retryPolicy.retryDelayMilliseconds * 1_000) }
            } catch let error as StateDBError { throw error }
        }
        throw lastError
    }

    private func readThreadOnce(rawID: String) throws -> StateDBThreadRecord? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &database, flags, nil)
        guard result == SQLITE_OK, let database else { sqlite3_close(database); throw StateDBError.readOnlyOpenFailed }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, retryPolicy.busyTimeoutMilliseconds)
        let version = try scalarInt(database, sql: "PRAGMA user_version")
        guard schema.acceptedUserVersions.contains(Int32(version)) else { throw StateDBError.schemaMismatch }
        let columns = try tableColumns(database, table: "threads")
        let required: Set<String> = ["id", "rollout_path", "title", "model", "reasoning_effort", "updated_at", "tokens_used"]
        guard required.isSubset(of: columns) else { throw StateDBError.schemaMismatch }
        let sql = "SELECT id, rollout_path, title, model, reasoning_effort, updated_at, tokens_used FROM threads WHERE id = ? LIMIT 1"
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw stateError(for: database) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, rawID, -1, SQLITE_TRANSIENT)
        let stepped = sqlite3_step(statement)
        if stepped == SQLITE_DONE { return nil }
        guard stepped == SQLITE_ROW else { throw stateError(for: database) }
        guard let id = text(statement, column: 0), id == rawID,
              let path = text(statement, column: 1),
              let threadID = NamespacedID(sourceID: sourceID.value, entityKind: .thread, rawID: id) else { throw StateDBError.schemaMismatch }
        let snapshot = DesktopThreadSnapshot(threadID: threadID, title: text(statement, column: 2), model: text(statement, column: 3), reasoningEffort: text(statement, column: 4), updatedAtMilliseconds: integer(statement, column: 5), tokensUsed: integer(statement, column: 6))
        return StateDBThreadRecord(snapshot: snapshot, rolloutURL: URL(fileURLWithPath: path))
    }

    private func scalarInt(_ database: OpaquePointer, sql: String) throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw stateError(for: database) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw stateError(for: database) }
        return sqlite3_column_int64(statement, 0)
    }

    private func tableColumns(_ database: OpaquePointer, table: String) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(threads)", -1, &statement, nil) == SQLITE_OK, let statement else { throw stateError(for: database) }
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW { if let value = text(statement, column: 1) { columns.insert(value) } }
        return columns
    }

    private func stateError(for database: OpaquePointer) -> StateDBError {
        let code = sqlite3_errcode(database)
        return code == SQLITE_BUSY || code == SQLITE_LOCKED ? .busyExhausted : .queryFailed
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private func text(_ statement: OpaquePointer, column: Int32) -> String? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL, let value = sqlite3_column_text(statement, column) else { return nil }
    return String(cString: value)
}
private func integer(_ statement: OpaquePointer, column: Int32) -> Int64? {
    sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, column)
}

public enum RolloutReadInvalidation: Sendable, Equatable { case fileMissing, fileTruncated, fileReplaced, sessionMismatch }
public struct RolloutReadResult: Sendable, Equatable {
    public let observations: [DesktopObservation]
    public let cursor: RolloutCursor?
    public let invalidation: RolloutReadInvalidation?
    /// Reconstructed only from the exact descriptor before a persisted cursor.
    /// It contains IDs and source times, never rollout content.
    public let hydration: RolloutCheckpointHydration?
    public init(observations: [DesktopObservation], cursor: RolloutCursor?, invalidation: RolloutReadInvalidation?, hydration: RolloutCheckpointHydration? = nil) {
        self.observations = observations; self.cursor = cursor; self.invalidation = invalidation; self.hydration = hydration
    }
}

public struct RolloutCheckpointHydration: Sendable, Equatable {
    public let activeTurnID: NamespacedID?
    public let turnStartedAt: Date?
    public let activeItemID: NamespacedID?
    public let activeItemCategory: RolloutActivityCategory?
    public let latestActiveState: MonitorRuntimeState?
    public let latestActiveStateAt: Date?
    public let terminal: ReconciledTerminal?
    public let authoritativeTokenTotal: Int64?
    public init(activeTurnID: NamespacedID?, turnStartedAt: Date?, activeItemID: NamespacedID?, activeItemCategory: RolloutActivityCategory?, latestActiveState: MonitorRuntimeState?, latestActiveStateAt: Date?, terminal: ReconciledTerminal?, authoritativeTokenTotal: Int64?) {
        self.activeTurnID = activeTurnID; self.turnStartedAt = turnStartedAt; self.activeItemID = activeItemID; self.activeItemCategory = activeItemCategory
        self.latestActiveState = latestActiveState; self.latestActiveStateAt = latestActiveStateAt; self.terminal = terminal; self.authoritativeTokenTotal = authoritativeTokenTotal
    }
}

/// Incremental, file-identity-aware JSONL reader.  It never scans an entire
/// rollout: first admission reads a bounded header plus tail; later reads only
/// appended bytes, preserving a partial final line in memory.
public final class RolloutIncrementalReader: @unchecked Sendable {
    public let binding: ThreadRolloutBinding
    private let maxHeaderBytes: UInt64
    private let maxTailBytes: UInt64
    private let maxAppendBytes: Int
    private var cursor: RolloutCursor?
    private var partialLine = Data()
    private var sessionValidated = false
    private var activeTurnID: NamespacedID?
    private var lastTokenTotal: Int64?
    private var activeTurnStartedAt: Date?
    private var activeItemID: NamespacedID?
    private var activeItemCategory: RolloutActivityCategory?
    private var latestActiveState: MonitorRuntimeState?
    private var latestActiveStateAt: Date?
    private var latestTerminal: ReconciledTerminal?
    /// An exact open binds a descriptor identity before it is allowed to own a
    /// thread.  Every later poll compares its *opened* descriptor to this value.
    private var admittedIdentity: FileIdentity?
    private var checkpointNeedsStateDBRevalidation: Bool
    /// Test-only deterministic seam: it runs immediately before the one
    /// descriptor for a transaction is opened.  It models an atomic pathname
    /// replacement without ever making production reads path-racy.
    private let beforeDescriptorOpen: (() -> Void)?

    public init(binding: ThreadRolloutBinding, checkpoint: RolloutCursor? = nil, maxHeaderBytes: UInt64 = 65_536, maxTailBytes: UInt64 = 1_048_576, maxAppendBytes: Int = 262_144) {
        self.binding = binding; self.cursor = checkpoint; self.maxHeaderBytes = maxHeaderBytes; self.maxTailBytes = maxTailBytes; self.maxAppendBytes = maxAppendBytes
        self.checkpointNeedsStateDBRevalidation = checkpoint != nil
        self.beforeDescriptorOpen = nil
    }

    init(binding: ThreadRolloutBinding, checkpoint: RolloutCursor? = nil, maxHeaderBytes: UInt64 = 65_536, maxTailBytes: UInt64 = 1_048_576, maxAppendBytes: Int = 262_144, beforeDescriptorOpen: (() -> Void)?) {
        self.binding = binding; self.cursor = checkpoint; self.maxHeaderBytes = maxHeaderBytes; self.maxTailBytes = maxTailBytes; self.maxAppendBytes = maxAppendBytes
        self.checkpointNeedsStateDBRevalidation = checkpoint != nil
        self.beforeDescriptorOpen = beforeDescriptorOpen
    }

    /// Admission is deliberately non-consuming.  `open` uses it before it
    /// clears an epoch latch, so a path/session lookalike cannot become a new
    /// owner merely because its DB row is plausible.
    func admitExactBinding() -> RolloutReadInvalidation? {
        guard let transaction = openTransaction() else { return .fileMissing }
        defer { transaction.close() }
        guard let header = read(transaction, offset: 0, count: Int(min(transaction.size, maxHeaderBytes))), validateSession(in: header) else {
            return .sessionMismatch
        }
        admittedIdentity = transaction.identity
        return nil
    }

    var requiresCheckpointStateDBRevalidation: Bool { checkpointNeedsStateDBRevalidation }

    func confirmCheckpointStateDBRevalidation() { checkpointNeedsStateDBRevalidation = false }

    func checkpointStateDBUnavailable() -> RolloutReadResult {
        RolloutReadResult(observations: [.capabilityUnavailable(threadID: binding.threadID, capability: .stateDatabase)], cursor: cursor, invalidation: .sessionMismatch)
    }

    public func poll() -> RolloutReadResult {
        guard let transaction = openTransaction() else {
            return RolloutReadResult(observations: [.sourceHealth(health(.unavailable, reason: .sourceMissing, identity: nil))], cursor: cursor, invalidation: .fileMissing)
        }
        defer { transaction.close() }
        let identity = transaction.identity
        let size = transaction.size
        let modified = transaction.modified
        if let admittedIdentity, admittedIdentity != identity {
            return invalidated(.fileReplaced, reason: .fileIdentityChanged, identity: identity)
        }
        if let cursor {
            if cursor.fileIdentity != identity {
                return invalidated(.fileReplaced, reason: .fileIdentityChanged, identity: identity)
            }
            if size < cursor.byteOffset { return invalidated(.fileTruncated, reason: .fileTruncated, identity: identity) }
            if !sessionValidated {
                return resumeCheckpoint(transaction: transaction, identity: identity, size: size, modified: modified, from: cursor.byteOffset)
            }
            return appended(transaction: transaction, identity: identity, size: size, modified: modified, from: cursor.byteOffset)
        }
        return bootstrap(transaction: transaction, identity: identity, size: size, modified: modified)
    }

    private func bootstrap(transaction: OpenedRollout, identity: FileIdentity, size: UInt64, modified: Date) -> RolloutReadResult {
        guard let header = read(transaction, offset: 0, count: Int(min(size, maxHeaderBytes))), validateSession(in: header) else {
            return RolloutReadResult(observations: [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutSessionIdentity)], cursor: nil, invalidation: .sessionMismatch)
        }
        sessionValidated = true
        if size <= maxHeaderBytes {
            let result = consume(header, identity: identity, offset: 0, endingOffset: size, modified: modified, skipFirstPartial: false)
            return RolloutReadResult(observations: result.observations, cursor: result.cursor, invalidation: result.invalidation, hydration: checkpointHydration())
        }
        let start = size - min(size, maxTailBytes)
        guard let tail = read(transaction, offset: start, count: Int(size - start)) else { return invalidated(.fileMissing, reason: .sourceMissing, identity: identity) }
        let result = consume(tail, identity: identity, offset: start, endingOffset: size, modified: modified, skipFirstPartial: start > 0)
        return RolloutReadResult(observations: result.observations, cursor: result.cursor, invalidation: result.invalidation, hydration: checkpointHydration())
    }

    /// A persisted cursor contains no raw rollout content or decoded state.  On
    /// its first use, reconstruct only the bounded tail needed for turn/token
    /// continuity, discard those historical observations, then consume new
    /// bytes from the same verified descriptor.
    private func resumeCheckpoint(transaction: OpenedRollout, identity: FileIdentity, size: UInt64, modified: Date, from offset: UInt64) -> RolloutReadResult {
        guard !checkpointNeedsStateDBRevalidation else { return checkpointStateDBUnavailable() }
        guard let header = read(transaction, offset: 0, count: Int(min(size, maxHeaderBytes))), validateSession(in: header) else {
            return RolloutReadResult(observations: [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutSessionIdentity)], cursor: cursor, invalidation: .sessionMismatch)
        }
        let reconstructionStart = offset - min(offset, maxTailBytes)
        guard let reconstruction = read(transaction, offset: reconstructionStart, count: Int(offset - reconstructionStart)) else {
            return invalidated(.fileMissing, reason: .sourceMissing, identity: identity)
        }
        reconstructCheckpointState(from: reconstruction, offset: reconstructionStart, skipFirstPartial: reconstructionStart > 0)
        sessionValidated = true
        let appended = appended(transaction: transaction, identity: identity, size: size, modified: modified, from: offset)
        return RolloutReadResult(observations: appended.observations, cursor: appended.cursor, invalidation: appended.invalidation, hydration: checkpointHydration())
    }

    private func reconstructCheckpointState(from bytes: Data, offset: UInt64, skipFirstPartial: Bool) {
        activeTurnID = nil
        lastTokenTotal = nil
        activeTurnStartedAt = nil; activeItemID = nil; activeItemCategory = nil
        latestActiveState = nil; latestActiveStateAt = nil; latestTerminal = nil
        partialLine = Data()
        let lines = bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
        let endedWithNewline = bytes.last == 0x0A
        let completeCount = endedWithNewline ? lines.count - 1 : max(0, lines.count - 1)
        var lineOffset = offset
        for index in 0..<completeCount {
            let line = Data(lines[index])
            defer { lineOffset += UInt64(line.count + 1) }
            if skipFirstPartial && index == 0 { continue }
            _ = decode(line: line, offset: lineOffset)
        }
        if !endedWithNewline { partialLine = Data(lines.last ?? Data()) }
    }

    private func appended(transaction: OpenedRollout, identity: FileIdentity, size: UInt64, modified: Date, from offset: UInt64) -> RolloutReadResult {
        guard size > offset else { return RolloutReadResult(observations: [.sourceHealth(health(.available, reason: nil, identity: identity))], cursor: cursor, invalidation: nil) }
        let count = Int(min(UInt64(maxAppendBytes), size - offset))
        guard let bytes = read(transaction, offset: offset, count: count) else { return invalidated(.fileMissing, reason: .sourceMissing, identity: identity) }
        return consume(bytes, identity: identity, offset: offset, endingOffset: offset + UInt64(bytes.count), modified: modified, skipFirstPartial: false)
    }

    private func consume(_ bytes: Data, identity: FileIdentity, offset: UInt64, endingOffset: UInt64, modified: Date, skipFirstPartial: Bool) -> RolloutReadResult {
        var data = partialLine; data.append(bytes)
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        let endedWithNewline = data.last == 0x0A
        partialLine = endedWithNewline ? Data() : Data(lines.last ?? Data())
        let completeCount = endedWithNewline ? lines.count - 1 : max(0, lines.count - 1)
        var observations: [DesktopObservation] = [.sourceHealth(health(.available, reason: nil, identity: identity))]
        var lineOffset = offset
        for index in 0..<completeCount {
            let line = Data(lines[index])
            defer { lineOffset += UInt64(line.count + 1) }
            if skipFirstPartial && index == 0 { continue }
            observations.append(contentsOf: decode(line: line, offset: lineOffset))
        }
        let next = RolloutCursor(fileIdentity: identity, byteOffset: endingOffset, modificationTime: modified)
        cursor = next
        return RolloutReadResult(observations: observations, cursor: next, invalidation: nil)
    }

    private func validateSession(in data: Data) -> Bool {
        for slice in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(slice)) as? [String: Any], object["type"] as? String == "session_meta",
                  let payload = object["payload"] as? [String: Any], let id = payload["id"] as? String else { continue }
            return id == binding.sessionID
        }
        return false
    }

    private func decode(line: Data, offset: UInt64) -> [DesktopObservation] {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let outerType = object["type"] as? String else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
        if outerType == "session_meta" { return [] }
        guard let payload = object["payload"] as? [String: Any] else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
        let observedAt = Date()
        let sourceAt = sourceDate(object["timestamp"])
        func envelope(_ kind: RolloutEventKind, turn: NamespacedID? = activeTurnID, itemRaw: String? = nil, activity: RolloutActivityCategory? = nil, token: TokenSnapshot? = nil, model: String? = nil, effort: String? = nil, eventID: String? = nil, authoritativeAt: Date? = sourceAt) -> DesktopObservation {
            let item = itemRaw.flatMap { NamespacedID(sourceID: binding.sourceID.value, entityKind: .item, rawID: $0) }
            let record = RolloutRecordEnvelope(threadID: binding.threadID, turnID: turn, itemID: item, kind: kind, activity: activity, tokenSnapshot: token, model: model, reasoningEffort: effort, eventID: eventID, authoritativeEventAt: authoritativeAt, observedAt: observedAt, fileOffset: offset)
            applyDecodedState(record)
            return .rollout(record)
        }
        let type = payload["type"] as? String
        switch (outerType, type) {
        case ("event_msg", "task_started"):
            guard let rawTurn = payload["turn_id"] as? String, number(payload["started_at"]) != nil,
                  let turn = NamespacedID(sourceID: binding.sourceID.value, entityKind: .turn, rawID: rawTurn) else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            activeTurnID = turn; return [envelope(.taskStarted, turn: turn)]
        case ("event_msg", "token_count"):
            guard let info = payload["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any], let totalTokens = number(total["total_tokens"]) else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .sessionToken)] }
            guard let turn = activeTurnID else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            let last = (info["last_token_usage"] as? [String: Any]).flatMap { number($0["total_tokens"]) }
            guard lastTokenTotal != totalTokens else { return [] }
            lastTokenTotal = totalTokens
            return [envelope(.tokenCount, turn: turn, token: TokenSnapshot(totalTokens: totalTokens, lastCallTokens: last))]
        case ("event_msg", "task_complete"):
            guard let rawTurn = payload["turn_id"] as? String, let turn = NamespacedID(sourceID: binding.sourceID.value, entityKind: .turn, rawID: rawTurn) else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            let error = payload["error"]
            guard error == nil || error is NSNull || error is [String: Any] else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            guard let completedAt = sourceDate(payload["completed_at"]) else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            // `completed_at` is the terminal event's own source timestamp.
            // Prefer the outer transport timestamp when it decodes, but never
            // fall back to monitor decode time for terminal retention.
            let authoritativeAt = sourceAt ?? completedAt
            // Installed successful terminals omit `error`; older records use
            // an explicit null.  Both are success, while a structured error is
            // the closed failure form.
            let kind: RolloutEventKind = error == nil || error is NSNull ? .taskCompletedSuccess : .taskCompletedFailure
            return [envelope(kind, turn: turn, eventID: terminalEventID(kind: kind, turn: rawTurn, sourceAt: authoritativeAt, completedAt: completedAt), authoritativeAt: authoritativeAt)]
        case ("event_msg", "turn_aborted"):
            guard payload["reason"] as? String == "interrupted", let rawTurn = payload["turn_id"] as? String,
                  let turn = NamespacedID(sourceID: binding.sourceID.value, entityKind: .turn, rawID: rawTurn) else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            guard let completedAt = sourceDate(payload["completed_at"]) else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            let authoritativeAt = sourceAt ?? completedAt
            return [envelope(.turnAbortedInterrupted, turn: turn, eventID: terminalEventID(kind: .turnAbortedInterrupted, turn: rawTurn, sourceAt: authoritativeAt, completedAt: completedAt), authoritativeAt: authoritativeAt)]
        case ("event_msg", "turn_context"):
            guard let rawTurn = payload["turn_id"] as? String, let model = payload["model"] as? String,
                  let turn = NamespacedID(sourceID: binding.sourceID.value, entityKind: .turn, rawID: rawTurn) else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            return [envelope(.turnContext, turn: turn, model: model, effort: payload["reasoning_effort"] as? String)]
        case ("response_item", "reasoning"):
            guard let turn = activeTurnID, let item = payload["id"] as? String else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            return [envelope(.activity, turn: turn, itemRaw: item, activity: .thinking)]
        case ("response_item", "function_call"), ("response_item", "custom_tool_call"):
            guard let turn = activeTurnID, let item = (payload["call_id"] as? String) ?? (payload["id"] as? String) else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            return [envelope(.activity, turn: turn, itemRaw: item, activity: .tool)]
        case ("response_item", "function_call_output"), ("response_item", "custom_tool_call_output"):
            guard let turn = activeTurnID, let item = payload["call_id"] as? String else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            // Codex output is the exact completion of a function/custom call,
            // not a reasoning item.  The reducer's completion branch owns the
            // item and approval-resolution transition.
            return [envelope(.activity, turn: turn, itemRaw: item, activity: .agentResponse)]
        case ("event_msg", "patch_apply_end"):
            guard let turn = activeTurnID, let item = payload["call_id"] as? String else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            return [envelope(.activity, turn: turn, itemRaw: item, activity: .fileChange)]
        case ("response_item", "message"):
            guard payload["role"] as? String == "assistant", let turn = activeTurnID, let item = payload["id"] as? String else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            return [envelope(.activity, turn: turn, itemRaw: item, activity: .agentResponse)]
        default:
            return []
        }
    }

    private func applyDecodedState(_ record: RolloutRecordEnvelope) {
        let at = record.authoritativeEventAt ?? record.observedAt
        if let tokens = record.tokenSnapshot?.totalTokens { lastTokenTotal = max(lastTokenTotal ?? tokens, tokens) }
        switch record.kind {
        case .taskStarted:
            activeTurnID = record.turnID; activeTurnStartedAt = at; activeItemID = nil; activeItemCategory = nil
            latestActiveState = .thinking; latestActiveStateAt = at; latestTerminal = nil
        case .activity where record.turnID == activeTurnID:
            switch record.activity {
            case .tool?, .fileChange?:
                activeItemID = record.itemID; activeItemCategory = record.activity; latestActiveState = .working; latestActiveStateAt = at
            case .thinking?, .agentResponse?:
                if activeItemID == nil || activeItemID == record.itemID { activeItemID = nil; activeItemCategory = nil; latestActiveState = .thinking; latestActiveStateAt = at }
            case nil: break
            }
        case .taskCompletedSuccess, .taskCompletedFailure, .turnAbortedInterrupted:
            guard let turn = record.turnID, let eventID = record.eventID else { return }
            let state: MonitorRuntimeState = record.kind == .taskCompletedSuccess ? .completed : (record.kind == .taskCompletedFailure ? .failed : .interrupted)
            latestTerminal = ReconciledTerminal(turnID: turn, eventID: eventID, state: state, authoritativeEventAt: at)
            activeTurnID = nil; activeTurnStartedAt = nil; activeItemID = nil; activeItemCategory = nil; latestActiveState = nil; latestActiveStateAt = nil
        default: break
        }
    }

    private func checkpointHydration() -> RolloutCheckpointHydration {
        RolloutCheckpointHydration(activeTurnID: activeTurnID, turnStartedAt: activeTurnStartedAt, activeItemID: activeItemID, activeItemCategory: activeItemCategory, latestActiveState: latestActiveState, latestActiveStateAt: latestActiveStateAt, terminal: latestTerminal, authoritativeTokenTotal: lastTokenTotal)
    }

    private func invalidated(_ invalidation: RolloutReadInvalidation, reason: DesktopSourceHealthReason, identity: FileIdentity?) -> RolloutReadResult {
        partialLine = Data(); sessionValidated = false
        return RolloutReadResult(observations: [.sourceHealth(health(.unavailable, reason: reason, identity: identity))], cursor: nil, invalidation: invalidation)
    }

    private func health(_ state: DesktopSourceHealthState, reason: DesktopSourceHealthReason?, identity: FileIdentity?) -> DesktopSourceHealth {
        DesktopSourceHealth(threadID: binding.threadID, state: state, processEpoch: nil, fileIdentity: identity, reason: reason)
    }
}

private func number(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let double = number.doubleValue
    guard double.rounded() == double, double >= Double(Int64.min), double <= Double(Int64.max) else { return nil }
    return Int64(double)
}

/// The installed rollout shape carries an ISO-8601 outer `timestamp` and a
/// numeric payload `completed_at`.  This decoder accepts only those source
/// timestamp representations; it never substitutes monitor decode time.
private func sourceDate(_ value: Any?) -> Date? {
    if let number = number(value), number >= 0 {
        let seconds = number > 10_000_000_000 ? Double(number) / 1_000 : Double(number)
        return Date(timeIntervalSince1970: seconds)
    }
    guard let string = value as? String else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: string) { return date }
    if let date = ISO8601DateFormatter().date(from: string) { return date }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    return formatter.date(from: string)
}

private func terminalEventID(kind: RolloutEventKind, turn: String, sourceAt: Date, completedAt: Date) -> String {
    // Stable source fields, rather than a monitor decode-time or in-memory
    // counter, provide terminal replay identity for this JSONL record shape.
    "terminal-\(kind.rawValue)-\(turn)-\(sourceAt.timeIntervalSince1970)-\(completedAt.timeIntervalSince1970)"
}
private final class OpenedRollout {
    let handle: FileHandle
    let identity: FileIdentity
    let size: UInt64
    let modified: Date

    init?(url: URL) {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC)
        }
        guard descriptor >= 0 else { return nil }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else { Darwin.close(descriptor); return nil }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        identity = FileIdentity(device: UInt64(attributes.st_dev), inode: UInt64(attributes.st_ino))
        size = UInt64(attributes.st_size)
        modified = Date(timeIntervalSince1970: TimeInterval(attributes.st_mtimespec.tv_sec) + TimeInterval(attributes.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    func close() { try? handle.close() }
}

private extension RolloutIncrementalReader {
    func openTransaction() -> OpenedRollout? {
        beforeDescriptorOpen?()
        return OpenedRollout(url: binding.rolloutURL)
    }
}

private func read(_ transaction: OpenedRollout, offset: UInt64, count: Int) -> Data? {
    do { try transaction.handle.seek(toOffset: offset); return try transaction.handle.read(upToCount: count) } catch { return nil }
}

public enum DesktopLocalAdapterError: Error, Equatable { case threadNotFound, rolloutOutsideValidatedRoots, shutdown }

/// Coordinates state-DB discovery, exact rollout admission and health evidence.
/// It has no background process, transport, reducer, notification, persistence,
/// approval, account, or Codex lifecycle control path.
public final class DesktopLocalAdapter: @unchecked Sendable {
    private let sourceID: DesktopLocalSourceID
    private let roots: [URL]
    private let stateDB: StateDBReader
    private var readers: [NamespacedID: RolloutIncrementalReader] = [:]
    /// A checkpoint reader is deliberately isolated from the installed reader
    /// until its first poll has completed every exact rebind validation.  This
    /// keeps an old epoch mismatch latch authoritative through the admission
    /// window and prevents checkpoint bytes from being emitted early.
    private var pendingCheckpointReaders: [NamespacedID: RolloutIncrementalReader] = [:]
    /// A failed first checkpoint poll is not retried implicitly: a caller must
    /// explicitly open a fresh checkpoint binding before any bytes can be read.
    private var rejectedCheckpointAdmissions: Set<NamespacedID> = []
    /// Health observations made during checkpoint admission are candidates only;
    /// they never replace the installed epoch until the exact first poll commits.
    private var pendingCheckpointEpochs: [NamespacedID: ProcessEpoch] = [:]
    private var processEpochs: [NamespacedID: ProcessEpoch] = [:]
    private var processEpochMismatchLatches: Set<NamespacedID> = []
    private let readerBeforeDescriptorOpen: (() -> Void)?
    private var stopped = false

    public init(sourceID: DesktopLocalSourceID, validatedSessionRoots: [URL], stateDB: StateDBReader) {
        self.sourceID = sourceID; self.roots = validatedSessionRoots.map { $0.standardizedFileURL }; self.stateDB = stateDB; self.readerBeforeDescriptorOpen = nil
    }

    init(sourceID: DesktopLocalSourceID, validatedSessionRoots: [URL], stateDB: StateDBReader, readerBeforeDescriptorOpen: (() -> Void)?) {
        self.sourceID = sourceID; self.roots = validatedSessionRoots.map { $0.standardizedFileURL }; self.stateDB = stateDB; self.readerBeforeDescriptorOpen = readerBeforeDescriptorOpen
    }

    public func open(threadRawID: String, checkpoint: RolloutCursor? = nil) throws -> DesktopThreadSnapshot {
        guard !stopped else { throw DesktopLocalAdapterError.shutdown }
        guard let record = try stateDB.thread(rawID: threadRawID) else { throw DesktopLocalAdapterError.threadNotFound }
        guard isUnderValidatedRoot(record.rolloutURL) else { throw DesktopLocalAdapterError.rolloutOutsideValidatedRoots }
        guard let binding = ThreadRolloutBinding(sourceID: sourceID, threadRawID: threadRawID, rolloutURL: record.rolloutURL, sessionID: threadRawID) else { throw DesktopLocalAdapterError.threadNotFound }
        let reader = RolloutIncrementalReader(binding: binding, checkpoint: checkpoint, beforeDescriptorOpen: readerBeforeDescriptorOpen)
        if checkpoint != nil {
            // Do not replace the installed reader or touch its epoch state.
            // `poll` atomically installs this reader only after exact first-poll
            // State DB, descriptor, cursor, session, and reconstruction checks.
            pendingCheckpointReaders[binding.threadID] = reader
            rejectedCheckpointAdmissions.remove(binding.threadID)
            pendingCheckpointEpochs.removeValue(forKey: binding.threadID)
            return record.snapshot
        }
        switch reader.admitExactBinding() {
        case nil: break
        case .fileMissing?: throw DesktopLocalAdapterError.threadNotFound
        case .sessionMismatch?: throw DesktopLocalAdapterError.threadNotFound
        default: throw DesktopLocalAdapterError.threadNotFound
        }
        // Only a newly DB/path/file/session-admitted owner clears the per-thread
        // epoch latch.  An invalid attempted rebind leaves the old owner blocked.
        readers[binding.threadID] = reader
        processEpochs.removeValue(forKey: binding.threadID)
        processEpochMismatchLatches.remove(binding.threadID)
        return record.snapshot
    }

    public func poll(threadID: NamespacedID) throws -> RolloutReadResult {
        guard !stopped else { throw DesktopLocalAdapterError.shutdown }
        if rejectedCheckpointAdmissions.contains(threadID) {
            return pendingAdmissionUnavailable(threadID: threadID)
        }
        if let reader = pendingCheckpointReaders[threadID] {
            guard let record = try stateDB.thread(rawID: threadID.rawID),
                  record.snapshot.threadID == threadID,
                  record.rolloutURL.standardizedFileURL == reader.binding.rolloutURL.standardizedFileURL else {
                return reader.checkpointStateDBUnavailable()
            }
            reader.confirmCheckpointStateDBRevalidation()
            let result = reader.poll()
            guard result.invalidation == nil else {
                // Reject this candidate without disturbing the installed reader
                // or epoch latch.  A new explicit checkpoint open is required.
                pendingCheckpointReaders.removeValue(forKey: threadID)
                rejectedCheckpointAdmissions.insert(threadID)
                pendingCheckpointEpochs.removeValue(forKey: threadID)
                return result
            }
            // This is the single checkpoint-admission commit point: only now is
            // the replacement reader installed and the old ownership revoked.
            readers[threadID] = reader
            pendingCheckpointReaders.removeValue(forKey: threadID)
            rejectedCheckpointAdmissions.remove(threadID)
            processEpochs.removeValue(forKey: threadID)
            processEpochMismatchLatches.remove(threadID)
            if let admittedEpoch = pendingCheckpointEpochs.removeValue(forKey: threadID) {
                processEpochs[threadID] = admittedEpoch
            }
            return result
        }
        guard let reader = readers[threadID] else { throw DesktopLocalAdapterError.threadNotFound }
        if reader.requiresCheckpointStateDBRevalidation {
            guard let record = try stateDB.thread(rawID: threadID.rawID),
                  record.snapshot.threadID == threadID,
                  record.rolloutURL.standardizedFileURL == reader.binding.rolloutURL.standardizedFileURL else {
                return reader.checkpointStateDBUnavailable()
            }
            reader.confirmCheckpointStateDBRevalidation()
        }
        return reader.poll()
    }

    /// Records observed ownership without any signal, launch, restart or kill.
    /// A changed epoch is unavailable evidence until the caller performs a fresh
    /// exact state-DB/path/session rebind through `open`.
    public func health(threadID: NamespacedID, processEpoch: ProcessEpoch?, writerOwnsSelectedRollout: Bool) -> DesktopObservation {
        if pendingCheckpointReaders[threadID] != nil || rejectedCheckpointAdmissions.contains(threadID) {
            if pendingCheckpointReaders[threadID] != nil, let processEpoch, writerOwnsSelectedRollout {
                pendingCheckpointEpochs[threadID] = processEpoch
            }
            let identity = readers[threadID].flatMap { FileIdentity.readOnlyIdentity(of: $0.binding.rolloutURL) }
            return .sourceHealth(DesktopSourceHealth(threadID: threadID, state: .unavailable, processEpoch: processEpoch, fileIdentity: identity, reason: .checkpointAdmissionPending))
        }
        guard let reader = readers[threadID] else { return .capabilityUnavailable(threadID: threadID, capability: .rolloutSessionIdentity) }
        let identity = FileIdentity.readOnlyIdentity(of: reader.binding.rolloutURL)
        guard let processEpoch else { return .sourceHealth(DesktopSourceHealth(threadID: threadID, state: .unavailable, processEpoch: nil, fileIdentity: identity, reason: .sourceMissing)) }
        if processEpochMismatchLatches.contains(threadID) {
            return .sourceHealth(DesktopSourceHealth(threadID: threadID, state: .unavailable, processEpoch: processEpoch, fileIdentity: identity, reason: .processEpochMismatch))
        }
        if let expected = processEpochs[threadID], expected != processEpoch {
            processEpochMismatchLatches.insert(threadID)
            return .sourceHealth(DesktopSourceHealth(threadID: threadID, state: .unavailable, processEpoch: processEpoch, fileIdentity: identity, reason: .processEpochMismatch))
        }
        guard writerOwnsSelectedRollout else { return .sourceHealth(DesktopSourceHealth(threadID: threadID, state: .unavailable, processEpoch: processEpoch, fileIdentity: identity, reason: .writerOwnershipMissing)) }
        processEpochs[threadID] = processEpoch
        return .sourceHealth(DesktopSourceHealth(threadID: threadID, state: .available, processEpoch: processEpoch, fileIdentity: identity))
    }

    public func shutdown() {
        stopped = true
        readers.removeAll()
        pendingCheckpointReaders.removeAll()
        rejectedCheckpointAdmissions.removeAll()
        pendingCheckpointEpochs.removeAll()
        processEpochs.removeAll()
        processEpochMismatchLatches.removeAll()
    }

    private func pendingAdmissionUnavailable(threadID: NamespacedID) -> RolloutReadResult {
        let identity = readers[threadID].flatMap { FileIdentity.readOnlyIdentity(of: $0.binding.rolloutURL) }
        let health = DesktopSourceHealth(threadID: threadID, state: .unavailable, processEpoch: nil, fileIdentity: identity, reason: .checkpointAdmissionPending)
        return RolloutReadResult(observations: [.sourceHealth(health)], cursor: nil, invalidation: .sessionMismatch)
    }

    private func isUnderValidatedRoot(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        return roots.contains { root in candidate == root.path || candidate.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/") }
    }
}
