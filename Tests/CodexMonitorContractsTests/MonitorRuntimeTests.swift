import XCTest
@testable import CodexMonitorContracts

final class MonitorRuntimeTests: XCTestCase {
    private let source = SourceID("desktop-local")!

    func testSnapshotMapsStateAttributionTokenUsageQuotaAndCapabilityContract() async throws {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let thread = id(.thread, "thread-a")
        let turn = id(.turn, "turn-a")

        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, title: "Build monitor", model: "gpt-5", reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: 4))
        await store.ingest(event(thread, turn, .taskStarted, tokens: 12, clock: clock))
        await store.ingest(event(thread, turn, .activity, activity: .tool, item: id(.item, "tool-a"), tokens: 15, clock: clock))
        await store.ingest(account: accountSnapshot(clock: clock, usage: UsagePresence(summaryAvailable: true, totalTokens: 99), primary: RateLimitWindow(usedPercent: 25, windowDurationMinutes: 300), resetCount: 2))

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .working)
        XCTAssertEqual(snapshot.currentThread?.threadID, thread)
        XCTAssertEqual(snapshot.currentSessionThread?.activeTurnID, turn)
        XCTAssertEqual(snapshot.sessionToken, 15)
        XCTAssertEqual(snapshot.usage.availability, .available)
        XCTAssertEqual(snapshot.usage.usage?.totalTokens, 99)
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 25)
        XCTAssertEqual(snapshot.quota.secondaryAvailability, .unavailable)
        XCTAssertEqual(snapshot.resetInformation.count, 2)
        XCTAssertEqual(snapshot.resetInformation.detailsAvailability, .unavailable)
        XCTAssertEqual(snapshot.capabilities[.approvalResolution], MonitorCapabilityAvailability(availability: .unavailable, reason: .externalCodexDesktopCapability))
    }

    func testUnavailableDesktopFailsClosedWithoutRetainingCurrentToken() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let thread = id(.thread, "thread-a")
        let turn = id(.turn, "turn-a")
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.ingest(event(thread, turn, .taskStarted, tokens: 10, clock: clock))
        await store.ingest(DesktopObservation.sourceHealth(DesktopSourceHealth(threadID: thread, state: .unavailable, processEpoch: nil, fileIdentity: nil, reason: .sourceMissing)))

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .disconnected)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .unavailable)
        XCTAssertEqual(snapshot.capabilities[.currentState]?.availability, .unavailable)
        XCTAssertNil(snapshot.sessionToken)
        XCTAssertEqual(snapshot.currentThread?.sessionTokenAvailability, .unavailable)
    }

    func testPauseAndReconciliationProtectAgainstStaleStateThenRecover() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let thread = id(.thread, "thread-a")
        let turn = id(.turn, "turn-a")
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, title: "Resume", model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.ingest(event(thread, turn, .taskStarted, clock: clock))

        await store.setPaused(true)
        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .paused)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .stale)
        XCTAssertEqual(snapshot.capabilities[.currentState]?.availability, .stale)

        await store.setPaused(false)
        await store.installReconciliation([
            RuntimeReconciliationThread(threadID: thread, title: "Resume", model: nil, activeTurnID: turn, turnStartedAt: clock.now(), latestActiveState: .thinking, latestActiveStateAt: clock.now(), approvalHealth: .availableKnownNotWaiting, unresolvedApprovals: [], runtimeSourceAvailable: true, runtimeObservedAt: clock.now(), approvalObservedAt: clock.now())
        ])
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.monitoringPhase, .live)
        XCTAssertEqual(snapshot.currentState, .thinking)
        XCTAssertEqual(snapshot.currentSessionThread?.activeTurnID, turn)
    }

    func testApprovalResolutionIsNotConsumedAndExactCompletionFallbackRemains() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let thread = id(.thread, "thread-a")
        let turn = id(.turn, "turn-a")
        let request = id(.item, "request-a")
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.ingest(event(thread, turn, .taskStarted, clock: clock))
        await store.ingest(ApprovalObservation.requested(ApprovalRequested(threadID: thread, turnID: turn, requestID: request, observedAt: clock.now())))
        await store.ingest(ApprovalObservation.resolved(ApprovalResolved(threadID: thread, turnID: turn, requestID: request, status: .approved, observedAt: clock.now())))

        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .waitingApproval)
        XCTAssertEqual(snapshot.capabilities[.approvalResolution]?.availability, .unavailable)

        await store.ingest(event(thread, turn, .activity, activity: .agentResponse, item: request, clock: clock))
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .thinking)
        XCTAssertEqual(snapshot.waitingApprovalCount, 0)
    }

    func testStaleAccountSnapshotIsWithheldInsteadOfDisplayedAsCurrent() async throws {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock, freshness: MonitorRuntimeFreshnessPolicy(maximumAccountAge: 5))
        await store.ingest(account: accountSnapshot(clock: clock, usage: UsagePresence(totalTokens: 100), primary: RateLimitWindow(usedPercent: 50), resetCount: 1))
        clock.advance(6)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.sourceHealth[.account]?.availability, .stale)
        XCTAssertEqual(snapshot.usage.availability, .stale)
        XCTAssertNil(snapshot.usage.usage)
        XCTAssertEqual(snapshot.quota.primaryAvailability, .stale)
        XCTAssertNil(snapshot.quota.primary)
        XCTAssertEqual(snapshot.resetInformation.countAvailability, .stale)
        XCTAssertNil(snapshot.resetInformation.count)
    }

    func testRepresentativeThreadSwitchesWithoutMixingAttribution() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let first = id(.thread, "thread-a"), firstTurn = id(.turn, "turn-a")
        let second = id(.thread, "thread-b"), secondTurn = id(.turn, "turn-b")
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: first, title: "First", model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: second, title: "Second", model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.ingest(event(first, firstTurn, .taskStarted, clock: clock))
        await store.ingest(event(first, firstTurn, .activity, activity: .tool, item: id(.item, "tool-a"), clock: clock))
        clock.advance(1)
        await store.ingest(event(second, secondTurn, .taskStarted, clock: clock))

        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentThread?.threadID, second)
        XCTAssertEqual(snapshot.currentSessionThread?.activeTurnID, secondTurn)
        XCTAssertEqual(snapshot.currentState, .thinking)

        await store.ingest(event(second, secondTurn, .taskCompletedFailure, clock: clock))
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .failed)
        XCTAssertEqual(snapshot.currentSessionThread?.threadID, second)
        XCTAssertEqual(snapshot.threads.first { $0.threadID == first }?.state, .working)
    }

    func testSnapshotStreamImmediatelyYieldsThenDeliversMutation() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let stream = await store.snapshots()
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial?.currentState, .disconnected)

        let thread = id(.thread, "event-thread")
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        let updated = await iterator.next()
        XCTAssertEqual(updated?.currentState, .idle)
        XCTAssertEqual(updated?.sourceHealth[.desktopLocal]?.availability, .available)
    }

    func testTerminalRetentionPublishesIdleWithoutAnotherExternalMutation() async throws {
        let store = MonitorRuntimeStore(
            engine: RuntimeStateEngine(initialPhase: .live),
            initialPhase: .live
        )
        let thread = id(.thread, "terminal-deadline")
        let turn = id(.turn, "terminal-turn")
        let stream = await store.snapshots()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        _ = await iterator.next()
        let now = Date()
        await store.ingest(.rollout(RolloutRecordEnvelope(threadID: thread, turnID: turn, itemID: nil, kind: .taskStarted, activity: nil, tokenSnapshot: nil, model: nil, reasoningEffort: nil, observedAt: now, fileOffset: 0)))
        _ = await iterator.next()

        // Use an authoritative source time just before the retained deadline:
        // this is a real one-shot scheduler regression without turning the
        // normal unit suite into a twenty-second timer test.
        let completedAt = Date().addingTimeInterval(-4.85)
        await store.ingest(.rollout(RolloutRecordEnvelope(threadID: thread, turnID: turn, itemID: nil, kind: .taskCompletedSuccess, activity: nil, tokenSnapshot: nil, model: nil, reasoningEffort: nil, authoritativeEventAt: completedAt, observedAt: Date(), fileOffset: 1)))
        let completed = await iterator.next()
        XCTAssertEqual(completed?.currentState, .completed)

        try await Task.sleep(for: .seconds(0.5))
        let idle = await iterator.next()
        XCTAssertEqual(idle?.currentState, .idle)
    }

    func testOldUnavailableThreadDoesNotPoisonFreshRepresentativeIdleThread() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let old = id(.thread, "old"), current = id(.thread, "current")
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: old, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.ingest(.sourceHealth(DesktopSourceHealth(threadID: old, state: .unavailable, processEpoch: nil, fileIdentity: nil, reason: .sourceMissing)))
        clock.advance(1)
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: current, title: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentThread?.threadID, current)
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
    }

    private func makeStore(clock: RuntimeSnapshotTestClock, freshness: MonitorRuntimeFreshnessPolicy = .init()) -> MonitorRuntimeStore {
        MonitorRuntimeStore(engine: RuntimeStateEngine(clock: clock, initialPhase: .live), clock: clock, freshnessPolicy: freshness, initialPhase: .live)
    }

    private func id(_ kind: EntityKind, _ raw: String) -> NamespacedID {
        NamespacedID(sourceID: source, entityKind: kind, rawID: raw)!
    }

    private func event(_ thread: NamespacedID, _ turn: NamespacedID, _ kind: RolloutEventKind, activity: RolloutActivityCategory? = nil, item: NamespacedID? = nil, tokens: Int64? = nil, clock: RuntimeSnapshotTestClock) -> DesktopObservation {
        .rollout(RolloutRecordEnvelope(threadID: thread, turnID: turn, itemID: item, kind: kind, activity: activity, tokenSnapshot: tokens.map { TokenSnapshot(totalTokens: $0, lastCallTokens: nil) }, model: nil, reasoningEffort: nil, observedAt: clock.now(), fileOffset: 0))
    }

    private func accountSnapshot(clock: RuntimeSnapshotTestClock, usage: UsagePresence, primary: RateLimitWindow, resetCount: Int) -> AccountSnapshot {
        let now = clock.now()
        let provenance = Provenance(sourceID: SourceID("account")!, sourceKind: .account, adapterID: AdapterID("account")!, adapterVersion: AdapterVersion("v3")!, observationMode: .snapshot, authority: .authoritative, observedAt: now, freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now), capability: .usageResponsePresence, evidence: EvidenceMetadata(evidenceRun: "test", cliVersion: "test", historicalTransportEvidenceLabel: "test", probeOrHarnessAvailability: "test", sanitizerAvailability: "test", sanitizerVersion: "test", confidence: "test", limitations: "test"), origin: .adapter)!
        return AccountSnapshot(provenance: provenance, primaryRateLimit: primary, usage: usage, resetCreditCount: resetCount)!
    }
}

private final class RuntimeSnapshotTestClock: StateEngineClock, MonitorRuntimeClock, @unchecked Sendable {
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { date }
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}
