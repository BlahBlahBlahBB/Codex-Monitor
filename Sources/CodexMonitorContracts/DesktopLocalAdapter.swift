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
    case sourceMissing, processEpochMismatch, writerOwnershipMissing, fileIdentityChanged, fileTruncated, schemaUnavailable
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
    public let observedAt: Date
    public let fileOffset: UInt64
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

    public init(binding: ThreadRolloutBinding, checkpoint: RolloutCursor? = nil, maxHeaderBytes: UInt64 = 65_536, maxTailBytes: UInt64 = 1_048_576, maxAppendBytes: Int = 262_144) {
        self.binding = binding; self.cursor = checkpoint; self.maxHeaderBytes = maxHeaderBytes; self.maxTailBytes = maxTailBytes; self.maxAppendBytes = maxAppendBytes
    }

    public func poll() -> RolloutReadResult {
        guard let identity = FileIdentity.readOnlyIdentity(of: binding.rolloutURL),
              let size = fileSize(binding.rolloutURL), let modified = modificationTime(binding.rolloutURL) else {
            return RolloutReadResult(observations: [.sourceHealth(health(.unavailable, reason: .sourceMissing, identity: nil))], cursor: cursor, invalidation: .fileMissing)
        }
        if let cursor {
            if cursor.fileIdentity != identity {
                return invalidated(.fileReplaced, reason: .fileIdentityChanged, identity: identity)
            }
            if size < cursor.byteOffset { return invalidated(.fileTruncated, reason: .fileTruncated, identity: identity) }
            return appended(identity: identity, size: size, modified: modified, from: cursor.byteOffset)
        }
        return bootstrap(identity: identity, size: size, modified: modified)
    }

    private func bootstrap(identity: FileIdentity, size: UInt64, modified: Date) -> RolloutReadResult {
        guard let header = read(url: binding.rolloutURL, offset: 0, count: Int(min(size, maxHeaderBytes))), validateSession(in: header) else {
            return RolloutReadResult(observations: [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutSessionIdentity)], cursor: nil, invalidation: .sessionMismatch)
        }
        sessionValidated = true
        if size <= maxHeaderBytes { return consume(header, identity: identity, offset: 0, endingOffset: size, modified: modified, skipFirstPartial: false) }
        let start = size - min(size, maxTailBytes)
        guard let tail = read(url: binding.rolloutURL, offset: start, count: Int(size - start)) else { return invalidated(.fileMissing, reason: .sourceMissing, identity: identity) }
        return consume(tail, identity: identity, offset: start, endingOffset: size, modified: modified, skipFirstPartial: start > 0)
    }

    private func appended(identity: FileIdentity, size: UInt64, modified: Date, from offset: UInt64) -> RolloutReadResult {
        guard sessionValidated else { return invalidated(.sessionMismatch, reason: .fileIdentityChanged, identity: identity) }
        guard size > offset else { return RolloutReadResult(observations: [.sourceHealth(health(.available, reason: nil, identity: identity))], cursor: cursor, invalidation: nil) }
        let count = Int(min(UInt64(maxAppendBytes), size - offset))
        guard let bytes = read(url: binding.rolloutURL, offset: offset, count: count) else { return invalidated(.fileMissing, reason: .sourceMissing, identity: identity) }
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
        func envelope(_ kind: RolloutEventKind, turn: NamespacedID? = activeTurnID, itemRaw: String? = nil, activity: RolloutActivityCategory? = nil, token: TokenSnapshot? = nil, model: String? = nil, effort: String? = nil) -> DesktopObservation {
            let item = itemRaw.flatMap { NamespacedID(sourceID: binding.sourceID.value, entityKind: .item, rawID: $0) }
            return .rollout(RolloutRecordEnvelope(threadID: binding.threadID, turnID: turn, itemID: item, kind: kind, activity: activity, tokenSnapshot: token, model: model, reasoningEffort: effort, observedAt: observedAt, fileOffset: offset))
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
            guard let rawTurn = payload["turn_id"] as? String, let turn = NamespacedID(sourceID: binding.sourceID.value, entityKind: .turn, rawID: rawTurn), payload.keys.contains("error") else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            let error = payload["error"]
            guard error is NSNull || error is [String: Any] else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            return [envelope(error is NSNull ? .taskCompletedSuccess : .taskCompletedFailure, turn: turn)]
        case ("event_msg", "turn_aborted"):
            guard payload["reason"] as? String == "interrupted", let rawTurn = payload["turn_id"] as? String,
                  let turn = NamespacedID(sourceID: binding.sourceID.value, entityKind: .turn, rawID: rawTurn) else { return [.capabilityUnavailable(threadID: binding.threadID, capability: .rolloutFormat)] }
            return [envelope(.turnAbortedInterrupted, turn: turn)]
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
            return [envelope(.activity, turn: turn, itemRaw: item, activity: .thinking)]
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
private func fileSize(_ url: URL) -> UInt64? {
    var attributes = stat()
    let result = url.withUnsafeFileSystemRepresentation { path in
        guard let path else { return -1 }
        return Int(lstat(path, &attributes))
    }
    return result == 0 ? UInt64(attributes.st_size) : nil
}
private func modificationTime(_ url: URL) -> Date? {
    var attributes = stat()
    let result = url.withUnsafeFileSystemRepresentation { path in
        guard let path else { return -1 }
        return Int(lstat(path, &attributes))
    }
    guard result == 0 else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(attributes.st_mtimespec.tv_sec) + TimeInterval(attributes.st_mtimespec.tv_nsec) / 1_000_000_000)
}
private func read(url: URL, offset: UInt64, count: Int) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    do { try handle.seek(toOffset: offset); return try handle.read(upToCount: count) } catch { return nil }
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
    private var processEpochs: [NamespacedID: ProcessEpoch] = [:]
    private var stopped = false

    public init(sourceID: DesktopLocalSourceID, validatedSessionRoots: [URL], stateDB: StateDBReader) {
        self.sourceID = sourceID; self.roots = validatedSessionRoots.map { $0.standardizedFileURL }; self.stateDB = stateDB
    }

    public func open(threadRawID: String, checkpoint: RolloutCursor? = nil) throws -> DesktopThreadSnapshot {
        guard !stopped else { throw DesktopLocalAdapterError.shutdown }
        guard let record = try stateDB.thread(rawID: threadRawID) else { throw DesktopLocalAdapterError.threadNotFound }
        guard isUnderValidatedRoot(record.rolloutURL) else { throw DesktopLocalAdapterError.rolloutOutsideValidatedRoots }
        guard let binding = ThreadRolloutBinding(sourceID: sourceID, threadRawID: threadRawID, rolloutURL: record.rolloutURL, sessionID: threadRawID) else { throw DesktopLocalAdapterError.threadNotFound }
        readers[binding.threadID] = RolloutIncrementalReader(binding: binding, checkpoint: checkpoint)
        return record.snapshot
    }

    public func poll(threadID: NamespacedID) throws -> RolloutReadResult {
        guard !stopped else { throw DesktopLocalAdapterError.shutdown }
        guard let reader = readers[threadID] else { throw DesktopLocalAdapterError.threadNotFound }
        return reader.poll()
    }

    /// Records observed ownership without any signal, launch, restart or kill.
    /// A changed epoch is unavailable evidence until the caller performs a fresh
    /// exact state-DB/path/session rebind through `open`.
    public func health(threadID: NamespacedID, processEpoch: ProcessEpoch?, writerOwnsSelectedRollout: Bool) -> DesktopObservation {
        guard let reader = readers[threadID] else { return .capabilityUnavailable(threadID: threadID, capability: .rolloutSessionIdentity) }
        let identity = FileIdentity.readOnlyIdentity(of: reader.binding.rolloutURL)
        guard let processEpoch else { return .sourceHealth(DesktopSourceHealth(threadID: threadID, state: .unavailable, processEpoch: nil, fileIdentity: identity, reason: .sourceMissing)) }
        if let expected = processEpochs[threadID], expected != processEpoch {
            return .sourceHealth(DesktopSourceHealth(threadID: threadID, state: .unavailable, processEpoch: processEpoch, fileIdentity: identity, reason: .processEpochMismatch))
        }
        guard writerOwnsSelectedRollout else { return .sourceHealth(DesktopSourceHealth(threadID: threadID, state: .unavailable, processEpoch: processEpoch, fileIdentity: identity, reason: .writerOwnershipMissing)) }
        processEpochs[threadID] = processEpoch
        return .sourceHealth(DesktopSourceHealth(threadID: threadID, state: .available, processEpoch: processEpoch, fileIdentity: identity))
    }

    public func shutdown() { stopped = true; readers.removeAll(); processEpochs.removeAll() }

    private func isUnderValidatedRoot(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        return roots.contains { root in candidate == root.path || candidate.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/") }
    }
}
