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
        XCTAssertThrowsError(try adapter.open(threadRawID: "thread-b")) { XCTAssertEqual($0 as? DesktopLocalAdapterError, .threadNotFound) }
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
        XCTAssertThrowsError(try adapter.open(threadRawID: "thread-a")) { XCTAssertEqual($0 as? DesktopLocalAdapterError, .threadNotFound) }
    }

    func testPIDReuseAndWriterLossAreUnavailableEvidenceOnly() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a")])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        let epochOne = ProcessEpoch(pid: 42, startedAtNanoseconds: 1)!
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: epochOne, writerOwnsSelectedRollout: true).health?.state, .available)
        let missing = adapter.health(threadID: thread.threadID, processEpoch: epochOne, writerOwnsSelectedRollout: false)
        XCTAssertEqual(missing.health?.reason, .writerOwnershipMissing)
        let reused = adapter.health(threadID: thread.threadID, processEpoch: ProcessEpoch(pid: 42, startedAtNanoseconds: 2)!, writerOwnsSelectedRollout: true)
        XCTAssertEqual(reused.health?.reason, .processEpochMismatch)
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: epochOne, writerOwnsSelectedRollout: true).health?.reason, .processEpochMismatch)
        XCTAssertNil(reused.rollout)
        XCTAssertNil(missing.rollout)
    }

    func testEpochMismatchLatchesUntilFreshExactRebindThenRejectsOldEpoch() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a")])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        let first = ProcessEpoch(pid: 42, startedAtNanoseconds: 1)!
        let reusedPID = ProcessEpoch(pid: 42, startedAtNanoseconds: 2)!
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: first, writerOwnsSelectedRollout: true).health?.state, .available)
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: reusedPID, writerOwnsSelectedRollout: true).health?.reason, .processEpochMismatch)
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: first, writerOwnsSelectedRollout: true).health?.reason, .processEpochMismatch)

        let rebound = try adapter.open(threadRawID: "thread-a")
        XCTAssertEqual(adapter.health(threadID: rebound.threadID, processEpoch: reusedPID, writerOwnsSelectedRollout: true).health?.state, .available)
        XCTAssertEqual(adapter.health(threadID: rebound.threadID, processEpoch: first, writerOwnsSelectedRollout: true).health?.reason, .processEpochMismatch)
    }

    func testEpochMismatchLatchesAreIndependentPerThread() throws {
        let a = try fixture.rollout("thread-a", lines: [fixture.session("thread-a")])
        let b = try fixture.rollout("thread-b", lines: [fixture.session("thread-b")])
        try fixture.addThread("thread-a", rollout: a); try fixture.addThread("thread-b", rollout: b)
        let adapter = try fixture.adapter(); let first = try adapter.open(threadRawID: "thread-a"); let second = try adapter.open(threadRawID: "thread-b")
        let aOne = ProcessEpoch(pid: 1, startedAtNanoseconds: 1)!, aTwo = ProcessEpoch(pid: 1, startedAtNanoseconds: 2)!, bOne = ProcessEpoch(pid: 2, startedAtNanoseconds: 1)!
        XCTAssertEqual(adapter.health(threadID: first.threadID, processEpoch: aOne, writerOwnsSelectedRollout: true).health?.state, .available)
        XCTAssertEqual(adapter.health(threadID: second.threadID, processEpoch: bOne, writerOwnsSelectedRollout: true).health?.state, .available)
        XCTAssertEqual(adapter.health(threadID: first.threadID, processEpoch: aTwo, writerOwnsSelectedRollout: true).health?.reason, .processEpochMismatch)
        XCTAssertEqual(adapter.health(threadID: second.threadID, processEpoch: bOne, writerOwnsSelectedRollout: true).health?.state, .available)
    }

    func testReplacementDuringReadIsRejectedBeforeValidLookingBytesDecode() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a")])
        try fixture.addThread("thread-a", rollout: file)
        var descriptorOpens = 0
        let adapter = try fixture.adapter(beforeDescriptorOpen: {
            descriptorOpens += 1
            if descriptorOpens == 2 {
                try! self.fixture.atomicReplace(at: file, with: [self.fixture.session("thread-a"), self.fixture.started("turn-replacement"), self.fixture.token(total: 999, last: 999), self.fixture.complete("turn-replacement")].joined(separator: "\n") + "\n")
            }
        })
        let thread = try adapter.open(threadRawID: "thread-a")
        let rejected = try adapter.poll(threadID: thread.threadID)
        XCTAssertEqual(rejected.invalidation, .fileReplaced)
        XCTAssertTrue(rejected.observations.rollouts.isEmpty)
        XCTAssertEqual(rejected.observations.health?.reason, .fileIdentityChanged)

        let rebound = try adapter.open(threadRawID: "thread-a")
        let admitted = try adapter.poll(threadID: rebound.threadID).observations.rollouts
        XCTAssertEqual(admitted.tokenTotals, [999])
        XCTAssertTrue(admitted.contains { $0.kind == .taskCompletedSuccess && $0.turnID?.rawID == "turn-replacement" })
    }

    func testCheckpointAtEOFRevalidatesBeforeAvailableWithoutReplayingHistory() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), fixture.token(total: 10, last: 10)])
        try fixture.addThread("thread-a", rollout: file)
        let initial = try fixture.adapter(); let thread = try initial.open(threadRawID: "thread-a")
        let checkpoint = try XCTUnwrap(try initial.poll(threadID: thread.threadID).cursor)

        let resumed = try fixture.adapter(); let recovered = try resumed.open(threadRawID: "thread-a", checkpoint: checkpoint)
        let epoch = ProcessEpoch(pid: 77, startedAtNanoseconds: 1)!
        XCTAssertEqual(resumed.health(threadID: recovered.threadID, processEpoch: epoch, writerOwnsSelectedRollout: true).health?.state, .unavailable)
        XCTAssertEqual(resumed.health(threadID: recovered.threadID, processEpoch: epoch, writerOwnsSelectedRollout: true).health?.reason, .checkpointAdmissionPending)
        let result = try resumed.poll(threadID: recovered.threadID)
        XCTAssertNil(result.invalidation)
        XCTAssertEqual(result.observations.health?.state, .available)
        XCTAssertTrue(result.observations.rollouts.isEmpty)
        XCTAssertEqual(resumed.health(threadID: recovered.threadID, processEpoch: epoch, writerOwnsSelectedRollout: true).health?.state, .available)
    }

    func testCheckpointResumeRestoresTokenAndTerminalExactlyOnce() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), fixture.token(total: 10, last: 10)])
        try fixture.addThread("thread-a", rollout: file)
        let initial = try fixture.adapter(); let thread = try initial.open(threadRawID: "thread-a")
        let checkpoint = try XCTUnwrap(try initial.poll(threadID: thread.threadID).cursor)
        try fixture.append(to: file, text: fixture.token(total: 20, last: 10) + "\n" + fixture.tool("call-after-restart") + "\n" + fixture.complete("turn-a") + "\n")

        let resumed = try fixture.adapter(); let recovered = try resumed.open(threadRawID: "thread-a", checkpoint: checkpoint)
        let first = try resumed.poll(threadID: recovered.threadID).observations.rollouts
        XCTAssertEqual(first.tokenTotals, [20])
        XCTAssertEqual(first.filter { $0.activity == .tool && $0.itemID?.rawID == "call-after-restart" }.count, 1)
        XCTAssertEqual(first.filter { $0.kind == .taskCompletedSuccess }.count, 1)
        let second = try resumed.poll(threadID: recovered.threadID).observations.rollouts
        XCTAssertTrue(second.isEmpty)
    }

    func testCheckpointHydrationCarriesAuthoritativeTokenAndTerminalSourceTime() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), fixture.token(total: 100, last: 100)])
        try fixture.addThread("thread-a", rollout: file)
        let initial = try fixture.adapter(); let thread = try initial.open(threadRawID: "thread-a")
        let checkpoint = try XCTUnwrap(try initial.poll(threadID: thread.threadID).cursor)
        try fixture.append(to: file, text: fixture.complete("turn-a") + "\n")
        let resumed = try fixture.adapter(); let recovered = try resumed.open(threadRawID: "thread-a", checkpoint: checkpoint)
        let result = try resumed.poll(threadID: recovered.threadID)
        let hydration = try XCTUnwrap(result.hydration)
        XCTAssertEqual(hydration.authoritativeTokenTotal, 100)
        XCTAssertEqual(hydration.terminal?.state, .completed)
        XCTAssertEqual(hydration.terminal?.authoritativeEventAt, fixture.authoritativeTerminalDate)
    }

    func testProductionReconciliationInstallerBuildsAndInstallsRestartState() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), fixture.token(total: 100, last: 100)])
        try fixture.addThread("thread-a", rollout: file)
        let initial = try fixture.adapter(); let thread = try initial.open(threadRawID: "thread-a")
        let checkpoint = try XCTUnwrap(try initial.poll(threadID: thread.threadID).cursor)

        let approvalDatabase = fixture.root.appendingPathComponent("logs.sqlite")
        var approvalDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(approvalDatabase.path, &approvalDB), SQLITE_OK)
        defer { sqlite3_close(approvalDB) }
        try execute(approvalDB, "PRAGMA user_version = 0")
        try execute(approvalDB, "CREATE TABLE logs (id INTEGER PRIMARY KEY, thread_id TEXT NOT NULL, ts REAL NOT NULL, target TEXT NOT NULL, level TEXT NOT NULL, feedback_log_body TEXT NOT NULL)")
        // These are deliberately non-approval target rows.  A one-row page
        // forces several source pages while preserving a known-not-waiting
        // snapshot; the installer must reach the final cursor before live.
        for id in 1...3 { try execute(approvalDB, "INSERT INTO logs VALUES (\(id), 'thread-a', 1, 'codex_core::stream_events_utils', 'info', 'ordinary')") }
        let approvalStore = ApprovalLifecycleCheckpointStore(url: fixture.root.appendingPathComponent("approval-checkpoint.json"))
        let approvals = try ApprovalLifecycleRuntimeOwner(databaseURL: approvalDatabase, sourceID: ApprovalLocalSourceID("test-desktop-source")!, schema: .init(acceptedUserVersions: [0]), store: approvalStore, retryPolicy: .init(maximumRowsPerPoll: 1))
        let engine = RuntimeStateEngine()
        XCTAssertEqual(engine.snapshot().state, .paused)
        let installer = LocalRuntimeReconciliationInstaller(desktop: try fixture.adapter(), approvals: approvals, engine: engine, approvalCatchUpPolicy: .init(maximumPolls: 8))
        let rebuilt = try installer.install(threadCheckpoints: [try XCTUnwrap(LocalRuntimeThreadCheckpoint(threadRawID: "thread-a", rolloutCursor: checkpoint))])

        XCTAssertEqual(rebuilt.count, 1)
        XCTAssertEqual(approvals.adapter.checkpoint()?.lastLogID, 3, "installer must catch up beyond the first approval page before entering live")
        XCTAssertGreaterThan(try XCTUnwrap(installer.lastApprovalCatchUp).polls, 2)
        let snapshot = try XCTUnwrap(engine.snapshot().threads.first)
        XCTAssertEqual(snapshot.state, .thinking)
        XCTAssertEqual(snapshot.sessionTokenCumulative, 100)
        XCTAssertEqual(snapshot.sessionTokenProvenance, .rolloutCumulativeAuthoritative)
    }

    func testProductionInstallerFailsClosedWhenApprovalCatchUpCannotStabilize() throws {
        let store = ApprovalLifecycleCheckpointStore(url: fixture.root.appendingPathComponent("approval-checkpoint.json"))
        let approvals = try ApprovalLifecycleRuntimeOwner(databaseURL: fixture.root.appendingPathComponent("missing-logs.sqlite"), sourceID: ApprovalLocalSourceID("test-desktop-source")!, schema: .init(acceptedUserVersions: [0]), store: store)
        let engine = RuntimeStateEngine()
        let installer = LocalRuntimeReconciliationInstaller(desktop: try fixture.adapter(), approvals: approvals, engine: engine, approvalCatchUpPolicy: .init(maximumPolls: 2))

        XCTAssertThrowsError(try installer.install(threadCheckpoints: [])) {
            XCTAssertEqual($0 as? ApprovalCatchUpError, .sourceUnavailable(.sourceMissing))
        }
        XCTAssertEqual(engine.snapshot().state, .paused)
    }

    func testFunctionOutputUsesCompletionBranchAndTerminalNeverUsesDecodeTime() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a"), fixture.tool("call-a"), fixture.toolOutput("call-a"), fixture.complete("turn-a")])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        let records = try adapter.poll(threadID: thread.threadID).observations.rollouts
        XCTAssertTrue(records.contains { $0.activity == .agentResponse && $0.itemID?.rawID == "call-a" })
        let terminal = try XCTUnwrap(records.first { $0.kind == .taskCompletedSuccess })
        XCTAssertEqual(terminal.authoritativeEventAt, fixture.authoritativeTerminalDate)
        XCTAssertNotEqual(terminal.authoritativeEventAt, terminal.observedAt)

        // Exercise the real decoder-to-reducer path: the output clears only
        // the exact request/call, through agentResponse rather than thinking.
        let engine = RuntimeStateEngine(initialPhase: .live)
        for record in records.prefix(2) { engine.ingest(record) }
        let turn = try XCTUnwrap(records.first { $0.kind == .taskStarted }?.turnID)
        let call = try XCTUnwrap(records.first { $0.activity == .tool }?.itemID)
        engine.ingest(.requested(ApprovalRequested(threadID: thread.threadID, turnID: turn, requestID: call, observedAt: Date())))
        XCTAssertEqual(engine.snapshot().threads.first?.state, .waitingApproval)
        engine.ingest(try XCTUnwrap(records.first { $0.activity == .agentResponse }))
        XCTAssertEqual(engine.snapshot().threads.first?.state, .thinking)
    }

    func testCheckpointRejectsReplacedFileAndSameInodeSessionMismatch() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a")])
        try fixture.addThread("thread-a", rollout: file)
        let initial = try fixture.adapter(); let thread = try initial.open(threadRawID: "thread-a")
        let checkpoint = try XCTUnwrap(try initial.poll(threadID: thread.threadID).cursor)
        try fixture.atomicReplace(at: file, with: fixture.session("thread-a") + "\n")
        let replaced = try fixture.adapter(); let reopened = try replaced.open(threadRawID: "thread-a", checkpoint: checkpoint)
        XCTAssertEqual(try replaced.poll(threadID: reopened.threadID).invalidation, .fileReplaced)

        let fresh = try fixture.adapter(); let current = try fresh.open(threadRawID: "thread-a")
        let sameInodeCheckpoint = try XCTUnwrap(try fresh.poll(threadID: current.threadID).cursor)
        try fixture.replaceContents(at: file, with: fixture.session("thread-b") + "\n" + fixture.started("turn-a") + "\n")
        let mismatch = try fixture.adapter(); let resumed = try mismatch.open(threadRawID: "thread-a", checkpoint: sameInodeCheckpoint)
        let result = try mismatch.poll(threadID: resumed.threadID)
        XCTAssertEqual(result.invalidation, .sessionMismatch)
        XCTAssertTrue(result.observations.containsUnavailable(.rolloutSessionIdentity))
        XCTAssertNil(result.observations.health)
    }

    func testCheckpointPendingRetainsEpochMismatchUntilExactAdmissionThenRejectsOldEpoch() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a")])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        let checkpoint = try XCTUnwrap(try adapter.poll(threadID: thread.threadID).cursor)
        let oldEpoch = ProcessEpoch(pid: 42, startedAtNanoseconds: 1)!
        let newEpoch = ProcessEpoch(pid: 42, startedAtNanoseconds: 2)!
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: oldEpoch, writerOwnsSelectedRollout: true).health?.state, .available)
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: newEpoch, writerOwnsSelectedRollout: true).health?.reason, .processEpochMismatch)

        _ = try adapter.open(threadRawID: "thread-a", checkpoint: checkpoint)
        let pending = adapter.health(threadID: thread.threadID, processEpoch: newEpoch, writerOwnsSelectedRollout: true).health
        XCTAssertEqual(pending?.state, .unavailable)
        XCTAssertEqual(pending?.reason, .checkpointAdmissionPending)

        XCTAssertNil(try adapter.poll(threadID: thread.threadID).invalidation)
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: newEpoch, writerOwnsSelectedRollout: true).health?.state, .available)
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: oldEpoch, writerOwnsSelectedRollout: true).health?.reason, .processEpochMismatch)
    }

    func testCheckpointReplacementFailureKeepsEpochLatchUnavailable() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a")])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        let checkpoint = try XCTUnwrap(try adapter.poll(threadID: thread.threadID).cursor)
        let oldEpoch = ProcessEpoch(pid: 43, startedAtNanoseconds: 1)!
        let newEpoch = ProcessEpoch(pid: 43, startedAtNanoseconds: 2)!
        _ = adapter.health(threadID: thread.threadID, processEpoch: oldEpoch, writerOwnsSelectedRollout: true)
        _ = adapter.health(threadID: thread.threadID, processEpoch: newEpoch, writerOwnsSelectedRollout: true)
        try fixture.atomicReplace(at: file, with: fixture.session("thread-a") + "\n")

        _ = try adapter.open(threadRawID: "thread-a", checkpoint: checkpoint)
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: newEpoch, writerOwnsSelectedRollout: true).health?.state, .unavailable)
        let rejected = try adapter.poll(threadID: thread.threadID)
        XCTAssertEqual(rejected.invalidation, .fileReplaced)
        XCTAssertTrue(rejected.observations.rollouts.isEmpty)
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: newEpoch, writerOwnsSelectedRollout: true).health?.state, .unavailable)
    }

    func testCheckpointSessionMismatchFailureKeepsEpochLatchUnavailable() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a")])
        try fixture.addThread("thread-a", rollout: file)
        let adapter = try fixture.adapter(); let thread = try adapter.open(threadRawID: "thread-a")
        let checkpoint = try XCTUnwrap(try adapter.poll(threadID: thread.threadID).cursor)
        let oldEpoch = ProcessEpoch(pid: 44, startedAtNanoseconds: 1)!
        let newEpoch = ProcessEpoch(pid: 44, startedAtNanoseconds: 2)!
        _ = adapter.health(threadID: thread.threadID, processEpoch: oldEpoch, writerOwnsSelectedRollout: true)
        _ = adapter.health(threadID: thread.threadID, processEpoch: newEpoch, writerOwnsSelectedRollout: true)
        try fixture.replaceContents(at: file, with: fixture.session("thread-b") + "\n" + fixture.started("turn-a") + "\n")

        _ = try adapter.open(threadRawID: "thread-a", checkpoint: checkpoint)
        let rejected = try adapter.poll(threadID: thread.threadID)
        XCTAssertEqual(rejected.invalidation, .sessionMismatch)
        XCTAssertTrue(rejected.observations.rollouts.isEmpty)
        XCTAssertEqual(adapter.health(threadID: thread.threadID, processEpoch: newEpoch, writerOwnsSelectedRollout: true).health?.state, .unavailable)
    }

    func testCheckpointPendingIsIsolatedFromOtherThreadHealth() throws {
        let a = try fixture.rollout("thread-a", lines: [fixture.session("thread-a")])
        let b = try fixture.rollout("thread-b", lines: [fixture.session("thread-b")])
        try fixture.addThread("thread-a", rollout: a); try fixture.addThread("thread-b", rollout: b)
        let adapter = try fixture.adapter(); let first = try adapter.open(threadRawID: "thread-a"); let second = try adapter.open(threadRawID: "thread-b")
        let checkpoint = try XCTUnwrap(try adapter.poll(threadID: first.threadID).cursor)
        let aOld = ProcessEpoch(pid: 1, startedAtNanoseconds: 1)!, aNew = ProcessEpoch(pid: 1, startedAtNanoseconds: 2)!, bEpoch = ProcessEpoch(pid: 2, startedAtNanoseconds: 1)!
        _ = adapter.health(threadID: first.threadID, processEpoch: aOld, writerOwnsSelectedRollout: true)
        _ = adapter.health(threadID: first.threadID, processEpoch: aNew, writerOwnsSelectedRollout: true)
        XCTAssertEqual(adapter.health(threadID: second.threadID, processEpoch: bEpoch, writerOwnsSelectedRollout: true).health?.state, .available)

        _ = try adapter.open(threadRawID: "thread-a", checkpoint: checkpoint)
        XCTAssertEqual(adapter.health(threadID: first.threadID, processEpoch: aNew, writerOwnsSelectedRollout: true).health?.state, .unavailable)
        XCTAssertEqual(adapter.health(threadID: second.threadID, processEpoch: bEpoch, writerOwnsSelectedRollout: true).health?.state, .available)
    }

    func testCheckpointFirstPollRequiresCurrentExactStateDBBinding() throws {
        let file = try fixture.rollout("thread-a", lines: [fixture.session("thread-a"), fixture.started("turn-a")])
        let moved = try fixture.rollout("thread-a-moved", lines: [fixture.session("thread-a"), fixture.started("turn-moved"), fixture.token(total: 500, last: 500)])
        try fixture.addThread("thread-a", rollout: file)
        let initial = try fixture.adapter(); let thread = try initial.open(threadRawID: "thread-a")
        let checkpoint = try XCTUnwrap(try initial.poll(threadID: thread.threadID).cursor)

        let resumed = try fixture.adapter(); let recovered = try resumed.open(threadRawID: "thread-a", checkpoint: checkpoint)
        try fixture.updatePath(thread: "thread-a", path: moved)
        let result = try resumed.poll(threadID: recovered.threadID)
        XCTAssertTrue(result.observations.containsUnavailable(.stateDatabase))
        XCTAssertTrue(result.observations.rollouts.isEmpty)
        XCTAssertNil(result.observations.health)
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
    let authoritativeTerminalDate = ISO8601DateFormatter().date(from: "2030-01-01T00:00:00Z")!

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
    func adapter(beforeDescriptorOpen: (() -> Void)? = nil) throws -> DesktopLocalAdapter {
        let reader = StateDBReader(databaseURL: database, sourceID: sourceID, schema: .init(acceptedUserVersions: [1]))
        return DesktopLocalAdapter(sourceID: sourceID, validatedSessionRoots: [root], stateDB: reader, readerBeforeDescriptorOpen: beforeDescriptorOpen)
    }
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
    func atomicReplace(at url: URL, with text: String) throws {
        let replacement = root.appendingPathComponent("replacement-\(UUID().uuidString).jsonl")
        try Data(text.utf8).write(to: replacement)
        guard rename(replacement.path, url.path) == 0 else { throw POSIXError(.EIO) }
    }
    func addThread(_ id: String, rollout: URL, title: String = "title") throws {
        try executeDatabase("INSERT INTO threads VALUES ('\(sql(id))', '\(sql(rollout.path))', '\(sql(title))', 'gpt-test', 'high', 1, 0)")
    }
    func updatePath(thread: String, path: URL) throws { try executeDatabase("UPDATE threads SET rollout_path = '\(sql(path.path))' WHERE id = '\(sql(thread))'") }
    func session(_ id: String) -> String { "{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\"}}" }
    func started(_ turn: String) -> String { "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"\(turn)\",\"started_at\":1}}" }
    func token(total: Int, last: Int) -> String { "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)},\"last_token_usage\":{\"total_tokens\":\(last)}}}}" }
    func reasoning(_ id: String) -> String { "{\"type\":\"response_item\",\"payload\":{\"type\":\"reasoning\",\"id\":\"\(id)\"}}" }
    func tool(_ id: String) -> String { "{\"type\":\"response_item\",\"payload\":{\"type\":\"function_call\",\"call_id\":\"\(id)\"}}" }
    func complete(_ turn: String) -> String { "{\"timestamp\":\"2030-01-01T00:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"\(turn)\",\"completed_at\":1893456000,\"error\":null}}" }
    func toolOutput(_ id: String) -> String { "{\"type\":\"response_item\",\"payload\":{\"type\":\"function_call_output\",\"call_id\":\"\(id)\"}}" }

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
