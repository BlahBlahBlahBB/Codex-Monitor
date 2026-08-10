import XCTest
import Foundation
import Darwin
import CSQLite
@testable import CodexMonitorContracts

final class DesktopLocalAdapterTests: XCTestCase {
    private var fixture: LocalFixture!

    override func setUpWithError() throws { fixture = try LocalFixture() }
    override func tearDownWithError() throws { fixture.cleanup(); fixture = nil }

    func testExactStateDBPathAndSessionMetaMustMatch() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a")])
        try fixture.addThread("thread-a", rollout: file)
        let sessionBefore = try Data(contentsOf: file)
        let adapter = try fixture.adapter()
        let snapshot = try adapter.open(threadRawID: "thread-a")
        XCTAssertEqual(snapshot.threadID.rawID, "thread-a")
        XCTAssertTrue(try adapter.poll(threadID: snapshot.threadID).observations.containsRollout(.taskStarted))
        XCTAssertEqual(sessionBefore, try Data(contentsOf: file))

        let wrong = try fixture.rollout("thread-b", lines: [fixture.session("not-thread-b")])
        try fixture.addThread("thread-b", rollout: wrong)
        let wrongSnapshot = try adapter.open(threadRawID: "thread-b")
        let result = try adapter.poll(threadID: wrongSnapshot.threadID)
        XCTAssertEqual(result.invalidation, .sessionMismatch)
        XCTAssertTrue(result.observations.containsUnavailable(.rolloutSessionIdentity))
    }

    func testInterleavedIdenticalTimestampsNeverCrossThreadOrToken() throws {
        let a = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), fixture.token(total: 100, last: 10)])
        let b = try fixture.rollout("thread-b", lines: [fixture.session("thread-b"), fixture.started("turn-b"), fixture.token(total: 900, last: 90)])
        try fixture.addThread("thread-a", rollout: a); try fixture.addThread("thread-b", rollout: b)
        let adapter = try fixture.adapter()
        let first = try adapter.open(threadRawID: "thread-a"); let second = try adapter.open(threadRawID: "thread-b")
        let aEvents = try adapter.poll(threadID: first.threadID).observations.rollouts
        let bEvents = try adapter.poll(threadID: second.threadID).observations.rollouts
        XCTAssertTrue(aEvents.allSatisfy { $0.threadID == first.threadID })
        XCTAssertTrue(bEvents.allSatisfy { $0.threadID == second.threadID })
        XCTAssertEqual(aEvents.tokenTotals, [100])
        XCTAssertEqual(bEvents.tokenTotals, [900])
    }

    func testOneThreadTerminalDoesNotStopAnotherThreadObservation() throws {
        let a = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), fixture.complete("turn-a")])
        let b = try fixture.rollout("thread-b", lines: [fixture.session("thread-b"), fixture.started("turn-b"), fixture.tool("call-b")])
        try fixture.addThread("thread-a", rollout: a); try fixture.addThread("thread-b", rollout: b)
        let adapter = try fixture.adapter(); let aThread = try adapter.open(threadRawID: "thread-a"); let bThread = try adapter.open(threadRawID: "thread-b")
        XCTAssertTrue(try adapter.poll(threadID: aThread.threadID).observations.containsRollout(.taskCompletedSuccess))
        let active = try adapter.poll(threadID: bThread.threadID).observations.rollouts
        XCTAssertTrue(active.contains { $0.activity == .tool && $0.turnID?.rawID == "turn-b" })
        XCTAssertFalse(active.contains { $0.kind == .taskCompletedSuccess || $0.kind == .taskCompletedFailure || $0.kind == .turnAbortedInterrupted })
    }

    func testDuplicateTokenSnapshotDoesNotAddLastValue() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), fixture.token(total: 100, last: 10), fixture.token(total: 100, last: 10), fixture.token(total: 110, last: 10)])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        let events = try adapter.poll(threadID: thread.threadID).observations.rollouts
        XCTAssertEqual(events.tokenTotals, [100, 110])
        XCTAssertEqual(events.compactMap { $0.tokenSnapshot?.lastCallTokens }, [10, 10])
    }

    func testPartialFinalJSONWaitsUntilAppend() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a")])
        try fixture.append(to: file, text: String(fixture.token(total: 42, last: 4).dropLast()))
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        XCTAssertTrue(try adapter.poll(threadID: thread.threadID).observations.rollouts.tokenTotals.isEmpty)
        try fixture.append(to: file, text: "}\n")
        XCTAssertEqual(try adapter.poll(threadID: thread.threadID).observations.rollouts.tokenTotals, [42])
    }

    func testTruncateAndReplacementInvalidateOldCursor() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), fixture.token(total: 10, last: 10)])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        _ = try adapter.poll(threadID: thread.threadID)
        try Data(fixture.session("thread-a").utf8).write(to: file)
        XCTAssertEqual(try adapter.poll(threadID: thread.threadID).invalidation, .fileTruncated)

        let rebound = try adapter.open(threadRawID: "thread-a"); _ = try adapter.poll(threadID: rebound.threadID)
        let replacement = try fixture.rollout("replacement", lines: [fixture.session("thread-a")])
        try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: replacement, to: file)
        XCTAssertEqual(try adapter.poll(threadID: rebound.threadID).invalidation, .fileReplaced)
    }

    func testArchiveMoveRequiresFreshExactStateDBAndSessionValidation() throws {
        let original = try fixture.rollout("thread-a", lines: [fixture.session("thread-a")])
        try fixture.addThread("thread-a", rollout: original)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        _ = try adapter.poll(threadID: thread.threadID)
        let archive = fixture.root.appendingPathComponent("archive-thread-a.jsonl")
        try FileManager.default.moveItem(at: original, to: archive)
        XCTAssertEqual(try adapter.poll(threadID: thread.threadID).invalidation, .fileMissing)
        try fixture.updatePath(thread: "thread-a", path: archive)
        let rebound = try adapter.open(threadRawID: "thread-a")
        XCTAssertNil(try adapter.poll(threadID: rebound.threadID).invalidation)
        try fixture.replaceContents(at: archive, with: fixture.session("other-thread") + "\n")
        let again = try adapter.open(threadRawID: "thread-a")
        XCTAssertEqual(try adapter.poll(threadID: again.threadID).invalidation, .sessionMismatch)
    }

    func testPIDReuseAndWriterLossAreUnavailableEvidenceOnly() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a")])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        let epochOne = ProcessEpoch(pid: 42, startedAtNanoseconds: 1)!
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: epochOne, writerOwnsSelectedRollout: true).health?.state, .available)
        let reused = adapter.health(threadID: thread.threadID, processEpoch: ProcessEpoch(pid: 42, startedAtNanoseconds: 2)!, writerOwnsSelectedRollout: true)
        XCTAssertEqual(reused.health?.reason, .processEpochMismatch)
        let missing = adapter.health(threadID: thread.threadID, processEpoch: epochOne, writerOwnsSelectedRollout: false)
        XCTAssertEqual(missing.health?.reason, .writerOwnershipMissing)
        XCTAssertNil(reused.rollout)
        XCTAssertNil(missing.rollout)
    }

    func testSilenceAndSourceLossNeverSynthesizeTerminal() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), fixture.reasoning("reason-a")])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        _ = try adapter.poll(threadID: thread.threadID)
        XCTAssertFalse(try adapter.poll(threadID: thread.threadID).observations.containsTerminal)
        try FileManager.default.removeItem(at: file)
        let lost = try adapter.poll(threadID: thread.threadID)
        XCTAssertEqual(lost.invalidation, .fileMissing)
        XCTAssertFalse(lost.observations.containsTerminal)
        XCTAssertEqual(lost.observations.health?.state, .unavailable)
    }

    func testWrongTokenTypeOnlyDowngradesSessionTokenCapability() throws {
        let bad = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\"wrong\"}}}}"
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), bad])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        let observations = try adapter.poll(threadID: thread.threadID).observations
        XCTAssertTrue(observations.containsUnavailable(.sessionToken))
        XCTAssertTrue(observations.containsRollout(.taskStarted))
    }

    func testBusyReadIsBoundedAndCodexDatabaseIsNeverWritten() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a")])
        try fixture.addThread("thread-a", rollout: file)
        let before = try Data(contentsOf: fixture.database)
        var lock: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(fixture.database.path, &lock, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_exec(lock, "ROLLBACK", nil, nil, nil); sqlite3_close(lock) }
        XCTAssertEqual(sqlite3_exec(lock, "BEGIN EXCLUSIVE", nil, nil, nil), SQLITE_OK)
        let reader = StateDBReader(databaseURL: fixture.database, sourceID: fixture.sourceID, schema: .init(acceptedUserVersions: [1]), retryPolicy: .init(attempts: 2, busyTimeoutMilliseconds: 1, retryDelayMilliseconds: 1))
        let started = Date()
        XCTAssertThrowsError(try reader.thread(rawID: "thread-a")) { XCTAssertEqual($0 as? StateDBError, .busyExhausted) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2)
        XCTAssertEqual(before, try Data(contentsOf: fixture.database))
    }

    func testUnknownStateDBVersionFailsClosedBeforePathDiscovery() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a")])
        try fixture.addThread("thread-a", rollout: file)
        let reader = StateDBReader(databaseURL: fixture.database, sourceID: fixture.sourceID, schema: .init(acceptedUserVersions: [2]))
        XCTAssertThrowsError(try reader.thread(rawID: "thread-a")) { XCTAssertEqual($0 as? StateDBError, .schemaMismatch) }
    }

    func testObservationsAndPersistableBoundariesRetainNoRawContentOrPrivatePath() throws {
        let privateMessage = "ULTRA_PRIVATE_COMMAND_OUTPUT_/Users/person/secret"
        let message = "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"id\":\"response-a\",\"content\":\"\(privateMessage)\"}}"
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), message])
        try fixture.addThread("thread-a", rollout: file, title: "PRIVATE_TITLE")
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        let observations = try adapter.poll(threadID: thread.threadID).observations
        let printed = String(reflecting: observations)
        XCTAssertFalse(printed.contains(privateMessage))
        XCTAssertFalse(printed.contains(fixture.root.path))
        XCTAssertTrue(observations.contains { $0.rollout?.activity == .agentResponse })
    }

    func testShutdownDoesNotSignalOrKillCodexProcess() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a")])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); _ = try adapter.open(threadRawID: "thread-a")
        adapter.shutdown()
        XCTAssertEqual(kill(getpid(), 0), 0)
        XCTAssertThrowsError(try adapter.open(threadRawID: "thread-a")) { XCTAssertEqual($0 as? DesktopLocalAdapterError, .shutdown) }
    }
}

private final class LocalFixture {
    let root: URL
    let database: URL
    let sourceID = DesktopLocalSourceID("test-desktop-source")!

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("codex-monitor-v31-\(UUID().uuidString)")
        database = root.appendingPathComponent("state.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw POSIXError(.EIO) }
        defer { sqlite3_close(db) }
        try execute(db, "PRAGMA user_version = 1")
        try execute(db, "CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, title TEXT, model TEXT, reasoning_effort TEXT, updated_at INTEGER, tokens_used INTEGER)")
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func adapter() throws -> DesktopLocalAdapter { DesktopLocalAdapter(sourceID: sourceID, validatedSessionRoots: [root], stateDB: StateDBReader(databaseURL: database, sourceID: sourceID, schema: .init(acceptedUserVersions: [1]))) }
    func rollout(_ name: String, lines: [String]) throws -> URL {
        let url = root.appendingPathComponent("\(name).jsonl")
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: url)
        return url
    }
    func append(to url: URL, text: String) throws {
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: Data(text.utf8))
    }
    func replaceContents(at url: URL, with text: String) throws { try Data(text.utf8).write(to: url) }
    func addThread(_ id: String, rollout: URL, title: String = "title") throws {
        try executeDatabase("INSERT INTO threads VALUES ('\(sql(id))', '\(sql(rollout.path))', '\(sql(title))', 'gpt-test', 'high', 1, 0)")
    }
    func updatePath(thread: String, path: URL) throws { try executeDatabase("UPDATE threads SET rollout_path = '\(sql(path.path))' WHERE id = '\(sql(thread))'") }
    func session(_ id: String) -> String { "{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\"}}" }
    func started(_ turn: String) -> String { "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"\(turn)\",\"started_at\":1}}" }
    func token(total: Int, last: Int) -> String { "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)},\"last_token_usage\":{\"total_tokens\":\(last)}}}}" }
    func reasoning(_ id: String) -> String { "{\"type\":\"response_item\",\"payload\":{\"type\":\"reasoning\",\"id\":\"\(id)\"}}" }
    func tool(_ id: String) -> String { "{\"type\":\"response_item\",\"payload\":{\"type\":\"function_call\",\"call_id\":\"\(id)\"}}" }
    func complete(_ turn: String) -> String { "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"\(turn)\",\"error\":null}}" }

    private func executeDatabase(_ sql: String) throws {
        var db: OpaquePointer?; guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw POSIXError(.EIO) }; defer { sqlite3_close(db) }
        try execute(db, sql)
    }
    private func sql(_ value: String) -> String { value.replacingOccurrences(of: "'", with: "''") }
}

private func execute(_ db: OpaquePointer?, _ sql: String) throws {
    var message: UnsafeMutablePointer<Int8>?
    guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else { sqlite3_free(message); throw POSIXError(.EIO) }
}

private extension Array where Element == DesktopObservation {
    var rollouts: [RolloutRecordEnvelope] { compactMap(\.rollout) }
    var health: DesktopSourceHealth? { compactMap(\.health).last }
    var containsTerminal: Bool { rollouts.contains { [.taskCompletedSuccess, .taskCompletedFailure, .turnAbortedInterrupted].contains($0.kind) } }
    func containsRollout(_ kind: RolloutEventKind) -> Bool { rollouts.contains { $0.kind == kind } }
    func containsUnavailable(_ capability: DesktopCapability) -> Bool { contains { $0.unavailableCapability == capability } }
}

private extension Array where Element == RolloutRecordEnvelope { var tokenTotals: [Int64] { compactMap { $0.tokenSnapshot?.totalTokens } } }
private extension DesktopObservation {
    var rollout: RolloutRecordEnvelope? { if case .rollout(let value) = self { return value }; return nil }
    var health: DesktopSourceHealth? { if case .sourceHealth(let value) = self { return value }; return nil }
    var unavailableCapability: DesktopCapability? { if case .capabilityUnavailable(_, let value) = self { return value }; return nil }
}
