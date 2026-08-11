import XCTest
import Foundation
import CSQLite
@testable import CodexMonitorContracts

final class V3StateEngineTests: XCTestCase {
    private var clock: V3FakeClock!
    private var engine: RuntimeStateEngine!
    private let source = SourceID("v3-test-source")!

    override func setUp() { clock = V3FakeClock(); engine = RuntimeStateEngine(clock: clock, initialPhase: .live) }

    func testFreshEngineDoesNotExposeLiveStateBeforeReconciliation() {
        let fresh = RuntimeStateEngine(clock: clock)
        XCTAssertEqual(fresh.snapshot().state, .paused)
        fresh.ingest(event(id(.thread, "fresh"), id(.turn, "turn"), .taskStarted))
        XCTAssertTrue(fresh.snapshot().threads.isEmpty)
    }

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

    func testPauseResumeInstallsAuthoritativeTerminalAtomically() {
        let thread = id(.thread, "a"), turn = id(.turn, "turn")
        engine.ingest(event(thread, turn, .taskStarted)); engine.setPaused(true)
        engine.ingest(event(thread, turn, .taskCompletedSuccess))
        XCTAssertEqual(engine.snapshot().state, .paused)
        XCTAssertEqual(engine.snapshot().sourceFreshness.state, .stale)
        engine.setPaused(false); XCTAssertEqual(engine.snapshot().state, .paused)
        engine.installReconciliation([reconciled(thread: thread, turn: turn, terminal: terminal(turn, "terminal-a", .completed))])
        XCTAssertEqual(state(thread), .completed)
    }

    func testTerminalFromAnotherTurnCannotAlterCurrentThreadTurn() {
        let thread = id(.thread, "a")
        engine.ingest(event(thread, id(.turn, "old"), .taskStarted)); engine.ingest(event(thread, id(.turn, "new"), .taskStarted))
        engine.ingest(event(thread, id(.turn, "old"), .taskCompletedSuccess))
        XCTAssertEqual(state(thread), .thinking)
    }

    func testWrongItemAndOverlappingItemCompletionCannotEndCurrentWork() {
        let thread = id(.thread, "items"), turn = id(.turn, "turn"), first = id(.item, "first"), second = id(.item, "second")
        engine.ingest(event(thread, turn, .taskStarted))
        engine.ingest(event(thread, turn, .activity, activity: .tool, item: first))
        engine.ingest(event(thread, turn, .activity, activity: .tool, item: second))
        engine.ingest(event(thread, turn, .activity, activity: .agentResponse, item: first))
        XCTAssertEqual(state(thread), .working)
        engine.ingest(event(thread, turn, .activity, activity: .agentResponse, item: second))
        XCTAssertEqual(state(thread), .thinking)
    }

    func testApprovalSourceLossPreservesPendingAndRecoveryIsThreeValued() {
        let thread = id(.thread, "approval"), turn = id(.turn, "turn"), request = id(.item, "request")
        engine.ingest(event(thread, turn, .taskStarted)); engine.ingest(.requested(ApprovalRequested(threadID: thread, turnID: turn, requestID: request, observedAt: clock.now())))
        engine.ingest(.sourceUnavailable(ApprovalSourceHealth(state: .unavailable, observedAt: clock.now(), reason: .sourceMissing)))
        XCTAssertEqual(state(thread), .waitingApproval)
        XCTAssertEqual(threadSnapshot(thread).approvalHealth, .unavailable)
        engine.ingest(.sourceHealth(ApprovalSourceHealth(state: .available, observedAt: clock.now())))
        XCTAssertEqual(threadSnapshot(thread).approvalHealth, .availableWaiting)
        engine.ingest(.resolved(ApprovalResolved(threadID: thread, turnID: turn, requestID: request, status: .approved, observedAt: clock.now())))
        XCTAssertEqual(threadSnapshot(thread).approvalHealth, .availableKnownNotWaiting)
    }

    func testRestartReconciliationRestoresUnresolvedApprovalsAndExactOutputResolution() {
        let a = id(.thread, "restart-a"), b = id(.thread, "restart-b"), turnA = id(.turn, "turn-a"), turnB = id(.turn, "turn-b")
        let requestA = ApprovalRequested(threadID: a, turnID: turnA, requestID: id(.item, "request-a"), observedAt: clock.now())
        let requestB = ApprovalRequested(threadID: b, turnID: turnB, requestID: id(.item, "request-b"), observedAt: clock.now())
        engine.beginReconciliation()
        engine.installReconciliation([
            reconciled(thread: a, turn: turnA, approval: .availableWaiting, pending: [requestA]),
            reconciled(thread: b, turn: turnB, approval: .availableWaiting, pending: [requestB])
        ])
        XCTAssertEqual(state(a), .waitingApproval); XCTAssertEqual(state(b), .waitingApproval)
        engine.ingest(event(a, turnA, .activity, activity: .agentResponse, item: id(.item, "wrong-output")))
        XCTAssertEqual(state(a), .waitingApproval)
        engine.ingest(event(a, turnA, .activity, activity: .agentResponse, item: requestA.requestID))
        XCTAssertEqual(state(a), .thinking); XCTAssertEqual(state(b), .waitingApproval)
    }

    func testReconciliationInstallsThinkingWorkingWaitingTerminalAndIdleWithoutReplay() {
        let thinking = id(.thread, "recon-thinking"), working = id(.thread, "recon-working"), waiting = id(.thread, "recon-waiting"), terminalThread = id(.thread, "recon-terminal"), idle = id(.thread, "recon-idle")
        let turnThinking = id(.turn, "thinking"), turnWorking = id(.turn, "working"), turnWaiting = id(.turn, "waiting"), turnTerminal = id(.turn, "terminal")
        let request = ApprovalRequested(threadID: waiting, turnID: turnWaiting, requestID: id(.item, "request"), observedAt: clock.now())
        engine.beginReconciliation()
        engine.installReconciliation([
            reconciled(thread: thinking, turn: turnThinking),
            reconciled(thread: working, turn: turnWorking, activeItem: id(.item, "tool"), activity: .tool),
            reconciled(thread: waiting, turn: turnWaiting, approval: .availableWaiting, pending: [request]),
            reconciled(thread: terminalThread, turn: turnTerminal, terminal: terminal(turnTerminal, "historical", .completed, at: clock.now().addingTimeInterval(-6))),
            reconciled(thread: idle, turn: nil)
        ])
        XCTAssertEqual(state(thinking), .thinking); XCTAssertEqual(state(working), .working); XCTAssertEqual(state(waiting), .waitingApproval)
        XCTAssertEqual(state(terminalThread), .idle); XCTAssertEqual(state(idle), .idle)
    }

    func testTokenAndApprovalCapabilityLossDoNotDisconnectRuntimeOrClearOwnerLatch() {
        let thread = id(.thread, "health"), turn = id(.turn, "turn")
        engine.ingest(event(thread, turn, .taskStarted, tokens: 10))
        engine.ingest(.capabilityUnavailable(threadID: thread, capability: .sessionToken))
        engine.ingest(.sourceUnavailable(ApprovalSourceHealth(state: .unavailable, observedAt: clock.now(), reason: .sourceMissing)))
        XCTAssertEqual(state(thread), .thinking)
        engine.ingest(DesktopSourceHealth(threadID: thread, state: .unavailable, processEpoch: nil, fileIdentity: nil, reason: .writerOwnershipMissing))
        engine.ingest(event(thread, turn, .activity, activity: .tool, item: id(.item, "buffered")))
        XCTAssertEqual(state(thread), .disconnected)
    }

    func testTerminalAdmissionDedupeAndAuthoritativeTime() {
        let thread = id(.thread, "terminal"), turn = id(.turn, "turn")
        let historical = event(thread, turn, .taskCompletedSuccess, eventID: "old", authoritativeAt: clock.now().addingTimeInterval(-6))
        engine.ingest(historical); XCTAssertEqual(state(thread), .idle) // nil active terminal is rejected
        engine.ingest(event(thread, turn, .taskStarted))
        engine.ingest(event(thread, turn, .taskCompletedSuccess, eventID: "current", authoritativeAt: clock.now().addingTimeInterval(-4)))
        XCTAssertEqual(state(thread), .completed)
        clock.advance(1); engine.ingest(event(thread, turn, .taskCompletedSuccess, eventID: "current", authoritativeAt: clock.now()))
        XCTAssertEqual(state(thread), .idle) // replay cannot refresh retention
    }

    func testTokenRolloutAuthorityDoesNotRegressOnRegisterAndReconciliation() {
        let thread = id(.thread, "token"), turn = id(.turn, "turn")
        engine.ingest(event(thread, turn, .taskStarted, tokens: 100))
        engine.register(DesktopThreadSnapshot(threadID: thread, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: 90))
        XCTAssertEqual(threadSnapshot(thread).sessionTokenCumulative, 100)
        XCTAssertEqual(threadSnapshot(thread).sessionTokenProvenance, .rolloutCumulativeAuthoritative)
        let hydration = RolloutCheckpointHydration(activeTurnID: turn, turnStartedAt: clock.now(), activeItemID: nil, activeItemCategory: nil, latestActiveState: .thinking, latestActiveStateAt: clock.now(), terminal: nil, authoritativeTokenTotal: 100)
        let seed = DesktopThreadSnapshot(threadID: thread, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: 90)
        let rebuilt = LocalRuntimeReconciliationOwner.thread(snapshot: seed, hydration: hydration, approval: ApprovalLifecycleCheckpoint(cursor: nil, unresolved: []), approvalHealth: .availableKnownNotWaiting, runtimeSourceAvailable: true, observedAt: clock.now())
        LocalRuntimeReconciliationOwner.install([rebuilt], into: engine)
        XCTAssertEqual(threadSnapshot(thread).sessionTokenCumulative, 100)
        XCTAssertEqual(threadSnapshot(thread).sessionTokenProvenance, .rolloutCumulativeAuthoritative)
    }

    private func id(_ kind: EntityKind, _ raw: String) -> NamespacedID { NamespacedID(sourceID: source, entityKind: kind, rawID: raw)! }
    private func event(_ thread: NamespacedID, _ turn: NamespacedID, _ kind: RolloutEventKind, activity: RolloutActivityCategory? = nil, tokens: Int64? = nil, item: NamespacedID? = nil, eventID: String? = nil, authoritativeAt: Date? = nil) -> RolloutRecordEnvelope {
        RolloutRecordEnvelope(threadID: thread, turnID: turn, itemID: item, kind: kind, activity: activity, tokenSnapshot: tokens.map { TokenSnapshot(totalTokens: $0, lastCallTokens: nil) }, model: nil, reasoningEffort: nil, eventID: eventID, authoritativeEventAt: authoritativeAt, observedAt: clock.now(), fileOffset: 0)
    }
    private func state(_ thread: NamespacedID) -> MonitorRuntimeState { engine.snapshot().threads.first { $0.threadID == thread }!.state }
    private func threadSnapshot(_ thread: NamespacedID) -> ThreadRuntimeSnapshot { engine.snapshot().threads.first { $0.threadID == thread }! }
    private func terminal(_ turn: NamespacedID, _ event: String, _ state: MonitorRuntimeState, at: Date? = nil) -> ReconciledTerminal { ReconciledTerminal(turnID: turn, eventID: event, state: state, authoritativeEventAt: at ?? clock.now())! }
    private func reconciled(thread: NamespacedID, turn: NamespacedID?, terminal: ReconciledTerminal? = nil, tokens: Int64? = nil, provenance: SessionTokenProvenance? = nil, activeItem: NamespacedID? = nil, activity: RuntimeActivityCategory? = nil, approval: ApprovalCapabilityHealth = .availableKnownNotWaiting, pending: [ApprovalRequested] = []) -> RuntimeReconciliationThread { RuntimeReconciliationThread(threadID: thread, activeTurnID: terminal == nil ? turn : nil, turnStartedAt: turn == nil ? nil : clock.now(), latestActiveState: terminal == nil && turn != nil ? (activity == nil ? .thinking : .working) : nil, latestActiveStateAt: clock.now(), activeItemID: activeItem, activeItemCategory: activity, terminal: terminal, sessionTokenCumulative: tokens, sessionTokenProvenance: provenance, approvalHealth: approval, unresolvedApprovals: pending, runtimeSourceAvailable: true, runtimeObservedAt: clock.now(), approvalObservedAt: clock.now()) }
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

    func testRealInstalledShapeRequestResolutionAndLifecycleRestartCheckpoint() throws {
        try fixture.insert(id: 1, thread: "a", target: fixture.realTarget, body: fixture.requestBody(thread: "a", request: "r-a", turn: "t-a"))
        let adapter = fixture.adapter(); let first = try adapter.poll()
        XCTAssertEqual(first.observations.count, 1); XCTAssertNotNil(first.cursor)
        XCTAssertTrue(first.observations.contains { if case .requested = $0 { return true }; return false })
        XCTAssertTrue((try adapter.poll()).observations.isEmpty)
        let resumed = fixture.adapter(lifecycleCheckpoint: adapter.lifecycleCheckpoint())
        XCTAssertTrue((try resumed.poll()).observations.isEmpty)
        try fixture.insert(id: 2, thread: "a", target: fixture.realTarget, body: fixture.resolutionBody(thread: "a", request: "r-a", turn: "t-a", variant: "approvalApproved"))
        let resolution = try resumed.poll().observations
        XCTAssertTrue(resolution.contains { if case .resolved(let value) = $0 { return value.requestID.rawID == "r-a" }; return false })
        XCTAssertTrue(resumed.lifecycleCheckpoint().unresolved.isEmpty)
    }

    func testRepeatedRealLoggerCorrelationFieldsAndSameRawRequestAcrossThreadsRemainExact() throws {
        let repeated = fixture.requestBody(thread: "a", request: "shared", turn: "t-a")
        try fixture.insert(id: 1, thread: "a", target: fixture.realTarget, body: repeated)
        try fixture.insert(id: 2, thread: "b", target: fixture.realTarget, body: fixture.requestBody(thread: "b", request: "shared", turn: "t-b"))
        let adapter = fixture.adapter()
        let first = try adapter.poll()
        XCTAssertEqual(first.observations.filter { if case .requested = $0 { return true }; return false }.count, 2)
        XCTAssertEqual(adapter.lifecycleCheckpoint().unresolved.count, 2)

        // The same raw request ID is not a cross-thread resolution key.
        try fixture.insert(id: 3, thread: "a", target: fixture.realTarget, body: fixture.resolutionBody(thread: "a", request: "shared", turn: "wrong", variant: "approvalApproved"))
        XCTAssertTrue(try adapter.poll().observations.isEmpty)
        XCTAssertEqual(adapter.lifecycleCheckpoint().unresolved.count, 2)
    }

    func testProductionApprovalLifecycleOwnerPersistsAndRestoresUnresolvedRequest() throws {
        try fixture.insert(id: 1, thread: "a", target: fixture.realTarget, body: fixture.requestBody(thread: "a", request: "r", turn: "t"))
        let store = ApprovalLifecycleCheckpointStore(url: fixture.root.appendingPathComponent("monitor-approval-checkpoint.json"))
        let first = try ApprovalLifecycleRuntimeOwner(databaseURL: fixture.database, sourceID: fixture.source, schema: .init(acceptedUserVersions: [0]), store: store, retryPolicy: .init(attempts: 2, busyTimeoutMilliseconds: 1, retryDelayMilliseconds: 1))
        XCTAssertTrue(try first.poll().observations.contains { if case .requested = $0 { return true }; return false })
        let restarted = try ApprovalLifecycleRuntimeOwner(databaseURL: fixture.database, sourceID: fixture.source, schema: .init(acceptedUserVersions: [0]), store: store, retryPolicy: .init(attempts: 2, busyTimeoutMilliseconds: 1, retryDelayMilliseconds: 1))
        XCTAssertEqual(restarted.adapter.lifecycleCheckpoint().unresolved.count, 1)
        try fixture.insert(id: 2, thread: "a", target: fixture.realTarget, body: fixture.resolutionBody(thread: "a", request: "r", turn: "t", variant: "approvalApproved"))
        XCTAssertTrue(try restarted.poll().observations.contains { if case .resolved = $0 { return true }; return false })
        XCTAssertTrue(restarted.adapter.lifecycleCheckpoint().unresolved.isEmpty)
    }

    func testResolutionRetainingRequestMarkersAdmitsOnlyExactLifecycleTriple() throws {
        try fixture.insert(id: 1, thread: "a", target: fixture.realTarget, body: fixture.requestBody(thread: "a", request: "r", turn: "t"))
        let adapter = fixture.adapter()
        XCTAssertTrue(try adapter.poll().observations.contains { if case .requested = $0 { return true }; return false })
        // Resolution envelopes may retain the request context and repeat their
        // exact correlation values.  Neither property relaxes lifecycle
        // attribution: the pending triple remains the admission gate.
        let retained = "stream_event requestApproval waitingOnApproval turn_id=t turn_id=t turn_id=t turn_id=t approvalApproved call_id=r call_id=r"
        try fixture.insert(id: 2, thread: "a", target: fixture.realTarget, body: retained)
        XCTAssertTrue(try adapter.poll().observations.contains { if case .resolved(let value) = $0 { return value.requestID.rawID == "r" && value.turnID.rawID == "t" }; return false })
        XCTAssertTrue(adapter.lifecycleCheckpoint().unresolved.isEmpty)

        try fixture.insert(id: 3, thread: "a", target: fixture.realTarget, body: fixture.requestBody(thread: "a", request: "other", turn: "next"))
        _ = try adapter.poll()
        try fixture.insert(id: 4, thread: "a", target: fixture.realTarget, body: "stream_event requestApproval waitingOnApproval turn_id=next turn_id=wrong approvalApproved call_id=other")
        let ambiguous = try adapter.poll()
        XCTAssertFalse(ambiguous.observations.contains { if case .resolved = $0 { return true }; return false })
        XCTAssertEqual(ambiguous.health.reason, .malformedRecord)
        XCTAssertEqual(adapter.lifecycleCheckpoint().unresolved.map(\.requestID.rawID), ["other"])
    }

    func testCatchUpIsBoundedAndResolvedCheckpointDoesNotResurrectAfterRestart() throws {
        try fixture.insert(id: 1, thread: "a", target: fixture.realTarget, body: fixture.requestBody(thread: "a", request: "r", turn: "t"))
        try fixture.insert(id: 2, thread: "a", target: fixture.realTarget, body: fixture.resolutionBody(thread: "a", request: "r", turn: "t", variant: "approvalApproved"))
        try fixture.insert(id: 3, thread: "b", target: fixture.realTarget, body: fixture.requestBody(thread: "b", request: "pending", turn: "turn-b"))
        let store = ApprovalLifecycleCheckpointStore(url: fixture.root.appendingPathComponent("approval-catchup.json"))
        let owner = try ApprovalLifecycleRuntimeOwner(databaseURL: fixture.database, sourceID: fixture.source, schema: .init(acceptedUserVersions: [0]), store: store, retryPolicy: .init(maximumRowsPerPoll: 1))
        let caughtUp = try owner.catchUpToStable(policy: .init(maximumPolls: 8))
        XCTAssertGreaterThan(caughtUp.polls, 2)
        XCTAssertEqual(caughtUp.checkpoint.unresolved.map(\.requestID.rawID), ["pending"])

        let restarted = try ApprovalLifecycleRuntimeOwner(databaseURL: fixture.database, sourceID: fixture.source, schema: .init(acceptedUserVersions: [0]), store: store, retryPolicy: .init(maximumRowsPerPoll: 1))
        let afterRestart = try restarted.catchUpToStable(policy: .init(maximumPolls: 4))
        XCTAssertEqual(afterRestart.checkpoint.unresolved.map(\.requestID.rawID), ["pending"])
    }

    func testUnknownSchemaMalformedAndRotationFailClosedWithoutContent() throws {
        try fixture.insert(id: 1, thread: "a", target: fixture.realTarget, body: "requestApproval waitingOnApproval turn_id=missing-request")
        let reader = fixture.adapter()
        let malformed = try reader.poll()
        XCTAssertEqual(malformed.health.reason, .malformedRecord)
        XCTAssertNotNil(malformed.cursor)
        let repeated = try reader.poll()
        XCTAssertEqual(repeated.health.state, .available)
        XCTAssertFalse(String(reflecting: malformed).contains("missing-request"))
        try fixture.setUserVersion(2)
        XCTAssertEqual(try fixture.adapter().poll().health.reason, .schemaMismatch)
        try fixture.setUserVersion(0)
        let checkpoint = ApprovalLogCursor(fileIdentity: FileIdentity.readOnlyIdentity(of: fixture.database)!, lastLogID: 1)
        try FileManager.default.removeItem(at: fixture.database); try fixture.createDatabase()
        XCTAssertEqual(try fixture.adapter(checkpoint: checkpoint).poll().health.reason, .fileIdentityChanged)
    }

    func testMalformedRowDoesNotBlockLaterInstalledRequestOrResolutionFromStateEngine() throws {
        try fixture.insert(id: 1, thread: "a", target: fixture.realTarget, body: "requestApproval waitingOnApproval turn_id=malformed")
        try fixture.insert(id: 2, thread: "a", target: fixture.realTarget, body: fixture.requestBody(thread: "a", request: "call", turn: "turn"))
        try fixture.insert(id: 3, thread: "a", target: fixture.realTarget, body: fixture.resolutionBody(thread: "a", request: "call", turn: "turn", variant: "approvalApproved"))
        let observations = try fixture.adapter().poll().observations
        XCTAssertEqual(observations.filter { if case .requested = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(observations.filter { if case .resolved = $0 { return true }; return false }.count, 1)
    }

    func testUnpinnedResolutionMarkerAndAmbiguousCorrelationFailClosed() throws {
        try fixture.insert(id: 1, thread: "a", target: fixture.realTarget, body: "stream_event approvalResolved status=approved thread_id=a turn_id=t request_id=r")
        XCTAssertEqual(try fixture.adapter().poll().health.reason, .malformedRecord)

        try fixture.clearLogs()
        try fixture.insert(id: 1, thread: "a", target: fixture.realTarget, body: "stream_event approvalApproved thread_id=a turn_id=t request_id=r request_id=other")
        XCTAssertEqual(try fixture.adapter().poll().health.reason, .malformedRecord)
    }

    func testUnknownTargetIsIgnoredAndResolutionRetainsExactIdentity() throws {
        try fixture.insert(id: 1, thread: "a", target: "codex_core::stream_events_utils_similar", body: fixture.requestBody(thread: "a", request: "r", turn: "t"))
        try fixture.insert(id: 2, thread: "b", target: fixture.realTarget, body: fixture.resolutionBody(thread: "b", request: "r", turn: "t", variant: "approvalApproved"))
        let values = try fixture.adapter().poll().observations
        XCTAssertTrue(values.isEmpty)
    }

    func testReadOnlyAdapterDoesNotMutateDatabase() throws {
        try fixture.insert(id: 1, thread: "a", target: fixture.realTarget, body: fixture.requestBody(thread: "a", request: "r", turn: "t"))
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
    let realTarget = "codex_core::stream_events_utils"
    init() throws { database = root.appendingPathComponent("logs.sqlite"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try createDatabase() }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func createDatabase() throws { var db: OpaquePointer?; guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw POSIXError(.EIO) }; defer { sqlite3_close(db) }; try approvalSQL(db, "PRAGMA user_version = 0"); try approvalSQL(db, "CREATE TABLE logs (id INTEGER PRIMARY KEY, thread_id TEXT NOT NULL, ts REAL NOT NULL, target TEXT NOT NULL, level TEXT NOT NULL, feedback_log_body TEXT NOT NULL)") }
    func adapter(checkpoint: ApprovalLogCursor? = nil) -> ApprovalLocalAdapter { ApprovalLocalAdapter(databaseURL: database, sourceID: source, schema: .init(acceptedUserVersions: [0]), checkpoint: checkpoint, retryPolicy: .init(attempts: 2, busyTimeoutMilliseconds: 1, retryDelayMilliseconds: 1)) }
    func adapter(lifecycleCheckpoint: ApprovalLifecycleCheckpoint) -> ApprovalLocalAdapter { ApprovalLocalAdapter(databaseURL: database, sourceID: source, schema: .init(acceptedUserVersions: [0]), lifecycleCheckpoint: lifecycleCheckpoint, retryPolicy: .init(attempts: 2, busyTimeoutMilliseconds: 1, retryDelayMilliseconds: 1)) }
    // Sanitized structural fixture of the installed logger's bounded wrapper:
    // four ordered turn IDs plus two equal call IDs.  Values are opaque test IDs.
    func requestBody(thread: String, request: String, turn: String) -> String { "stream_event thread_id=\(thread) turn_id=\(turn) turn_id=\(turn) turn_id=\(turn) turn_id=\(turn) requestApproval waitingOnApproval call_id=\(request) call_id=\(request)" }
    func resolutionBody(thread: String, request: String, turn: String, variant: String) -> String { "stream_event thread_id=\(thread) turn_id=\(turn) turn_id=\(turn) turn_id=\(turn) \(variant) call_id=\(request)" }
    func insert(id: Int, thread: String, target: String, body: String) throws { var db: OpaquePointer?; guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw POSIXError(.EIO) }; defer { sqlite3_close(db) }; let sql = "INSERT INTO logs VALUES (\(id), '\(thread)', 1800000000, '\(target)', 'info', '\(body.replacingOccurrences(of: "'", with: "''"))')"; try approvalSQL(db, sql) }
    func setUserVersion(_ value: Int) throws { var db: OpaquePointer?; guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw POSIXError(.EIO) }; defer { sqlite3_close(db) }; try approvalSQL(db, "PRAGMA user_version = \(value)") }
    func clearLogs() throws { var db: OpaquePointer?; guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw POSIXError(.EIO) }; defer { sqlite3_close(db) }; try approvalSQL(db, "DELETE FROM logs") }
}

private func approvalSQL(_ db: OpaquePointer?, _ sql: String) throws { var message: UnsafeMutablePointer<Int8>?; guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else { sqlite3_free(message); throw POSIXError(.EIO) } }
