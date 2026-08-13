import XCTest
@testable import CodexMonitorContracts
@testable import CodexMonitorApp

@MainActor
final class MonitorAppModelTests: XCTestCase {
    private let source = SourceID("ui-runtime-source")!

    func testRuntimeSnapshotDrivesObservableStateAndSuppressesDuplicates() async {
        let clock = AppModelTestClock()
        let engine = RuntimeStateEngine(clock: clock, initialPhase: .live)
        let runtime = MonitorRuntimeStore(engine: engine, clock: clock, initialPhase: .live)
        let thread = id(.thread, "thread"), turn = id(.turn, "turn")
        let model = MonitorAppModel()

        await runtime.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, title: "UI task", model: "gpt-5", reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await runtime.ingest(event(thread, turn, .taskStarted, clock: clock))
        await runtime.ingest(event(thread, turn, .activity, activity: .tool, item: id(.item, "tool"), clock: clock))
        let working = await runtime.snapshot()
        model.apply(working)
        XCTAssertEqual(model.snapshot?.currentState, .working)
        XCTAssertEqual(model.snapshot?.currentSessionThread?.activeTurnID, turn)

        let updates = model.acceptedSnapshotCount
        model.apply(working)
        XCTAssertEqual(model.acceptedSnapshotCount, updates)
        clock.advance(1)
        model.apply(await runtime.snapshot())
        XCTAssertEqual(model.acceptedSnapshotCount, updates)

        await runtime.ingest(event(thread, turn, .taskCompletedFailure, clock: clock))
        model.apply(await runtime.snapshot())
        XCTAssertEqual(model.snapshot?.currentState, .failed)
        XCTAssertEqual(model.snapshot?.capabilities[.approvalResolution]?.availability, .unavailable)
    }

    func testUnavailableAndApprovalObservedSnapshotsRemainVisibleToUI() async {
        let clock = AppModelTestClock()
        let runtime = MonitorRuntimeStore(engine: RuntimeStateEngine(clock: clock, initialPhase: .live), clock: clock, initialPhase: .live)
        let thread = id(.thread, "thread"), turn = id(.turn, "turn"), request = id(.item, "request")
        let model = MonitorAppModel()

        await runtime.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await runtime.ingest(event(thread, turn, .taskStarted, clock: clock))
        await runtime.ingest(.requested(ApprovalRequested(threadID: thread, turnID: turn, requestID: request, observedAt: clock.now())))
        model.apply(await runtime.snapshot())
        XCTAssertEqual(model.snapshot?.currentState, .thinking)
        XCTAssertEqual(model.snapshot?.approvalRequestObserved, true)
        XCTAssertEqual(model.snapshot?.capabilities[.waitingApproval]?.availability, .available)

        await runtime.ingest(.sourceHealth(DesktopSourceHealth(threadID: thread, state: .unavailable, processEpoch: nil, fileIdentity: nil, reason: .sourceMissing)))
        model.apply(await runtime.snapshot())
        XCTAssertEqual(model.snapshot?.currentState, .disconnected)
        XCTAssertEqual(model.snapshot?.sourceHealth[.desktopLocal]?.availability, .unavailable)
    }

    func testFreshRepresentativeIdleHasTheExactSteadyGreenPresentation() async {
        let clock = AppModelTestClock()
        let runtime = MonitorRuntimeStore(engine: RuntimeStateEngine(clock: clock, initialPhase: .live), clock: clock, initialPhase: .live)
        let old = id(.thread, "old"), current = id(.thread, "current")
        await runtime.registerDesktopThread(DesktopThreadSnapshot(threadID: old, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await runtime.ingest(.sourceHealth(DesktopSourceHealth(threadID: old, state: .unavailable, processEpoch: nil, fileIdentity: nil, reason: .sourceMissing)))
        clock.advance(1)
        await runtime.registerDesktopThread(DesktopThreadSnapshot(threadID: current, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))

        let snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
        XCTAssertEqual(VisualStatePresentation.forSnapshot(snapshot), .init(dots: [.green, .green, .green], orbTone: .green, breathes: false, stateTextKey: "state.idle"))
    }

    func testHeartbeatTimestampDoesNotChangePresentation() async {
        let clock = AppModelTestClock()
        let runtime = MonitorRuntimeStore(engine: RuntimeStateEngine(clock: clock, initialPhase: .live), clock: clock, initialPhase: .live)
        let model = MonitorAppModel()
        let thread = id(.thread, "heartbeat")
        await runtime.applyDesktopCycle(
            registrations: [DesktopThreadSnapshot(threadID: thread, title: "Idle", model: nil, reasoningEffort: nil, updatedAtMilliseconds: 1_700_000_000, tokensUsed: nil)],
            observations: [],
            health: DesktopCycleHealth(processRunning: true, stateDBReadable: true)
        )
        model.apply(await runtime.snapshot())
        let baseline = model.acceptedSnapshotCount

        for _ in 0..<100 {
            clock.advance(2)
            await runtime.applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: true, stateDBReadable: true))
            model.apply(await runtime.snapshot())
        }
        XCTAssertEqual(model.acceptedSnapshotCount, baseline)

        clock.advance(2)
        await runtime.applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: true, stateDBReadable: false))
        model.apply(await runtime.snapshot())
        XCTAssertEqual(model.acceptedSnapshotCount, baseline + 1)
        XCTAssertEqual(model.snapshot?.sourceHealth[.desktopLocal]?.availability, .unavailable)
    }

    /// Exercises the same production driver policy used by the two-second
    /// source loop. An exact transient WAL disappearance after a long idle
    /// interval is not evidence that a running Codex Desktop disappeared.
    func testProductionIdleWatchdogDoesNotInvalidateRunningCodex() async {
        let clock = AppModelTestClock()
        let runtime = MonitorRuntimeStore(engine: RuntimeStateEngine(clock: clock, initialPhase: .live), clock: clock, initialPhase: .live)
        await runtime.applyDesktopCycle(
            registrations: [],
            observations: [],
            health: DesktopCycleHealth(processRunning: true, stateDBReadable: true)
        )

        clock.advance(1_801)
        let disposition = DesktopPrimarySourceReadDisposition(
            error: StateDBError.transientWALUnavailable,
            hasSuccessfulStateDBRead: true
        )
        XCTAssertEqual(disposition, .retainLastKnownHealthy)

        // This is the exact health write the production loop performs after a
        // transient read failure. There is no parallel test-only reducer.
        await runtime.applyDesktopCycle(
            registrations: [],
            observations: [],
            health: DesktopCycleHealth(
                processRunning: true,
                stateDBReadable: disposition == .retainLastKnownHealthy
            )
        )
        let snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
    }

    func testFatalStateDatabaseErrorsRemainUnavailable() {
        for error in [StateDBError.readOnlyOpenFailed, .schemaMismatch, .queryFailed] {
            XCTAssertEqual(
                DesktopPrimarySourceReadDisposition(error: error, hasSuccessfulStateDBRead: true),
                .fatal
            )
        }
        XCTAssertEqual(
            DesktopPrimarySourceReadDisposition(error: StateDBError.transientWALUnavailable, hasSuccessfulStateDBRead: false),
            .fatal
        )
    }

    private func id(_ kind: EntityKind, _ raw: String) -> NamespacedID {
        NamespacedID(sourceID: source, entityKind: kind, rawID: raw)!
    }

    private func event(_ thread: NamespacedID, _ turn: NamespacedID, _ kind: RolloutEventKind, activity: RolloutActivityCategory? = nil, item: NamespacedID? = nil, clock: AppModelTestClock) -> DesktopObservation {
        .rollout(RolloutRecordEnvelope(threadID: thread, turnID: turn, itemID: item, kind: kind, activity: activity, tokenSnapshot: nil, model: nil, reasoningEffort: nil, observedAt: clock.now(), fileOffset: 0))
    }
}

private final class AppModelTestClock: StateEngineClock, MonitorRuntimeClock, @unchecked Sendable {
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { value }
    func advance(_ seconds: TimeInterval) { value = value.addingTimeInterval(seconds) }
}
