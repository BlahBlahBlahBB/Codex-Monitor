import XCTest
@testable import CodexMonitorContracts

final class HookApprovalContractsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPermissionRequestEntersWaitingApprovalAndCountsTheWaitingThread() {
        let fixture = activeEngine()
        fixture.engine.ingest(.permissionRequest(event(1, owner: fixture.owner)))

        XCTAssertEqual(snapshot(fixture).state, .waitingApproval)
        XCTAssertEqual(fixture.engine.snapshot().waitingApprovalCount, 1)
        XCTAssertEqual(snapshot(fixture).approvalHealth, .availableWaiting)
    }

    func testSolePendingSameTurnPostToolUseResolvesWithoutMakingATerminal() {
        let fixture = activeEngine()
        fixture.engine.ingest(.permissionRequest(event(1, owner: fixture.owner)))
        fixture.engine.ingest(.postToolUse(event(2, owner: fixture.owner)))

        XCTAssertEqual(snapshot(fixture).state, .thinking)
        XCTAssertEqual(fixture.engine.snapshot().waitingApprovalCount, 0)
        XCTAssertEqual(snapshot(fixture).activeTurnID, fixture.turnID)
    }

    func testUnrelatedTurnPostToolUseNeverResolvesAnotherTurn() {
        let fixture = activeEngine()
        fixture.engine.ingest(.permissionRequest(event(1, owner: fixture.owner)))
        fixture.engine.ingest(.postToolUse(event(2, owner: alternateOwner())))

        XCTAssertEqual(snapshot(fixture).state, .waitingApproval)
        XCTAssertEqual(fixture.engine.snapshot().waitingApprovalCount, 1)
    }

    func testMultipleUnresolvedSameTurnApprovalsRemainWaitingAfterPostToolUse() {
        let fixture = activeEngine()
        fixture.engine.ingest(.permissionRequest(event(1, owner: fixture.owner)))
        fixture.engine.ingest(.permissionRequest(event(2, owner: fixture.owner)))
        fixture.engine.ingest(.postToolUse(event(3, owner: fixture.owner)))

        XCTAssertEqual(snapshot(fixture).state, .waitingApproval)
        XCTAssertEqual(fixture.engine.snapshot().waitingApprovalCount, 1)
    }

    func testExactTurnStopClearsPendingWithoutManufacturingCompletion() {
        let fixture = activeEngine()
        fixture.engine.ingest(.permissionRequest(event(1, owner: fixture.owner)))
        fixture.engine.ingest(.stop(event(2, owner: fixture.owner)))

        XCTAssertEqual(snapshot(fixture).state, .thinking)
        XCTAssertNotEqual(snapshot(fixture).state, .completed)
        XCTAssertEqual(fixture.engine.snapshot().waitingApprovalCount, 0)
    }

    func testAuthoritativeRolloutTerminalWinsAndClearsPendingApproval() {
        let fixture = activeEngine()
        fixture.engine.ingest(.permissionRequest(event(1, owner: fixture.owner)))
        fixture.engine.ingest(RolloutRecordEnvelope(threadID: fixture.threadID, turnID: fixture.turnID, itemID: nil, kind: .taskCompletedSuccess, activity: nil, tokenSnapshot: nil, model: nil, reasoningEffort: nil, observedAt: now, fileOffset: 1))

        XCTAssertEqual(snapshot(fixture).state, .completed)
        XCTAssertNil(snapshot(fixture).activeTurnID)
        XCTAssertEqual(fixture.engine.snapshot().waitingApprovalCount, 0)
    }

    func testJournalReplayIsIdempotentAndPreservesOpaquePendingEvidence() throws {
        let owner = owner()
        let record = try XCTUnwrap(HookApprovalJournalRecord(journalEventID: id(1), kind: .permissionRequest, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: 1_800_000_000_000))
        let data = try JSONEncoder().encode(record)
        let reader = HookApprovalJournalReader(observedAt: now)

        XCTAssertEqual(reader.ingest([data]).events.count, 1)
        let replay = reader.ingest([data])
        XCTAssertTrue(replay.events.isEmpty)
        XCTAssertEqual(replay.health.state, .available)
        XCTAssertEqual(replay.checkpoint.unresolved.map(\.journalEventID), [id(1)])
    }

    func testMalformedOrRawLookingJournalRecordCreatesNoWaitingEvidence() {
        let reader = HookApprovalJournalReader(observedAt: now)
        let data = Data("{\"schema\":1,\"journalEventID\":1,\"kind\":\"permissionRequest\",\"sourceID\":\"hmac-sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"prompt\":\"do not admit this\"}".utf8)
        let result = reader.ingest([data])

        XCTAssertTrue(result.events.isEmpty)
        XCTAssertEqual(result.health.state, .unavailable)
        XCTAssertEqual(result.health.reason, .malformedRecord)
        XCTAssertNil(result.checkpoint.lastJournalEventID)
    }

    func testStrictRawAllowListRejectsEveryUnexpectedFieldOnAnOtherwiseValidRecord() throws {
        let owner = owner()
        let record = try XCTUnwrap(HookApprovalJournalRecord(journalEventID: id(1), kind: .permissionRequest, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: 1_800_000_000_000))
        let encoded = try JSONEncoder().encode(record)
        let validReader = HookApprovalJournalReader(observedAt: now)
        XCTAssertEqual(validReader.ingest([encoded]).events.count, 1)

        for field in ["prompt", "command", "tool_input", "tool_response", "assistant_text", "arbitrary_unknown_field"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            object[field] = "must not cross the Monitor boundary"
            let data = try JSONSerialization.data(withJSONObject: object)
            let result = HookApprovalJournalReader(observedAt: now).ingest([data])

            XCTAssertTrue(result.events.isEmpty, field)
            XCTAssertEqual(result.health.state, .unavailable, field)
            XCTAssertEqual(result.health.reason, .malformedRecord, field)
            XCTAssertNil(result.checkpoint.lastJournalEventID, field)
        }
    }

    func testRejectedUnknownFieldCannotCreateWaitingOrKnownNotWaiting() throws {
        let fixture = activeEngine()
        let record = try XCTUnwrap(HookApprovalJournalRecord(journalEventID: id(1), kind: .permissionRequest, sourceID: fixture.owner.sourceID, sessionID: fixture.owner.sessionID, turnID: fixture.owner.turnID, observedAtMilliseconds: 1_800_000_000_000))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object["prompt"] = "must not admit"
        let result = HookApprovalJournalReader(observedAt: now).ingest([try JSONSerialization.data(withJSONObject: object)])
        for event in result.events { fixture.engine.ingest(event) }
        fixture.engine.ingest(.sourceHealth(result.health))

        XCTAssertEqual(snapshot(fixture).state, .thinking)
        XCTAssertEqual(fixture.engine.snapshot().waitingApprovalCount, 0)
        XCTAssertEqual(snapshot(fixture).approvalHealth, .unknown)
        XCTAssertNotEqual(snapshot(fixture).approvalHealth, .availableKnownNotWaiting)
    }

    func testUnknownOrUnavailableHookHealthNeverBecomesKnownNotWaiting() {
        let fixture = activeEngine()
        XCTAssertEqual(snapshot(fixture).approvalHealth, .unknown)

        fixture.engine.ingest(.sourceHealth(HookApprovalSourceHealth(sourceID: fixture.owner.sourceID, state: .unavailable, observedAt: now)))
        XCTAssertEqual(snapshot(fixture).approvalHealth, .unavailable)
        XCTAssertNotEqual(snapshot(fixture).approvalHealth, .availableKnownNotWaiting)
    }

    func testSequentialSameTurnPatternResolvesFirstThenStopsSecond() {
        let fixture = activeEngine()
        fixture.engine.ingest(.permissionRequest(event(1, owner: fixture.owner)))
        fixture.engine.ingest(.postToolUse(event(2, owner: fixture.owner)))
        fixture.engine.ingest(.permissionRequest(event(3, owner: fixture.owner)))
        XCTAssertEqual(snapshot(fixture).state, .waitingApproval)
        fixture.engine.ingest(.stop(event(4, owner: fixture.owner)))

        XCTAssertEqual(snapshot(fixture).state, .thinking)
        XCTAssertEqual(fixture.engine.snapshot().waitingApprovalCount, 0)
    }

    func testJournalReaderConservativelyRetainsTwoPendingApprovalsOnPostToolUse() throws {
        let owner = owner()
        let reader = HookApprovalJournalReader(observedAt: now)
        let records = [
            try XCTUnwrap(HookApprovalJournalRecord(journalEventID: id(1), kind: .permissionRequest, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: 1)),
            try XCTUnwrap(HookApprovalJournalRecord(journalEventID: id(2), kind: .permissionRequest, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: 2)),
            try XCTUnwrap(HookApprovalJournalRecord(journalEventID: id(3), kind: .postToolUse, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: 3))
        ]

        let result = reader.ingest(try records.map(JSONEncoder().encode))
        XCTAssertEqual(result.checkpoint.unresolved.map(\.journalEventID), [id(1), id(2)])
    }

    func testPoisonRecordReturnsAcceptedPrefixWithoutAdvancingPastPoison() throws {
        let owner = owner()
        let reader = HookApprovalJournalReader(observedAt: now)
        let a = try JSONEncoder().encode(try XCTUnwrap(HookApprovalJournalRecord(journalEventID: id(1), kind: .permissionRequest, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: 1)))
        let poison = Data("{\"schema\":1,\"journalEventID\":2,\"kind\":\"permissionRequest\",\"sourceID\":\"\(owner.sourceID.value)\",\"sessionID\":\"\(owner.sessionID.value)\",\"turnID\":\"\(owner.turnID.value)\",\"observedAtMilliseconds\":2,\"prompt\":\"reject\"}".utf8)
        let c = try JSONEncoder().encode(try XCTUnwrap(HookApprovalJournalRecord(journalEventID: id(3), kind: .stop, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: 3)))

        let first = reader.ingest([a, poison, c])
        XCTAssertEqual(first.events.count, 1)
        XCTAssertEqual(first.checkpoint.lastJournalEventID, id(1))
        XCTAssertEqual(first.health.state, .unavailable)
        XCTAssertEqual(first.checkpoint.unresolved.map(\.journalEventID), [id(1)])

        let second = reader.ingest([a, poison, c])
        XCTAssertTrue(second.events.isEmpty)
        XCTAssertEqual(second.checkpoint.lastJournalEventID, id(1))
        XCTAssertEqual(second.checkpoint.unresolved.map(\.journalEventID), [id(1)])
        XCTAssertEqual(second.health.state, .unavailable)
    }

    func testSharedDeriverRejectsStaleTurnDuringFreshReconciliation() throws {
        let deriver = try XCTUnwrap(KeyedHookApprovalIdentityDeriver(keyMaterial: Data("test-key".utf8)))
        let source = SourceID("identity-fixture")!
        let thread = NamespacedID(sourceID: source, entityKind: .thread, rawID: "thread")!
        let t2 = NamespacedID(sourceID: source, entityKind: .turn, rawID: "t2")!
        let oldOwner = try XCTUnwrap(deriver.owner(sourceRawID: source.rawValue, sessionRawID: "session", turnRawID: "t1"))
        let currentOwner = try XCTUnwrap(deriver.owner(sourceRawID: source.rawValue, sessionRawID: "session", turnRawID: "t2"))
        XCTAssertNotEqual(oldOwner, currentOwner)
        let checkpoint = ApprovalLifecycleCheckpoint(cursor: nil, unresolved: [], hookJournal: HookApprovalJournalCheckpoint(sourceID: oldOwner.sourceID, lastJournalEventID: id(1), unresolved: [HookApprovalPendingEvidence(journalEventID: id(1), owner: oldOwner, observedAt: now)], sourceHealth: .available))
        let snapshot = DesktopThreadSnapshot(threadID: thread, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil)
        let hydration = RolloutCheckpointHydration(activeTurnID: t2, turnStartedAt: now, activeItemID: nil, activeItemCategory: nil, latestActiveState: .thinking, latestActiveStateAt: now, terminal: nil, authoritativeTokenTotal: nil, sessionID: "session")
        let derived = LocalRuntimeReconciliationOwner.derivedHookOwner(snapshot: snapshot, hydration: hydration, resolver: deriver)
        XCTAssertEqual(derived, currentOwner)
        let rebuilt = LocalRuntimeReconciliationOwner.thread(snapshot: snapshot, hydration: hydration, approval: checkpoint, approvalHealth: .availableKnownNotWaiting, runtimeSourceAvailable: true, observedAt: now, activityAdmission: .requireFreshLiveEvidence, hookOwner: derived, hookSourceHealth: .available)
        XCTAssertNil(rebuilt.activeTurnID)
        XCTAssertTrue(rebuilt.unresolvedHookApprovals.isEmpty)
    }

    func testDurableHookPendingRestoresAcrossFreshProcessBoundary() {
        let fixture = reconciliationFixture(health: .available, pending: true)
        let rebuilt = LocalRuntimeReconciliationOwner.thread(snapshot: fixture.snapshot, hydration: fixture.hydration, approval: fixture.checkpoint, approvalHealth: .availableKnownNotWaiting, runtimeSourceAvailable: true, observedAt: now, activityAdmission: .requireFreshLiveEvidence, hookOwner: fixture.owner)
        let engine = RuntimeStateEngine()
        LocalRuntimeReconciliationOwner.install([rebuilt], into: engine)

        XCTAssertEqual(engine.snapshot().threads.first?.state, .waitingApproval)
        XCTAssertEqual(engine.snapshot().threads.first?.activeTurnID, fixture.turnID)
        XCTAssertEqual(engine.snapshot().waitingApprovalCount, 1)
    }

    func testExistingMonitorCheckpointPersistsOnlyOpaqueHookEvidence() throws {
        let fixture = reconciliationFixture(health: .available, pending: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hook-checkpoint-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ApprovalLifecycleCheckpointStore(url: url)
        try store.save(fixture.checkpoint)
        let restored = try store.load()

        XCTAssertEqual(restored.hookJournal, fixture.checkpoint.hookJournal)
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("prompt"))
        XCTAssertFalse(text.contains("command"))
        XCTAssertFalse(text.contains("tool_input"))
    }

    func testDurableHookPendingWithUnavailableSourceIsPreservedWithoutFalseHealth() {
        let fixture = reconciliationFixture(health: .unavailable, pending: true)
        let rebuilt = LocalRuntimeReconciliationOwner.thread(snapshot: fixture.snapshot, hydration: fixture.hydration, approval: fixture.checkpoint, approvalHealth: .availableKnownNotWaiting, runtimeSourceAvailable: true, observedAt: now, activityAdmission: .requireFreshLiveEvidence, hookOwner: fixture.owner)
        let engine = RuntimeStateEngine()
        LocalRuntimeReconciliationOwner.install([rebuilt], into: engine)

        XCTAssertEqual(engine.snapshot().waitingApprovalCount, 1)
        XCTAssertEqual(engine.snapshot().threads.first?.approvalHealth, .unavailable)
        XCTAssertNotEqual(engine.snapshot().threads.first?.approvalHealth, .availableKnownNotWaiting)
    }

    func testUnavailableHookWithoutPendingNeverBecomesKnownNotWaitingAndUnrelatedOwnerCannotRestore() {
        let unavailable = reconciliationFixture(health: .unavailable, pending: false)
        let unrelated = reconciliationFixture(health: .available, pending: true)
        let rebuiltUnavailable = LocalRuntimeReconciliationOwner.thread(snapshot: unavailable.snapshot, hydration: unavailable.hydration, approval: unavailable.checkpoint, approvalHealth: .availableKnownNotWaiting, runtimeSourceAvailable: true, observedAt: now, hookOwner: unavailable.owner)
        let rebuiltUnrelated = LocalRuntimeReconciliationOwner.thread(snapshot: unrelated.snapshot, hydration: unrelated.hydration, approval: unrelated.checkpoint, approvalHealth: .availableKnownNotWaiting, runtimeSourceAvailable: true, observedAt: now, activityAdmission: .requireFreshLiveEvidence, hookOwner: alternateOwner())

        XCTAssertEqual(rebuiltUnavailable.approvalHealth, .unavailable)
        XCTAssertNotEqual(rebuiltUnavailable.approvalHealth, .availableKnownNotWaiting)
        XCTAssertTrue(rebuiltUnrelated.unresolvedHookApprovals.isEmpty)
        XCTAssertNil(rebuiltUnrelated.activeTurnID)
    }

    func testReconciliationTerminalWinsOverStaleDurableHookPending() {
        let fixture = reconciliationFixture(health: .available, pending: true)
        let terminal = ReconciledTerminal(turnID: fixture.turnID, eventID: "terminal", state: .completed, authoritativeEventAt: now)!
        let rebuilt = RuntimeReconciliationThread(threadID: fixture.snapshot.threadID, activeTurnID: fixture.turnID, turnStartedAt: now, latestActiveState: .thinking, latestActiveStateAt: now, terminal: terminal, approvalHealth: .availableWaiting, unresolvedApprovals: [], unresolvedHookApprovals: fixture.checkpoint.hookJournal!.unresolved, hookApprovalOwner: fixture.owner, runtimeSourceAvailable: true, runtimeObservedAt: now, approvalObservedAt: now)
        let engine = RuntimeStateEngine()
        LocalRuntimeReconciliationOwner.install([rebuilt], into: engine)

        XCTAssertEqual(engine.snapshot().threads.first?.state, .completed)
        XCTAssertNil(engine.snapshot().threads.first?.activeTurnID)
        XCTAssertEqual(engine.snapshot().waitingApprovalCount, 0)
    }

    private func activeEngine() -> (engine: RuntimeStateEngine, threadID: NamespacedID, turnID: NamespacedID, owner: HookApprovalTurnOwner) {
        let engine = RuntimeStateEngine(initialPhase: .live)
        let source = SourceID("runtime-fixture")!
        let threadID = NamespacedID(sourceID: source, entityKind: .thread, rawID: "thread")!
        let turnID = NamespacedID(sourceID: source, entityKind: .turn, rawID: "turn")!
        engine.ingest(RolloutRecordEnvelope(threadID: threadID, turnID: turnID, itemID: nil, kind: .taskStarted, activity: nil, tokenSnapshot: nil, model: nil, reasoningEffort: nil, observedAt: now, fileOffset: 0))
        let owner = owner()
        engine.bindHookApprovalOwner(owner, to: threadID, turnID: turnID, observedAt: now)
        return (engine, threadID, turnID, owner)
    }

    private func snapshot(_ fixture: (engine: RuntimeStateEngine, threadID: NamespacedID, turnID: NamespacedID, owner: HookApprovalTurnOwner)) -> ThreadRuntimeSnapshot {
        fixture.engine.snapshot().threads.first { $0.threadID == fixture.threadID }!
    }

    private func event(_ value: UInt64, owner: HookApprovalTurnOwner) -> HookApprovalLifecycleEvent {
        HookApprovalLifecycleEvent(journalEventID: id(value), owner: owner, observedAt: now)
    }

    private func id(_ value: UInt64) -> HookApprovalJournalEventID { HookApprovalJournalEventID(value)! }

    private func owner() -> HookApprovalTurnOwner {
        HookApprovalTurnOwner(sourceID: opaque("a"), sessionID: opaque("b"), turnID: opaque("c"))
    }

    private func alternateOwner() -> HookApprovalTurnOwner {
        HookApprovalTurnOwner(sourceID: opaque("a"), sessionID: opaque("d"), turnID: opaque("e"))
    }

    private func reconciliationFixture(health: HookApprovalSourceHealthState, pending: Bool) -> (snapshot: DesktopThreadSnapshot, hydration: RolloutCheckpointHydration, checkpoint: ApprovalLifecycleCheckpoint, owner: HookApprovalTurnOwner, turnID: NamespacedID) {
        let source = SourceID("reconciliation-fixture")!
        let thread = NamespacedID(sourceID: source, entityKind: .thread, rawID: "thread")!
        let turn = NamespacedID(sourceID: source, entityKind: .turn, rawID: "turn")!
        let owner = owner()
        let unresolved = pending ? [HookApprovalPendingEvidence(journalEventID: id(1), owner: owner, observedAt: now)] : []
        let checkpoint = ApprovalLifecycleCheckpoint(cursor: nil, unresolved: [], hookJournal: HookApprovalJournalCheckpoint(sourceID: owner.sourceID, lastJournalEventID: pending ? id(1) : nil, unresolved: unresolved, sourceHealth: health))
        let snapshot = DesktopThreadSnapshot(threadID: thread, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil)
        let hydration = RolloutCheckpointHydration(activeTurnID: turn, turnStartedAt: now, activeItemID: nil, activeItemCategory: nil, latestActiveState: .thinking, latestActiveStateAt: now, terminal: nil, authoritativeTokenTotal: nil)
        return (snapshot, hydration, checkpoint, owner, turn)
    }

    private func opaque(_ character: Character) -> HookOpaqueIdentity {
        HookOpaqueIdentity("hmac-sha256:" + String(repeating: String(character), count: 64))!
    }
}
