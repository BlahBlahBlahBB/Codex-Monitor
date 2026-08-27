import XCTest
@testable import CodexMonitorContracts
@testable import CodexMonitorApp

final class MonitorRuntimeTests: XCTestCase {
    private let source = SourceID("desktop-local")!

    func testSnapshotMapsStateAttributionTokenUsageQuotaAndCapabilityContract() async throws {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let thread = id(.thread, "thread-a")
        let turn = id(.turn, "turn-a")

        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: "Build monitor", model: "gpt-5", reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: 4))
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
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
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
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: "Resume", model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.ingest(event(thread, turn, .taskStarted, clock: clock))

        await store.setPaused(true)
        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .paused)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .stale)
        XCTAssertEqual(snapshot.capabilities[.currentState]?.availability, .stale)

        await store.setPaused(false)
        await store.installReconciliation([
            RuntimeReconciliationThread(threadID: thread, conversationName: "Resume", model: nil, activeTurnID: turn, turnStartedAt: clock.now(), latestActiveState: .thinking, latestActiveStateAt: clock.now(), approvalHealth: .availableKnownNotWaiting, unresolvedApprovals: [], runtimeSourceAvailable: true, runtimeObservedAt: clock.now(), approvalObservedAt: clock.now())
        ])
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.monitoringPhase, .live)
        XCTAssertEqual(snapshot.currentState, .thinking)
        XCTAssertEqual(snapshot.currentSessionThread?.activeTurnID, turn)
    }

    func testApprovalRequestCreatesSecondaryObservedEvent() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let thread = id(.thread, "thread-a")
        let turn = id(.turn, "turn-a")
        let request = id(.item, "request-a")
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.ingest(event(thread, turn, .taskStarted, clock: clock))
        await store.ingest(ApprovalObservation.requested(ApprovalRequested(threadID: thread, turnID: turn, requestID: request, observedAt: clock.now())))
        await store.ingest(ApprovalObservation.resolved(ApprovalResolved(threadID: thread, turnID: turn, requestID: request, status: .approved, observedAt: clock.now())))

        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .thinking)
        XCTAssertTrue(snapshot.approvalRequestObserved)
        XCTAssertEqual(snapshot.capabilities[.approvalResolution]?.availability, .unavailable)

        await store.ingest(event(thread, turn, .activity, activity: .agentResponse, item: request, clock: clock))
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .thinking)
        XCTAssertEqual(snapshot.waitingApprovalCount, 0)
        XCTAssertTrue(snapshot.approvalRequestObserved)
    }

    func testOrdinaryTaskHasNoApprovalObservedEvent() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let thread = id(.thread, "ordinary-thread")
        let turn = id(.turn, "ordinary-turn")
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.ingest(event(thread, turn, .taskStarted, clock: clock))
        await store.ingest(event(thread, turn, .activity, activity: .tool, item: id(.item, "ordinary-tool"), clock: clock))

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .working)
        XCTAssertFalse(snapshot.approvalRequestObserved)
    }

    func testStaleAccountSnapshotRemainsLastKnownGoodWhileFreshnessIsTracked() async throws {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock, freshness: MonitorRuntimeFreshnessPolicy(maximumAccountAge: 5))
        await store.ingest(account: accountSnapshot(clock: clock, usage: UsagePresence(totalTokens: 100), primary: RateLimitWindow(usedPercent: 50), resetCount: 1))
        clock.advance(6)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.sourceHealth[.account]?.availability, .available)
        XCTAssertEqual(snapshot.sourceHealth[.account]?.freshness.state, .stale)
        XCTAssertEqual(snapshot.usage.availability, .available)
        XCTAssertEqual(snapshot.usage.usage?.totalTokens, 100)
        XCTAssertEqual(snapshot.quota.primaryAvailability, .available)
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 50)
        XCTAssertEqual(snapshot.resetInformation.countAvailability, .available)
        XCTAssertEqual(snapshot.resetInformation.count, 1)
    }

    func testQuotaLastKnownGoodSurvivesTransientRefreshFailure() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        await store.ingest(account: accountSnapshot(clock: clock, usage: UsagePresence(totalTokens: 100), primary: RateLimitWindow(usedPercent: 25), resetCount: 1))
        let before = await store.snapshot()

        clock.advance(60)
        await store.markAccountRefreshDegraded()
        let after = await store.snapshot()

        XCTAssertEqual(after.account.availability, .available)
        XCTAssertEqual(after.account.plan, before.account.plan)
        XCTAssertEqual(after.usage.usage?.totalTokens, 100)
        XCTAssertEqual(after.quota.primary?.usedPercent, 25)
        XCTAssertEqual(after.resetInformation.count, 1)
        XCTAssertEqual(after.sourceHealth[.account]?.availability, .available)
        XCTAssertEqual(after.sourceHealth[.account]?.freshness.state, .stale)
    }

    func testRepresentativeThreadSwitchesWithoutMixingAttribution() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let first = id(.thread, "thread-a"), firstTurn = id(.turn, "turn-a")
        let second = id(.thread, "thread-b"), secondTurn = id(.turn, "turn-b")
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: first, conversationName: "First", model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: second, conversationName: "Second", model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
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
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        let updated = await iterator.next()
        XCTAssertEqual(updated?.currentState, .idle)
        XCTAssertEqual(updated?.sourceHealth[.desktopLocal]?.availability, .available)
    }

    func testDesktopCyclePublishesOneSemanticSnapshot() async throws {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let model = await MainActor.run { MonitorAppModel() }
        await MainActor.run { model.startObserving(store) }
        try await Task.sleep(for: .milliseconds(25))
        let baseline = await MainActor.run { model.acceptedSnapshotCount }

        let first = id(.thread, "batch-a")
        let second = id(.thread, "batch-b")
        let firstTurn = id(.turn, "batch-turn-a")
        let secondTurn = id(.turn, "batch-turn-b")
        let firstStart = event(first, firstTurn, .taskStarted, clock: clock)
        clock.advance(1)
        let secondStart = event(second, secondTurn, .taskStarted, clock: clock)
        await store.applyDesktopCycle(
            registrations: [
                DesktopThreadSnapshot(threadID: first, conversationName: "First", model: nil, reasoningEffort: nil, updatedAtMilliseconds: 1_700_000_000, tokensUsed: 10),
                DesktopThreadSnapshot(threadID: second, conversationName: "Second", model: nil, reasoningEffort: nil, updatedAtMilliseconds: 1_700_000_100, tokensUsed: 20)
            ],
            observations: [
                firstStart,
                secondStart
            ]
        )
        try await Task.sleep(for: .milliseconds(25))

        let accepted = await MainActor.run { model.acceptedSnapshotCount }
        let snapshot = await store.snapshot()
        XCTAssertEqual(accepted, baseline + 1)
        XCTAssertEqual(snapshot.currentThread?.threadID, second)
        await MainActor.run { model.stopObserving() }
    }

    func testApprovalPollBatchPublishesOneCoherentSnapshot() async throws {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let thread = id(.thread, "approval-batch")
        let turn = id(.turn, "approval-turn")
        let request = id(.item, "approval-request")
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: "Approval", model: nil, reasoningEffort: nil, updatedAtMilliseconds: 1_700_000_000, tokensUsed: nil))
        await store.ingest(event(thread, turn, .taskStarted, clock: clock))

        let model = await MainActor.run { MonitorAppModel() }
        await MainActor.run { model.startObserving(store) }
        try await Task.sleep(for: .milliseconds(25))
        let baseline = await MainActor.run { model.acceptedSnapshotCount }
        let health = ApprovalSourceHealth(state: .available, observedAt: clock.now())
        await store.ingestApprovalPoll(ApprovalPollResult(
            observations: [
                .requested(ApprovalRequested(threadID: thread, turnID: turn, requestID: request, observedAt: clock.now())),
                .sourceUnavailable(ApprovalSourceHealth(state: .unavailable, observedAt: clock.now(), reason: .sourceMissing))
            ],
            cursor: nil,
            health: health
        ))
        try await Task.sleep(for: .milliseconds(25))

        let accepted = await MainActor.run { model.acceptedSnapshotCount }
        let snapshot = await store.snapshot()
        XCTAssertEqual(accepted, baseline + 1)
        XCTAssertEqual(snapshot.currentState, .thinking)
        XCTAssertTrue(snapshot.approvalRequestObserved)
        XCTAssertEqual(snapshot.capabilities[.approvalResolution]?.availability, .unavailable)
        await MainActor.run { model.stopObserving() }
    }

    func testAccountHeartbeatDoesNotChangePresentation() async throws {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let model = await MainActor.run { MonitorAppModel() }
        let first = accountSnapshot(clock: clock, usage: UsagePresence(totalTokens: 100), primary: RateLimitWindow(usedPercent: 50), resetCount: 1)
        await store.ingest(account: first)
        let initial = await store.snapshot()
        await MainActor.run { model.apply(initial) }
        let baseline = await MainActor.run { model.acceptedSnapshotCount }

        for _ in 0..<100 {
            clock.advance(60)
            await store.ingest(account: accountSnapshot(clock: clock, usage: UsagePresence(totalTokens: 100), primary: RateLimitWindow(usedPercent: 50), resetCount: 1))
            let heartbeat = await store.snapshot()
            await MainActor.run { model.apply(heartbeat) }
        }
        let accepted = await MainActor.run { model.acceptedSnapshotCount }
        XCTAssertEqual(accepted, baseline)
    }

    func testIdleCodexProcessRunningRemainsAvailable() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        await store.applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: true, stateDBReadable: true))
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
    }

    func testIdleThirtyMinutesAndEightHoursDoNotBecomeUnavailable() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        await store.applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: true, stateDBReadable: true))

        let checkpoints: [TimeInterval] = [1_800, 7_200, 28_800]
        var previousCheckpoint: TimeInterval = 0
        for checkpoint in checkpoints {
            clock.advance(checkpoint - previousCheckpoint)
            previousCheckpoint = checkpoint
            let snapshot = await store.snapshot()
            XCTAssertEqual(snapshot.currentState, .idle)
            XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
            XCTAssertNotEqual(snapshot.sourceHealth[.desktopLocal]?.reason, .codexProcessNotRunning)
        }
    }

    func testIdleThirtyMinutesRemainsAvailable() async {
        let snapshot = await idleSnapshot(after: 1_800)
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
    }

    func testIdleTwoHoursRemainsAvailable() async {
        let snapshot = await idleSnapshot(after: 7_200)
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
    }

    func testIdleEightHoursRemainsAvailable() async {
        let snapshot = await idleSnapshot(after: 28_800)
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
    }

    func testIdleTwentyFourHoursRemainsAvailable() async {
        let snapshot = await idleSnapshot(after: 86_400)
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
    }

    func testDesktopAvailabilityReducerHasNoAgeInput() {
        XCTAssertEqual(
            DesktopAvailabilityDecision(processRunning: true, stateDBReadable: true, monitorPaused: false, activeTurnPresent: false, fatalSourceError: false),
            .availableIdle
        )
        XCTAssertEqual(
            DesktopAvailabilityDecision(processRunning: true, stateDBReadable: true, monitorPaused: false, activeTurnPresent: true, fatalSourceError: false),
            .availableActive
        )
        XCTAssertEqual(
            DesktopAvailabilityDecision(processRunning: true, stateDBReadable: false, monitorPaused: false, activeTurnPresent: false, fatalSourceError: false),
            .sourceFailure
        )
        XCTAssertEqual(
            DesktopAvailabilityDecision(processRunning: false, stateDBReadable: false, monitorPaused: false, activeTurnPresent: false, fatalSourceError: false),
            .disconnected
        )
    }

    func testHistoricalThreadFailureDoesNotPoisonDesktopLane() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let old = id(.thread, "archived"), current = id(.thread, "current")
        await store.applyDesktopCycle(
            registrations: [
                DesktopThreadSnapshot(threadID: old, conversationName: "Old", model: nil, reasoningEffort: nil, updatedAtMilliseconds: 1_700_000_000, tokensUsed: 10),
                DesktopThreadSnapshot(threadID: current, conversationName: "Current", model: nil, reasoningEffort: nil, updatedAtMilliseconds: 1_700_000_100, tokensUsed: 20)
            ],
            observations: [],
            health: DesktopCycleHealth(processRunning: true, stateDBReadable: true)
        )
        await store.applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: true, stateDBReadable: true, failedThreadIDs: [old]))
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
        XCTAssertEqual(snapshot.currentThread?.threadID, current)
        XCTAssertFalse(snapshot.threads.contains { $0.threadID == old })
    }

    func testArchivedIdleThreadDoesNotMeanCodexUnavailable() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let archived = id(.thread, "archived")
        await store.applyDesktopCycle(registrations: [DesktopThreadSnapshot(threadID: archived, conversationName: "Old", model: nil, reasoningEffort: nil, updatedAtMilliseconds: 1_700_000_000, tokensUsed: nil)], observations: [], health: DesktopCycleHealth(processRunning: true, stateDBReadable: true))
        await store.applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: true, stateDBReadable: true, removedThreadIDs: [archived]))
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
    }

    func testCodexProcessQuitIsDisconnected() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        await store.applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: false, stateDBReadable: false))
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .disconnected)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.reason, .codexProcessNotRunning)
    }

    func testCodexProcessRelaunchRestoresIdle() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        await store.applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: false, stateDBReadable: false))
        clock.advance(1)
        await store.applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: true, stateDBReadable: true))
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
    }

    func testRestartHydrationDoesNotRestoreHistoricalActiveStateWithoutFreshEvidence() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let thread = id(.thread, "freshness-thread")
        let turn = id(.turn, "historical-turn")
        let hydrated = RolloutCheckpointHydration(activeTurnID: turn, turnStartedAt: clock.now(), activeItemID: nil, activeItemCategory: nil, latestActiveState: .thinking, latestActiveStateAt: clock.now(), terminal: nil, authoritativeTokenTotal: 10)
        let rebuilt = LocalRuntimeReconciliationOwner.thread(snapshot: DesktopThreadSnapshot(threadID: thread, conversationName: "Fresh title", model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil), hydration: hydrated, approval: ApprovalLifecycleCheckpoint(cursor: nil, unresolved: []), approvalHealth: .availableKnownNotWaiting, runtimeSourceAvailable: true, observedAt: clock.now(), activityAdmission: .requireFreshLiveEvidence)

        await store.beginReconciliation()
        await store.installReconciliation([rebuilt], desktopHealth: DesktopCycleHealth(processRunning: true, stateDBReadable: true))
        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertNil(snapshot.currentThread?.activeTurnID)

        await store.ingest(event(thread, turn, .taskStarted, clock: clock))
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .thinking)
    }

    func testUnfreshMetadataCannotSupplyConversationPresentationTitle() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let thread = id(.thread, "title-safety")
        let turn = id(.turn, "title-turn")
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: "Authoritative title", model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.ingest(event(thread, turn, .taskStarted, clock: clock))
        await store.clearDesktopConversationNames()
        let snapshot = await store.snapshot()
        XCTAssertNil(snapshot.currentThread?.conversationName)
        XCTAssertEqual(MonitorDisplayValue.resolvedConversationDisplayTitle(snapshot), L10n.tr("activity.currentTask"))
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

        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
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
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: old, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await store.ingest(.sourceHealth(DesktopSourceHealth(threadID: old, state: .unavailable, processEpoch: nil, fileIdentity: nil, reason: .sourceMissing)))
        clock.advance(1)
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: current, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentThread?.threadID, current)
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
    }

    func testHistoricalThreadFailureCannotChangeGlobalAvailability() async {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        let current = id(.thread, "current")
        let historical = (0..<5).map { id(.thread, "historical-\($0)") }
        await store.applyDesktopCycle(
            registrations: historical.map { DesktopThreadSnapshot(threadID: $0, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: 1_700_000_000, tokensUsed: nil) } + [DesktopThreadSnapshot(threadID: current, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: 1_700_000_100, tokensUsed: nil)],
            observations: [],
            health: DesktopCycleHealth(processRunning: true, stateDBReadable: true)
        )
        await store.applyDesktopCycle(
            registrations: [],
            observations: [],
            health: DesktopCycleHealth(processRunning: true, stateDBReadable: true, failedThreadIDs: historical, removedThreadIDs: historical)
        )
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentState, .idle)
        XCTAssertEqual(snapshot.sourceHealth[.desktopLocal]?.availability, .available)
    }

    private func makeStore(clock: RuntimeSnapshotTestClock, freshness: MonitorRuntimeFreshnessPolicy = .init()) -> MonitorRuntimeStore {
        MonitorRuntimeStore(engine: RuntimeStateEngine(clock: clock, initialPhase: .live), clock: clock, freshnessPolicy: freshness, initialPhase: .live)
    }

    private func idleSnapshot(after seconds: TimeInterval) async -> MonitorRuntimeSnapshot {
        let clock = RuntimeSnapshotTestClock()
        let store = makeStore(clock: clock)
        await store.applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: true, stateDBReadable: true))
        clock.advance(seconds)
        return await store.snapshot()
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
