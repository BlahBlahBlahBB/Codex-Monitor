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

    func testUnavailableAndWaitingApprovalSnapshotsRemainVisibleToUI() async {
        let clock = AppModelTestClock()
        let runtime = MonitorRuntimeStore(engine: RuntimeStateEngine(clock: clock, initialPhase: .live), clock: clock, initialPhase: .live)
        let thread = id(.thread, "thread"), turn = id(.turn, "turn"), request = id(.item, "request")
        let model = MonitorAppModel()

        await runtime.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await runtime.ingest(event(thread, turn, .taskStarted, clock: clock))
        await runtime.ingest(.requested(ApprovalRequested(threadID: thread, turnID: turn, requestID: request, observedAt: clock.now())))
        model.apply(await runtime.snapshot())
        XCTAssertEqual(model.snapshot?.currentState, .waitingApproval)
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
