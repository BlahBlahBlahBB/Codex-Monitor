import XCTest
import Foundation
import CSQLite
@testable import CodexMonitorContracts

final class V3StateEngineTests: XCTestCase {
    private var clock: V3FakeClock!
    private var engine: RuntimeStateEngine!
    private let source = SourceID("v3-test-source")!

    override func setUp() { clock = V3FakeClock(); engine = RuntimeStateEngine(clock: clock) }

    func testReasoningToolAndTokenOnlyArbitration() {
        let thread = id(.thread, "a"), turn = id(.turn, "turn-a")
        engine.ingest(event(thread, turn, .taskStarted))
        XCTAssertEqual(state(thread), .thinking)
        clock.advance(1); engine.ingest(event(thread, turn, .activity, activity: .tool))
        XCTAssertEqual(state(thread), .working)
        clock.advance(1); engine.ingest(event(thread, turn, .tokenCount, tokens: 44))
        XCTAssertEqual(state(thread), .working)
        XCTAssertEqual(engine.snapshot().representativeThread?.sessionTokenCumulative, 44)
        engine.ingest(event(thread, turn, .activity, activity: .thinking))
        XCTAssertEqual(state(thread), .thinking)
    }

    func testExactApprovalOverridesOnlyItsThreadAndExactResolutionClears() {
        let a = id(.thread, "a"), b = id(.thread, "b"), turnA = id(.turn, "turn-a"), turnB = id(.turn, "turn-b")
        engine.ingest(event(a, turnA, .taskStarted)); engine.ingest(event(b, turnB, .taskStarted, activity: .tool))
        let request = id(.item, "request-a")
        engine.ingest(.requested(ApprovalRequested(threadID: a, turnID: turnA, requestID: request, observedAt: clock.now())))
        XCTAssertEqual(state(a), .waitingApproval); XCTAssertEqual(state(b), .thinking)
        engine.ingest(.resolved(ApprovalResolved(threadID: b, turnID: turnB, requestID: request, status: .approved, observedAt: clock.now())))
        XCTAssertEqual(state(a), .waitingApproval)
        engine.ingest(.resolved(ApprovalResolved(threadID: a, turnID: turnA, requestID: request, status: .approved, observedAt: clock.now())))
        XCTAssertEqual(state(a), .thinking)
    }

    func testTerminalWinsApprovalAndTaskFailureIsNotSystemError() {
        let thread = id(.thread, "a"), turn = id(.turn, "turn-a"), request = id(.item, "request")
        engine.ingest(event(thread, turn, .taskStarted)); engine.ingest(.requested(ApprovalRequested(threadID: thread, turnID: turn, requestID: request, observedAt: clock.now())))
        engine.ingest(event(thread, turn, .taskCompletedFailure))
        XCTAssertEqual(state(thread), .failed)
        XCTAssertNotEqual(state(thread), .systemError)
    }

    func testInterruptedAndSystemErrorRemainDistinct() {
        let a = id(.thread, "a"), b = id(.thread, "b"), turn = id(.turn, "turn")
        engine.ingest(event(a, turn, .taskStarted)); engine.ingest(event(a, turn, .turnAbortedInterrupted))
        engine.recordSystemError(threadID: b)
        XCTAssertEqual(state(a), .interrupted); XCTAssertEqual(state(b), .systemError)
    }

    func testSourceLossAndLongSilenceNeverFabricateTerminals() {
        let thread = id(.thread, "a"), turn = id(.turn, "turn")
        engine.ingest(event(thread, turn, .taskStarted, activity: .tool))
        clock.advance(3_600); XCTAssertEqual(state(thread), .thinking) // start is conservative thinking; silence preserves it
        engine.ingest(DesktopSourceHealth(threadID: thread, state: .unavailable, processEpoch: nil, fileIdentity: nil, reason: .sourceMissing))
        XCTAssertEqual(state(thread), .disconnected)
        XCTAssertFalse([MonitorRuntimeState.completed, .failed, .interrupted].contains(state(thread)))
    }

    func testCompletedRetentionAndNewTurnOverride() {
        let thread = id(.thread, "a"), turn = id(.turn, "turn")
        engine.ingest(event(thread, turn, .taskStarted)); engine.ingest(event(thread, turn, .taskCompletedSuccess))
        XCTAssertEqual(state(thread), .completed)
        clock.advance(4.9); XCTAssertEqual(state(thread), .completed)
        clock.advance(0.1); XCTAssertEqual(state(thread), .idle)
        engine.ingest(event(thread, id(.turn, "next"), .taskStarted, activity: .tool))
        XCTAssertEqual(state(thread), .thinking)
    }

    func testRedRetentionAndImmediateNewTurnOverride() {
        for terminal in [RolloutEventKind.taskCompletedFailure, .turnAbortedInterrupted] {
            let thread = id(.thread, terminal.rawValue), turn = id(.turn, terminal.rawValue)
            engine.ingest(event(thread, turn, .taskStarted)); engine.ingest(event(thread, turn, terminal))
            XCTAssertNotEqual(state(thread), .idle)
            clock.advance(14.9); XCTAssertNotEqual(state(thread), .idle)
            clock.advance(0.1); XCTAssertEqual(state(thread), .idle)
        }
        let system = id(.thread, "system"); engine.recordSystemError(threadID: system)
        clock.advance(14.9); XCTAssertEqual(state(system), .systemError)
        engine.ingest(event(system, id(.turn, "new"), .taskStarted)); XCTAssertEqual(state(system), .thinking)
    }

    func testThreadIsolationAndGlobalPriority() {
        let working = id(.thread, "working"), failed = id(.thread, "failed"), approval = id(.thread, "approval")
        engine.ingest(event(working, id(.turn, "w"), .taskStarted)); engine.ingest(event(working, id(.turn, "w"), .activity, activity: .tool))
        engine.ingest(event(approval, id(.turn, "a"), .taskStarted)); engine.ingest(.requested(ApprovalRequested(threadID: approval, turnID: id(.turn, "a"), requestID: id(.item, "r"), observedAt: clock.now())))
        XCTAssertEqual(engine.snapshot().state, .waitingApproval)
        engine.ingest(event(failed, id(.turn, "f"), .taskStarted)); engine.ingest(event(failed, id(.turn, "f"), .taskCompletedFailure))
        XCTAssertEqual(engine.snapshot().state, .failed)
        XCTAssertEqual(state(working), .working)
        XCTAssertEqual(engine.snapshot().activeThreadCount, 2)
        XCTAssertEqual(engine.snapshot().waitingApprovalCount, 1)
    }

    func testPauseResumeRequiresReconciliationAndDoesNotApplyTerminal() {
        let thread = id(.thread, "a"), turn = id(.turn, "turn")
        engine.ingest(event(thread, turn, .taskStarted)); engine.setPaused(true)
        engine.ingest(event(thread, turn, .taskCompletedSuccess))
        XCTAssertEqual(engine.snapshot().state, .paused)
        XCTAssertEqual(engine.snapshot().sourceFreshness.state, .stale)
        engine.setPaused(false); XCTAssertEqual(engine.snapshot().state, .paused)
        engine.completeResumeReconciliation(); XCTAssertEqual(state(thread), .thinking)
    }

    func testTerminalFromAnotherTurnCannotAlterCurrentThreadTurn() {
        let thread = id(.thread, "a")
        engine.ingest(event(thread, id(.turn, "old"), .taskStarted)); engine.ingest(event(thread, id(.turn, "new"), .taskStarted))
        engine.ingest(event(thread, id(.turn, "old"), .taskCompletedSuccess))
        XCTAssertEqual(state(thread), .thinking)
    }

    private func id(_ kind: EntityKind, _ raw: String) -> NamespacedID { NamespacedID(sourceID: source, entityKind: kind, rawID: raw)! }
    private func event(_ thread: NamespacedID, _ turn: NamespacedID, _ kind: RolloutEventKind, activity: RolloutActivityCategory? = nil, tokens: Int64? = nil) -> RolloutRecordEnvelope {
        RolloutRecordEnvelope(threadID: thread, turnID: turn, itemID: nil, kind: kind, activity: activity, tokenSnapshot: tokens.map { TokenSnapshot(totalTokens: $0, lastCallTokens: nil) }, model: nil, reasoningEffort: nil, observedAt: clock.now(), fileOffset: 0)
    }
    private func state(_ thread: NamespacedID) -> MonitorRuntimeState { engine.snapshot().threads.first { $0.threadID == thread }!.state }
}

private final class V3FakeClock: StateEngineClock, @unchecked Sendable {
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { value }
    func advance(_ seconds: TimeInterval) { value = value.addingTimeInterval(seconds) }
}

final class ApprovalLocalAdapterTests: XCTestCase {
    private var fixture: ApprovalFixture!
    override func setUpWithError() throws { fixture = try ApprovalFixture() }
    override func tearDownWithError() throws { fixture.cleanup() }

    func testRequestResolutionExactCorrelationIncrementalAndRestartCheckpoint() throws {
        try fixture.insert(id: 1, thread: "a", target: "item/commandExecution/requestApproval", body: fixture.body(event: "requestApproval", request: "r-a", turn: "t-a"))
        let adapter = fixture.adapter(); let first = try adapter.poll()
        XCTAssertEqual(first.observations.count, 1); XCTAssertNotNil(first.cursor)
        XCTAssertTrue(first.observations.contains { if case .requested = $0 { return true }; return false })
        XCTAssertTrue((try adapter.poll()).observations.isEmpty)
        let resumed = fixture.adapter(checkpoint: first.cursor)
        XCTAssertTrue((try resumed.poll()).observations.isEmpty)
        try fixture.insert(id: 2, thread: "a", target: "serverRequest/resolved", body: fixture.body(event: "approved", request: "r-a", turn: "t-a"))
        let resolution = try resumed.poll().observations
        XCTAssertTrue(resolution.contains { if case .resolved(let value) = $0 { return value.requestID.rawID == "r-a" }; return false })
    }

    func testUnknownSchemaMalformedAndRotationFailClosedWithoutContent() throws {
        try fixture.insert(id: 1, thread: "a", target: "item/commandExecution/requestApproval", body: "{not-json secret-command}")
        let malformed = try fixture.adapter().poll()
        XCTAssertEqual(malformed.health.reason, .malformedRecord)
        XCTAssertFalse(String(reflecting: malformed).contains("secret-command"))
        try fixture.setUserVersion(2)
        XCTAssertEqual(try fixture.adapter().poll().health.reason, .schemaMismatch)
        try fixture.setUserVersion(1)
        let checkpoint = ApprovalLogCursor(fileIdentity: FileIdentity.readOnlyIdentity(of: fixture.database)!, lastLogID: 1)
        try FileManager.default.removeItem(at: fixture.database); try fixture.createDatabase()
        XCTAssertEqual(try fixture.adapter(checkpoint: checkpoint).poll().health.reason, .fileIdentityChanged)
    }

    func testUnknownTargetIsIgnoredAndResolutionRetainsExactIdentity() throws {
        try fixture.insert(id: 1, thread: "a", target: "unrecognized", body: fixture.body(event: "requestApproval", request: "r", turn: "t"))
        try fixture.insert(id: 2, thread: "b", target: "serverRequest/resolved", body: fixture.body(event: "approved", request: "r", turn: "t"))
        let values = try fixture.adapter().poll().observations
        XCTAssertEqual(values.count, 1)
        XCTAssertTrue(values.contains { if case .resolved(let resolution) = $0 { return resolution.threadID.rawID == "b" && resolution.requestID.rawID == "r" }; return false })
    }

    func testReadOnlyAdapterDoesNotMutateDatabase() throws {
        try fixture.insert(id: 1, thread: "a", target: "item/fileChange/requestApproval", body: fixture.body(event: "waitingOnApproval", request: "r", turn: "t"))
        let before = try Data(contentsOf: fixture.database)
        _ = try fixture.adapter().poll()
        XCTAssertEqual(before, try Data(contentsOf: fixture.database))
    }

    func testBusyRetryIsBoundedAndFailsClosed() throws {
        var lock: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.database.path, &lock), SQLITE_OK)
        defer { sqlite3_close(lock) }
        try approvalSQL(lock, "BEGIN EXCLUSIVE")
        let result = try fixture.adapter().poll()
        XCTAssertEqual(result.health.reason, .busyExhausted)
        XCTAssertTrue(result.observations.contains { if case .sourceUnavailable = $0 { return true }; return false })
    }
}

private final class ApprovalFixture {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("codex-monitor-v32-\(UUID().uuidString)")
    let database: URL
    let source = ApprovalLocalSourceID("approval-test-source")!
    init() throws { database = root.appendingPathComponent("logs.sqlite"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try createDatabase() }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func createDatabase() throws { var db: OpaquePointer?; guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw POSIXError(.EIO) }; defer { sqlite3_close(db) }; try approvalSQL(db, "PRAGMA user_version = 1"); try approvalSQL(db, "CREATE TABLE logs (id INTEGER PRIMARY KEY, thread_id TEXT NOT NULL, timestamp REAL NOT NULL, target TEXT NOT NULL, level TEXT NOT NULL, body TEXT NOT NULL)") }
    func adapter(checkpoint: ApprovalLogCursor? = nil) -> ApprovalLocalAdapter { ApprovalLocalAdapter(databaseURL: database, sourceID: source, schema: .init(acceptedUserVersions: [1]), checkpoint: checkpoint, retryPolicy: .init(attempts: 2, busyTimeoutMilliseconds: 1, retryDelayMilliseconds: 1)) }
    func body(event: String, request: String, turn: String) -> String { "{\"event\":\"\(event)\",\"request_id\":\"\(request)\",\"turn_id\":\"\(turn)\"}" }
    func insert(id: Int, thread: String, target: String, body: String) throws { var db: OpaquePointer?; guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw POSIXError(.EIO) }; defer { sqlite3_close(db) }; let sql = "INSERT INTO logs VALUES (\(id), '\(thread)', 1800000000, '\(target)', 'info', '\(body.replacingOccurrences(of: "'", with: "''"))')"; try approvalSQL(db, sql) }
    func setUserVersion(_ value: Int) throws { var db: OpaquePointer?; guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw POSIXError(.EIO) }; defer { sqlite3_close(db) }; try approvalSQL(db, "PRAGMA user_version = \(value)") }
}

private func approvalSQL(_ db: OpaquePointer?, _ sql: String) throws { var message: UnsafeMutablePointer<Int8>?; guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else { sqlite3_free(message); throw POSIXError(.EIO) } }
