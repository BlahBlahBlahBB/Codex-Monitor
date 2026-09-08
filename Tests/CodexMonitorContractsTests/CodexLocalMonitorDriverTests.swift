import XCTest
import Foundation
import CSQLite
@testable import CodexMonitorContracts
@testable import CodexMonitorApp

final class CodexLocalMonitorDriverTests: XCTestCase {
    func testProductionDriverBootstrapRestoresExactPendingFromCheckpointRoundTrip() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: false)
        defer { fixture.cleanup() }
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("driver-key".utf8)))
        let owner = try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1"))
        try fixture.persist(owner: owner, health: .available)
        let engine = RuntimeStateEngine()
        let runtime = MonitorRuntimeStore(engine: engine)
        let driver = fixture.driver(runtime: runtime, resolver: deriver)

        await driver.refreshOnce()
        let snapshot = await runtime.snapshot()
        let thread = try XCTUnwrap(snapshot.threads.first)
        XCTAssertEqual(thread.threadID.rawID, "thread-a")
        XCTAssertEqual(thread.activeTurnID?.rawID, "t1")
        XCTAssertEqual(thread.state, .waitingApproval)
        XCTAssertEqual(thread.waitingApproval.availability, .available)
        XCTAssertEqual(snapshot.waitingApprovalCount, 1)
        XCTAssertEqual(engine.snapshot().threads.first?.approvalHealth, .availableWaiting)
        XCTAssertEqual(snapshot.activeThreadCount, 0)
        let stored = try String(decoding: Data(contentsOf: fixture.checkpoint), as: UTF8.self)
        XCTAssertFalse(stored.contains("prompt")); XCTAssertFalse(stored.contains("tool_input")); XCTAssertFalse(stored.contains("thread-a")); XCTAssertFalse(stored.contains("t1"))
    }

    func testProductionDriverBootstrapDoesNotAttachStaleT1PendingToHydratedT2() async throws {
        let fixture = try DriverFixture(turn: "t2", terminal: false)
        defer { fixture.cleanup() }
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("driver-key".utf8)))
        let stale = try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1"))
        let current = try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t2"))
        XCTAssertNotEqual(stale, current)
        try fixture.persist(owner: stale, health: .available)
        let runtime = MonitorRuntimeStore(); await fixture.driver(runtime: runtime, resolver: deriver).refreshOnce()
        let snapshot = await runtime.snapshot()
        // Startup deliberately suppresses historical activity until it sees a
        // fresh live event. It must not manufacture T2 ownership from T1.
        XCTAssertNil(snapshot.threads.first?.activeTurnID)
        XCTAssertNotEqual(snapshot.threads.first?.state, .waitingApproval)
        XCTAssertEqual(snapshot.waitingApprovalCount, 0)
    }

    func testProductionDriverBootstrapDoesNotAttachDifferentKeyOwner() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: false)
        defer { fixture.cleanup() }
        let good = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("good".utf8)))
        let wrong = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("wrong".utf8)))
        let durableOwner = try XCTUnwrap(wrong.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1"))
        let currentOwner = try XCTUnwrap(good.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1"))
        XCTAssertNotEqual(durableOwner, currentOwner)
        try fixture.persist(owner: durableOwner, health: .available)
        let mismatchRuntime = MonitorRuntimeStore(); await fixture.driver(runtime: mismatchRuntime, resolver: good).refreshOnce()
        let mismatch = await mismatchRuntime.snapshot()
        XCTAssertNotEqual(mismatch.currentState, .waitingApproval)
        XCTAssertEqual(mismatch.waitingApprovalCount, 0)
    }

    func testProductionDriverBootstrapFailsClosedWhenIdentityAuthorityIsMissing() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: false)
        defer { fixture.cleanup() }
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("good".utf8)))
        try fixture.persist(owner: try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1")), health: .available)
        let missingRuntime = MonitorRuntimeStore(); await fixture.driver(runtime: missingRuntime, resolver: nil).refreshOnce()
        let missing = await missingRuntime.snapshot().threads.first
        XCTAssertNotEqual(missing?.state, .waitingApproval)
        XCTAssertEqual(missing?.waitingApproval.availability, .unknown)
    }

    func testProductionDriverBootstrapTerminalDefeatsDurablePending() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: true)
        defer { fixture.cleanup() }
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("driver-key".utf8)))
        try fixture.persist(owner: try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1")), health: .available)
        let runtime = MonitorRuntimeStore(); await fixture.driver(runtime: runtime, resolver: deriver).refreshOnce()
        let snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.currentState, .completed)
        XCTAssertNil(snapshot.currentThread?.activeTurnID)
        XCTAssertEqual(snapshot.waitingApprovalCount, 0)
    }

    func testProductionDriverBootstrapPreservesExactPendingWhenHookSourceBecomesUnavailable() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: false)
        defer { fixture.cleanup() }
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("driver-key".utf8)))
        let owner = try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1"))
        try fixture.persist(owner: owner, health: .available)
        fixture.journalSource.failReads = true
        let runtime = MonitorRuntimeStore(); await fixture.driver(runtime: runtime, resolver: deriver).refreshOnce()
        let snapshot = await runtime.snapshot()
        let thread = try XCTUnwrap(snapshot.threads.first)
        XCTAssertEqual(thread.state, .waitingApproval)
        XCTAssertEqual(thread.waitingApproval.availability, .unavailable)
        XCTAssertNotEqual(thread.waitingApproval.availability, .available)
    }

    func testProductionDriverBootstrapDoesNotClaimKnownNotWaitingWhenUnavailableWithoutPending() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: false)
        defer { fixture.cleanup() }
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("driver-key".utf8)))
        let owner = try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1"))
        try fixture.persist(owner: owner, health: .available, pending: false)
        fixture.journalSource.failReads = true
        let runtime = MonitorRuntimeStore(); await fixture.driver(runtime: runtime, resolver: deriver).refreshOnce()
        let snapshot = await runtime.snapshot()
        let thread = try XCTUnwrap(snapshot.threads.first)
        XCTAssertNotEqual(thread.state, .waitingApproval)
        XCTAssertEqual(thread.waitingApproval.availability, .unavailable)
    }

    func testProductionDriverBootstrapKeepsPendingScopedToItsExactThread() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: false, includeSecondThread: true)
        defer { fixture.cleanup() }
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("driver-key".utf8)))
        let owner = try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1"))
        try fixture.persist(owner: owner, health: .available)
        let runtime = MonitorRuntimeStore()
        let driver = fixture.driver(runtime: runtime, resolver: deriver)

        await driver.refreshOnce()
        fixture.appendFreshTurnStartForThreadB()
        await driver.refreshOnce()
        await driver.refreshOnce()

        let snapshot = await runtime.snapshot()
        let a = try XCTUnwrap(snapshot.threads.first { $0.threadID.rawID == "thread-a" })
        let b = try XCTUnwrap(snapshot.threads.first { $0.threadID.rawID == "thread-b" })
        XCTAssertEqual(a.state, .waitingApproval)
        XCTAssertEqual(b.activeTurnID?.rawID, "b1")
        XCTAssertNotEqual(b.state, .waitingApproval)
        XCTAssertEqual(snapshot.waitingApprovalCount, 1)
        XCTAssertEqual(snapshot.currentThread?.threadID.rawID, "thread-a")
    }

    func testOnlyExactlyAdmittedPermissionRequestsCreateOutboxNotifications() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: false)
        defer { fixture.cleanup() }
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("driver-key".utf8)))
        let owner = try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1"))
        let rejectedOwner = try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "unmapped-thread", turnRawID: "t1"))
        let delivery = ApprovalOutboxDeliveryRecorder()
        let runtime = MonitorRuntimeStore()
        let driver = fixture.driver(runtime: runtime, resolver: deriver, approvalNotificationDelivery: { intent in
            await delivery.deliver(intent)
        })

        await driver.refreshOnce()
        fixture.appendFreshTurnStartForThreadA()
        try fixture.appendPermissionRequest(owner: owner, eventID: 7)
        await driver.refreshOnce()
        await driver.refreshOnce()

        let first = await delivery.submitted()
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.journalEventID, HookApprovalJournalEventID(7))
        XCTAssertEqual(first.first?.sourceID, owner.sourceID)
        XCTAssertEqual(first.first?.taskTitle, L10n.tr("activity.currentTask"))
        let waitingSnapshot = await runtime.snapshot()
        XCTAssertEqual(waitingSnapshot.currentState, .waitingApproval)

        // A new journal row whose owner is not bound to any runtime thread is
        // rejected by the frozen reducer. Existing task A remains waiting, but
        // event B must not become a notification merely because of that state.
        try fixture.appendPermissionRequest(owner: rejectedOwner, eventID: 8)
        await driver.refreshOnce()
        let afterRejected = await delivery.submitted()
        XCTAssertEqual(afterRejected.map(\.journalEventID), [HookApprovalJournalEventID(7)!])

        // A second exact PermissionRequest in the same bound turn is a
        // separate journal event and therefore gets its own notification.
        try fixture.appendPermissionRequest(owner: owner, eventID: 9)
        await driver.refreshOnce()
        let second = await delivery.submitted()
        XCTAssertEqual(second.map(\.journalEventID), [HookApprovalJournalEventID(7)!, HookApprovalJournalEventID(9)!])

        await driver.refreshOnce()
        let afterReconcile = await delivery.submitted()
        XCTAssertEqual(afterReconcile.count, 2)

        let restartedDelivery = ApprovalOutboxDeliveryRecorder()
        let restarted = fixture.driver(runtime: MonitorRuntimeStore(), resolver: deriver, approvalNotificationDelivery: { candidate in
            await restartedDelivery.deliver(candidate)
        })
        await restarted.refreshOnce()
        let restartedValues = await restartedDelivery.submitted()
        XCTAssertTrue(restartedValues.isEmpty)
    }

    func testCheckpointFailurePreventsDeliveryAndRetriesTheSameJournalEvent() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: false)
        defer { fixture.cleanup() }
        let store = InMemoryApprovalCheckpointStore()
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("retry-key".utf8)))
        let owner = try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1"))
        let delivery = ApprovalOutboxDeliveryRecorder()
        let driver = fixture.driver(runtime: MonitorRuntimeStore(), resolver: deriver, approvalCheckpointStore: store, approvalNotificationDelivery: { intent in
            await delivery.deliver(intent)
        })

        await driver.refreshOnce()
        fixture.appendFreshTurnStartForThreadA()
        try fixture.appendPermissionRequest(owner: owner, eventID: 7)
        // Incremental polling saves the legacy checkpoint first, then the
        // Hook cursor plus outbox intent. Both failures are injected so the
        // event cannot be sent from an uncommitted cursor.
        store.failNextSaves(2)
        await driver.refreshOnce()
        let failedValues = await delivery.submitted()
        XCTAssertTrue(failedValues.isEmpty)
        XCTAssertTrue(store.latest().notificationOutbox.isEmpty)

        await driver.refreshOnce()
        let retriedValues = await delivery.submitted()
        XCTAssertEqual(retriedValues.map(\.journalEventID), [HookApprovalJournalEventID(7)!])
        XCTAssertTrue(store.latest().notificationOutbox.isEmpty)
    }

    func testDurableOutboxRecoversAfterCrashBeforeNotificationAdd() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: false)
        defer { fixture.cleanup() }
        let store = InMemoryApprovalCheckpointStore()
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("crash-before-add".utf8)))
        let owner = try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1"))
        let first = fixture.driver(runtime: MonitorRuntimeStore(), resolver: deriver, approvalCheckpointStore: store, approvalNotificationDelivery: { _ in .retry })

        await first.refreshOnce()
        fixture.appendFreshTurnStartForThreadA()
        try fixture.appendPermissionRequest(owner: owner, eventID: 7)
        await first.refreshOnce()
        XCTAssertEqual(store.latest().notificationOutbox.count, 1)

        let recoveredDelivery = ApprovalOutboxDeliveryRecorder()
        let restarted = fixture.driver(runtime: MonitorRuntimeStore(), resolver: deriver, approvalCheckpointStore: store, approvalNotificationDelivery: { intent in
            await recoveredDelivery.deliver(intent)
        })
        await restarted.refreshOnce()
        let recoveredValues = await recoveredDelivery.submitted()
        XCTAssertEqual(recoveredValues.map(\.journalEventID), [HookApprovalJournalEventID(7)!])
        XCTAssertTrue(store.latest().notificationOutbox.isEmpty)
    }

    func testDurableOutboxRecoveryDoesNotDependOnCodexStillRunning() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: false)
        defer { fixture.cleanup() }
        let store = InMemoryApprovalCheckpointStore()
        let source = HookOpaqueIdentity("hmac-sha256:" + String(repeating: "c", count: 64))!
        let intent = ApprovalNotificationOutboxIntent(sourceID: source, journalEventID: HookApprovalJournalEventID(7)!, taskTitle: "Recovered approval")
        try store.save(ApprovalLifecycleCheckpoint(cursor: nil, unresolved: [], notificationOutbox: [intent]))
        let delivery = ApprovalOutboxDeliveryRecorder()
        let driver = fixture.driver(
            runtime: MonitorRuntimeStore(),
            resolver: nil,
            approvalCheckpointStore: store,
            processIsRunning: { false },
            approvalNotificationDelivery: { value in
            await delivery.deliver(value)
            }
        )

        await driver.refreshOnce()
        let recovered = await delivery.submitted()
        XCTAssertEqual(recovered.map(\.requestIdentifier), [intent.requestIdentifier])
        XCTAssertTrue(store.latest().notificationOutbox.isEmpty)
    }

    func testAddThenAcknowledgementFailureReconcilesWithoutDuplicateOnRestart() async throws {
        let fixture = try DriverFixture(turn: "t1", terminal: false)
        defer { fixture.cleanup() }
        let store = InMemoryApprovalCheckpointStore()
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("ack-retry".utf8)))
        let owner = try XCTUnwrap(deriver.owner(sourceRawID: "codex-desktop-local", sessionRawID: "thread-a", turnRawID: "t1"))
        let delivery = ApprovalOutboxDeliveryRecorder()
        let first = fixture.driver(runtime: MonitorRuntimeStore(), resolver: deriver, approvalCheckpointStore: store, approvalNotificationDelivery: { intent in
            await delivery.deliver(intent)
        })

        await first.refreshOnce() // save #1: empty Hook batch
        // Incremental save #2 is legacy, #3 is cursor + intent, and #4 is the
        // post-add acknowledgement that we deliberately fail.
        store.failOnSave(number: 4)
        fixture.appendFreshTurnStartForThreadA()
        try fixture.appendPermissionRequest(owner: owner, eventID: 7)
        await first.refreshOnce()
        let firstDelivery = await delivery.submitted()
        XCTAssertEqual(firstDelivery.count, 1)
        XCTAssertEqual(store.latest().notificationOutbox.count, 1)

        let restarted = fixture.driver(runtime: MonitorRuntimeStore(), resolver: deriver, approvalCheckpointStore: store, approvalNotificationDelivery: { intent in
            await delivery.deliver(intent)
        })
        await restarted.refreshOnce()
        let restartedDelivery = await delivery.submitted()
        XCTAssertEqual(restartedDelivery.count, 1)
        XCTAssertTrue(store.latest().notificationOutbox.isEmpty)
    }
}

private final class DriverFixture {
    let root: URL; let checkpoint: URL; let journalSource = FixtureJournalSource()
    private let threadARollout: URL
    private let threadBRollout: URL?
    init(turn: String, terminal: Bool, includeSecondThread: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("driver-hook-\(UUID().uuidString)")
        checkpoint = root.appendingPathComponent("checkpoint.json")
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let rollout = sessions.appendingPathComponent("thread-a.jsonl")
        threadARollout = rollout
        var lines = ["{\"type\":\"session_meta\",\"payload\":{\"id\":\"thread-a\"}}", "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"\(turn)\",\"started_at\":1}}"]
        if terminal { lines.append("{\"timestamp\":\"2030-01-01T00:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"\(turn)\",\"completed_at\":1893456000}}") }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: rollout)
        let dbURL = root.appendingPathComponent("state_5.sqlite")
        var db: OpaquePointer?; guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { throw POSIXError(.EIO) }; defer { sqlite3_close(db) }
        try sql(db, "PRAGMA user_version = 0")
        try sql(db, "CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, title TEXT, model TEXT, reasoning_effort TEXT, updated_at INTEGER, tokens_used INTEGER)")
        try sql(db, "INSERT INTO threads VALUES ('thread-a', '\(rollout.path)', 'safe', 'gpt-test', 'high', 1, 0)")
        if includeSecondThread {
            let rolloutB = sessions.appendingPathComponent("thread-b.jsonl")
            try Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"thread-b\"}}\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"b0\",\"started_at\":1}}\n".utf8).write(to: rolloutB)
            try sql(db, "INSERT INTO threads VALUES ('thread-b', '\(rolloutB.path)', 'safe-b', 'gpt-test', 'high', 2, 0)")
            threadBRollout = rolloutB
        } else {
            threadBRollout = nil
        }
    }
    func persist(owner: HookApprovalTurnOwner, health: HookApprovalSourceHealthState, pending: Bool = true) throws {
        let eventID = HookApprovalJournalEventID(1)!
        let evidence = HookApprovalPendingEvidence(journalEventID: eventID, owner: owner, observedAt: Date())
        try ApprovalLifecycleCheckpointStore(url: checkpoint).save(ApprovalLifecycleCheckpoint(cursor: nil, unresolved: [], hookJournal: HookApprovalJournalCheckpoint(sourceID: owner.sourceID, lastJournalEventID: pending ? eventID : nil, unresolved: pending ? [evidence] : [], sourceHealth: health)))
        let record = try XCTUnwrap(HookApprovalJournalRecord(journalEventID: eventID, kind: .permissionRequest, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: 1))
        journalSource.records = [try JSONEncoder().encode(record)]
    }
    func driver(runtime: MonitorRuntimeStore, resolver: (any HookApprovalIdentityResolving)?, approvalCheckpointStore: (any ApprovalLifecycleCheckpointStoring)? = nil, processIsRunning: @escaping @Sendable () -> Bool = { true }, approvalNotificationDelivery: @escaping @Sendable (ApprovalNotificationOutboxIntent) async -> ApprovalNotificationDeliveryDisposition = { _ in .retry }) -> CodexLocalMonitorDriver {
        CodexLocalMonitorDriver(runtime: runtime, codexRoot: root, hookJournalSource: journalSource, hookIdentityResolver: resolver, approvalCheckpointURL: checkpoint, approvalCheckpointStore: approvalCheckpointStore, processIsRunning: processIsRunning, approvalNotificationDelivery: approvalNotificationDelivery)
    }
    func appendPermissionRequest(owner: HookApprovalTurnOwner, eventID: UInt64) throws {
        let identifier = try XCTUnwrap(HookApprovalJournalEventID(eventID))
        let record = try XCTUnwrap(HookApprovalJournalRecord(journalEventID: identifier, kind: .permissionRequest, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: Int64(eventID)))
        journalSource.records.append(try JSONEncoder().encode(record))
    }
    func appendFreshTurnStartForThreadA() {
        let line = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"t1\",\"started_at\":2}}\n"
        if let handle = try? FileHandle(forWritingTo: threadARollout) { defer { try? handle.close() }; handle.seekToEndOfFile(); try? handle.write(contentsOf: Data(line.utf8)) }
    }
    func appendFreshTurnStartForThreadB() { guard let threadBRollout else { return }; let line = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"b1\",\"started_at\":2}}\n"; if let handle = try? FileHandle(forWritingTo: threadBRollout) { defer { try? handle.close() }; handle.seekToEndOfFile(); try? handle.write(contentsOf: Data(line.utf8)) } }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private final class FixtureJournalSource: HookApprovalJournalSource, @unchecked Sendable {
    var records: [Data] = []; var failReads = false
    func readRecords() throws -> [Data] { if failReads { throw POSIXError(.EIO) }; return records }
}
private actor ApprovalOutboxDeliveryRecorder {
    private var requestIdentifiers = Set<String>()
    private var values: [ApprovalNotificationOutboxIntent] = []

    func deliver(_ intent: ApprovalNotificationOutboxIntent) -> ApprovalNotificationDeliveryDisposition {
        guard requestIdentifiers.insert(intent.requestIdentifier).inserted else { return .confirmed }
        values.append(intent)
        return .confirmed
    }

    func submitted() -> [ApprovalNotificationOutboxIntent] { values }
}

private final class InMemoryApprovalCheckpointStore: ApprovalLifecycleCheckpointStoring, @unchecked Sendable {
    private var checkpoint = ApprovalLifecycleCheckpoint(cursor: nil, unresolved: [])
    private var saveCount = 0
    private var failedSaveNumbers = Set<Int>()

    func load() throws -> ApprovalLifecycleCheckpoint { checkpoint }

    func save(_ checkpoint: ApprovalLifecycleCheckpoint) throws {
        saveCount += 1
        if failedSaveNumbers.remove(saveCount) != nil {
            throw ApprovalLifecycleCheckpointStoreError.writeFailed
        }
        self.checkpoint = checkpoint
    }

    func failNextSaves(_ count: Int) {
        guard count > 0 else { return }
        failedSaveNumbers.formUnion((saveCount + 1)...(saveCount + count))
    }

    func failOnSave(number: Int) { failedSaveNumbers.insert(number) }
    func latest() -> ApprovalLifecycleCheckpoint { checkpoint }
}
private func sql(_ db: OpaquePointer?, _ statement: String) throws { guard sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK else { throw POSIXError(.EIO) } }
