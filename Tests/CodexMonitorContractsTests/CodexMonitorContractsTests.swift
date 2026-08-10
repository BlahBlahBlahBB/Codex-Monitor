import XCTest
@testable import CodexMonitorContracts

final class CodexMonitorContractsTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_728_000_000)

    private var evidence: EvidenceMetadata {
        EvidenceMetadata(
            evidenceRun: "AR-P0 retained evidence decision",
            cliVersion: "0.147.0",
            historicalTransportEvidenceLabel: "unresolved/inconsistent: loopback-IP WebSocket or Unix-socket WebSocket",
            probeOrHarnessAvailability: "unavailable; harness/digest was not retained",
            sanitizerAvailability: "unavailable",
            sanitizerVersion: "unavailable; retained evidence did not record a version",
            confidence: "bounded contract evidence only",
            limitations: "synthetic contract test only"
        )
    }

    private func source(_ value: String = "source-a") -> SourceID { SourceID(value)! }
    private var adapterID: AdapterID { AdapterID("monitor-runtime")! }
    private var adapterVersion: AdapterVersion { AdapterVersion("h1")! }
    private var runtimeID: RuntimeInstanceID { RuntimeInstanceID("runtime-synthetic")! }
    private var accountEpoch: AccountEpoch { AccountEpoch("account-epoch-synthetic")! }
    private var connectionEpoch: ConnectionEpoch { ConnectionEpoch("connection-epoch-synthetic")! }
    private var lifecycleEpoch: LifecycleEpoch { LifecycleEpoch("lifecycle-epoch-synthetic")! }
    private var freshness: Freshness { Freshness(state: .fresh, assessedAt: date, observedAt: date) }

    private func runtimeProvenance(sourceID: SourceID? = nil, capability: CapabilityName = .threadStartObservation, origin: EvidenceOrigin = .adapter, connection: ConnectionEpoch? = nil, lifecycle: LifecycleEpoch? = nil, runtime: RuntimeInstanceID? = nil, account: AccountEpoch? = nil) -> Provenance {
        Provenance(sourceID: sourceID ?? source(), sourceKind: .monitorOwnedRuntime, adapterID: adapterID, adapterVersion: adapterVersion, runtimeInstanceID: runtime ?? runtimeID, observationMode: .live, authority: .partial, observedAt: date, freshness: freshness, accountEpoch: account ?? accountEpoch, connectionEpoch: connection ?? connectionEpoch, lifecycleEpoch: lifecycle ?? lifecycleEpoch, capability: capability, evidence: evidence, origin: origin)!
    }

    private func accountProvenance() -> Provenance {
        Provenance(sourceID: source("account-source"), sourceKind: .account, adapterID: AdapterID("account")!, adapterVersion: adapterVersion, observationMode: .snapshot, authority: .authoritative, observedAt: date, freshness: freshness, capability: .accountReturnedFields, evidence: evidence, origin: .adapter)!
    }

    private func desktopProvenance() -> Provenance {
        Provenance(sourceID: source("desktop-source"), sourceKind: .desktopSnapshot, adapterID: AdapterID("desktop")!, adapterVersion: adapterVersion, observationMode: .snapshot, authority: .partial, observedAt: date, freshness: freshness, capability: .desktopSummaryHistoryRead, evidence: evidence, origin: .adapter)!
    }

    private func thread(_ sourceID: SourceID? = nil, raw: String = "synthetic-thread-alpha") -> NamespacedID { NamespacedID(sourceID: sourceID ?? source(), entityKind: .thread, rawID: raw)! }

    private func candidate(provenance: Provenance? = nil, threadID: NamespacedID? = nil) -> CandidateRuntimeObservationEnvelope {
        CandidateRuntimeObservationEnvelope(provenance: provenance ?? runtimeProvenance(), kind: .threadStarted, threadID: threadID ?? thread())!
    }

    private func descriptor(state: CapabilityState, sourceID: SourceID? = nil) -> AdapterDescriptor {
        AdapterDescriptor(adapterID: adapterID, adapterVersion: adapterVersion, sourceKind: .monitorOwnedRuntime, sourceID: sourceID ?? source(), capabilitySnapshot: CapabilitySnapshot([.threadStartObservation: state]), evidenceMetadata: evidence)
    }

    private func context(descriptor: AdapterDescriptor, threadID: NamespacedID? = nil, connection: ConnectionEpoch? = nil) -> LiveAdmissionContext {
        let ownedThread = threadID ?? thread(descriptor.sourceID)
        let ownership = OwnershipRecord(sourceID: descriptor.sourceID, runtimeInstanceID: runtimeID, namespacedThreadID: ownedThread, creationProvenance: runtimeProvenance(sourceID: descriptor.sourceID), accountEpoch: accountEpoch, lifecycleEpoch: lifecycleEpoch)
        return LiveAdmissionContext(descriptor: descriptor, ownership: ownership, connectionEpoch: connection ?? connectionEpoch)
    }

    func test01CapabilityTaxonomyIsExactlyFiveStates() {
        XCTAssertEqual(Set(CapabilityState.allCases.map(\.rawValue)), ["unsupported", "unvalidated", "snapshot", "liveAuthoritative", "mutationValidated"])
        XCTAssertFalse(CapabilityName.allCases.map(\.rawValue).contains("fullRealtime"))
    }

    func test02NamespacedIdentityIsSourceSensitive() {
        XCTAssertNotEqual(thread(source("source-a")), thread(source("source-b")))
    }

    func test03EntityKindParticipatesInIdentity() {
        let sourceID = source()
        XCTAssertNotEqual(NamespacedID(sourceID: sourceID, entityKind: .thread, rawID: "same")!, NamespacedID(sourceID: sourceID, entityKind: .turn, rawID: "same")!)
    }

    func test04ProvenanceIsRequiredAndInternallyConsistent() {
        XCTAssertNil(Provenance(sourceID: source(), sourceKind: .monitorOwnedRuntime, adapterID: adapterID, adapterVersion: adapterVersion, observationMode: .live, authority: .partial, observedAt: date, freshness: freshness, capability: .threadStartObservation, evidence: evidence, origin: .adapter))
        XCTAssertNil(Provenance(sourceID: source(), sourceKind: .account, adapterID: adapterID, adapterVersion: adapterVersion, observationMode: .snapshot, authority: .authoritative, observedAt: date, freshness: Freshness(state: .fresh, assessedAt: date, observedAt: date.addingTimeInterval(1)), capability: .accountReturnedFields, evidence: evidence, origin: .adapter))
    }

    func test05AccountConnectedDoesNotCreateRuntimeAvailabilityOrIdle() {
        let output = AdapterOutput.accountSnapshot(AccountSnapshot(provenance: accountProvenance()))
        XCTAssertNil(H1LiveBoundary.candidate(from: output))
    }

    func test06FreshQuotaDoesNotCreateRuntimeStateRingOrAnimationEligibility() {
        let account = AccountSnapshot(provenance: accountProvenance(), primaryRateLimit: RateLimitWindow(usedPercent: 10))
        XCTAssertEqual(account.primaryRateLimit?.usedPercent, 10)
        XCTAssertNil(H1LiveBoundary.candidate(from: .accountSnapshot(account)))
    }

    func test07DesktopRawActiveDoesNotCreateThinkingOrWorking() throws {
        let summary = try SnapshotSummary(provenance: desktopProvenance(), readAt: date, rawStatus: "active", titleAvailability: .unknown, previewAvailability: .unknown, historyAvailability: .unknown, sourceClassification: .unclassified, staleness: freshness)
        XCTAssertNil(H1LiveBoundary.candidate(from: .snapshotSummary(summary)))
    }

    func test08AccountUsageIsNotSessionToken() {
        let usage = UsagePresence(totalTokens: 123)
        XCTAssertEqual(usage.totalTokens, 123)
        XCTAssertNil(usage.costUSD)
    }

    func test09SchemaPresenceDoesNotEnableResetMutation() {
        let descriptor = AdapterDescriptor(adapterID: AdapterID("account")!, adapterVersion: adapterVersion, sourceKind: .account, sourceID: source("account-source"), capabilitySnapshot: CapabilitySnapshot([.resetCreditConsume: .unvalidated]), evidenceMetadata: evidence)
        XCTAssertEqual(descriptor.capabilitySnapshot.state(for: .resetCreditConsume), .unvalidated)
    }

    func test10SnapshotSummaryCannotEnterLiveAdmissionPath() throws {
        let summary = try SnapshotSummary(provenance: desktopProvenance(), readAt: date, titleAvailability: .unavailable, previewAvailability: .unavailable, historyAvailability: .unavailable, sourceClassification: .unvalidated, staleness: freshness)
        XCTAssertNil(H1LiveBoundary.candidate(from: .snapshotSummary(summary)))
    }

    func test11FixtureCannotPromoteRealAdapterOrEnterGate() throws {
        let descriptor = descriptor(state: .liveAuthoritative)
        let gate = LiveProductAdmissionGate(registry: try AdapterRegistry([descriptor]))
        let fixture = candidate(provenance: runtimeProvenance(capability: .threadStartObservation, origin: .fixture, account: accountEpoch))
        XCTAssertEqual(gate.admit(fixture, using: context(descriptor: descriptor)), .failure(.fixtureOrigin))
        XCTAssertEqual(descriptor.capabilitySnapshot.state(for: .threadStartObservation), .liveAuthoritative)
    }

    func test12FutureObserverIsAllUnsupportedAndZeroOutput() {
        let future = FutureObserverAdapter(descriptor: H1Baseline.futureObserverDescriptor(sourceID: source("future-source"), evidence: evidence))
        XCTAssertTrue(future.isAllUnsupported)
        XCTAssertTrue(future.outputs.isEmpty)
    }

    func test13MissingSecondaryCostAndDetailsRemainNil() {
        let account = AccountSnapshot(provenance: accountProvenance(), usage: UsagePresence())
        XCTAssertNil(account.secondaryRateLimit)
        XCTAssertNil(account.usage?.costUSD)
        XCTAssertNil(account.resetCreditDetails)
    }

    func test14AdapterAndSourceLanesAreIsolated() throws {
        let account = AdapterOutput.accountSnapshot(AccountSnapshot(provenance: accountProvenance()))
        let desktop = AdapterOutput.snapshotSummary(try SnapshotSummary(provenance: desktopProvenance(), readAt: date, titleAvailability: .unknown, previewAvailability: .unknown, historyAvailability: .unknown, sourceClassification: .unclassified, staleness: freshness))
        XCTAssertNil(H1LiveBoundary.candidate(from: account))
        XCTAssertNil(H1LiveBoundary.candidate(from: desktop))
    }

    func test15CapabilityDowngradeRejectsFormerlyEligibleCandidate() throws {
        let live = descriptor(state: .liveAuthoritative)
        let candidate = candidate(provenance: runtimeProvenance(sourceID: live.sourceID))
        if case .success = LiveProductAdmissionGate(registry: try AdapterRegistry([live])).admit(candidate, using: context(descriptor: live)) {
            // Admission has a deliberately opaque success wrapper.
        } else {
            XCTFail("live-authoritative exact match must be admitted")
        }
        let downgraded = descriptor(state: .unvalidated)
        XCTAssertEqual(LiveProductAdmissionGate(registry: try AdapterRegistry([downgraded])).admit(candidate, using: context(descriptor: downgraded)), .failure(.capabilityNotLiveAuthoritative(.unvalidated)))
    }

    func test16SourceRuntimeConnectionAndLifecycleMismatchReject() throws {
        let descriptor = descriptor(state: .liveAuthoritative)
        let gate = LiveProductAdmissionGate(registry: try AdapterRegistry([descriptor]))
        let valid = context(descriptor: descriptor)
        XCTAssertEqual(gate.admit(candidate(provenance: runtimeProvenance(sourceID: descriptor.sourceID, connection: ConnectionEpoch("other-connection")!)), using: valid), .failure(.connectionEpochMismatch))
        XCTAssertEqual(gate.admit(candidate(provenance: runtimeProvenance(sourceID: descriptor.sourceID, lifecycle: LifecycleEpoch("other-lifecycle")!)), using: valid), .failure(.lifecycleEpochMismatch))
        XCTAssertEqual(gate.admit(candidate(provenance: runtimeProvenance(sourceID: descriptor.sourceID, runtime: RuntimeInstanceID("other-runtime")!)), using: valid), .failure(.runtimeMismatch))
        let otherSource = source("other-source")
        XCTAssertEqual(gate.admit(candidate(provenance: runtimeProvenance(sourceID: otherSource), threadID: thread(otherSource)), using: valid), .failure(.descriptorNotRegistered))
    }

    func test17MatchingUnvalidatedCandidateRejectsAndCallsNoProductCallback() throws {
        let descriptor = descriptor(state: .unvalidated)
        let gate = LiveProductAdmissionGate(registry: try AdapterRegistry([descriptor]))
        var callbackCount = 0
        let result = gate.deliver(candidate(provenance: runtimeProvenance(sourceID: descriptor.sourceID)), using: context(descriptor: descriptor)) { _ in callbackCount += 1 }
        XCTAssertEqual(result, .failure(.capabilityNotLiveAuthoritative(.unvalidated)))
        XCTAssertEqual(callbackCount, 0)
    }

    func test18UnsupportedAndSnapshotCandidatesRejectFromLivePath() throws {
        for state in [CapabilityState.unsupported, .snapshot] {
            let descriptor = descriptor(state: state)
            let gate = LiveProductAdmissionGate(registry: try AdapterRegistry([descriptor]))
            XCTAssertEqual(gate.admit(candidate(provenance: runtimeProvenance(sourceID: descriptor.sourceID)), using: context(descriptor: descriptor)), .failure(.capabilityNotLiveAuthoritative(state)))
        }
    }

    func test19OwnershipAndPartialAuthorityCannotBypassGate() throws {
        let descriptor = descriptor(state: .unvalidated)
        let gate = LiveProductAdmissionGate(registry: try AdapterRegistry([descriptor]))
        XCTAssertEqual(gate.admit(candidate(provenance: runtimeProvenance(sourceID: descriptor.sourceID)), using: context(descriptor: descriptor)), .failure(.capabilityNotLiveAuthoritative(.unvalidated)))
    }

    func test20ForwardUnixSocketDecisionDoesNotRewriteHistoricalEvidence() {
        XCTAssertEqual(evidence.forwardTransportDecision, "Unix-socket WebSocket")
        XCTAssertTrue(evidence.historicalTransportEvidenceLabel.contains("unresolved/inconsistent"))
        XCTAssertNotEqual(evidence.forwardTransportDecision, evidence.historicalTransportEvidenceLabel)
    }

    func test21BaselineInstantiatesNoLiveAuthoritativeRealCapabilities() throws {
        let registry = try H1Baseline.registry(accountSourceID: source("account-source"), runtimeSourceID: source(), desktopSourceID: source("desktop-source"), futureSourceID: source("future-source"), evidence: evidence)
        XCTAssertEqual(registry.realLiveAuthoritativeCapabilityCount, 0)
    }

    func test22AccountAndParentIdentityMismatchesReject() throws {
        let descriptor = descriptor(state: .liveAuthoritative)
        let gate = LiveProductAdmissionGate(registry: try AdapterRegistry([descriptor]))
        let context = context(descriptor: descriptor)
        let wrongAccount = candidate(provenance: runtimeProvenance(sourceID: descriptor.sourceID, account: AccountEpoch("other-account")!))
        XCTAssertEqual(gate.admit(wrongAccount, using: context), .failure(.accountEpochMismatch))
        let wrongThread = candidate(provenance: runtimeProvenance(sourceID: descriptor.sourceID), threadID: thread(descriptor.sourceID, raw: "other-thread"))
        XCTAssertEqual(gate.admit(wrongThread, using: context), .failure(.parentIdentityMismatch))
    }

    func test23FixturesAreCompleteSanitizedAndBaselineScoped() throws {
        let expected = Set(["account-snapshot-minimal-v1", "owned-thread-started-v1", "owned-thread-status-changed-v1", "owned-turn-started-v1", "owned-item-started-v1", "owned-item-completed-v1", "owned-turn-completed-success-v1", "owned-token-usage-shape-v1", "desktop-summary-unclassified-v1", "future-observer-empty-v1"])
        let fixtures = try loadFixtures()
        XCTAssertEqual(Set(fixtures.map(\.fixtureID)), expected)
        for fixture in fixtures {
            XCTAssertEqual(fixture.cliVersion, "0.147.0")
            XCTAssertTrue(fixture.historicalTransportEvidenceLabel.contains("unresolved/inconsistent"))
            XCTAssertEqual(fixture.forwardTransportDecision, "Unix-socket WebSocket")
            XCTAssertFalse(fixture.serialized.contains("/Users/"))
            XCTAssertFalse(fixture.serialized.lowercased().contains("credential"))
        }
    }

    private func loadFixtures() throws -> [FixtureAuditRecord] {
        let urls = try FileManager.default.contentsOfDirectory(at: Bundle.module.resourceURL!, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        return try urls.map { url in try FixtureAuditRecord(data: Data(contentsOf: url)) }
    }
}

private struct FixtureAuditRecord {
    let fixtureID: String
    let sourceKind: String
    let capability: String
    let capabilityState: String
    let evidenceRun: String
    let cliVersion: String
    let historicalTransportEvidenceLabel: String
    let probeOrHarnessAvailability: String
    let sanitizerAvailability: String
    let sanitizerVersion: String
    let confidence: String
    let limitations: String
    let forwardTransportDecision: String
    let serialized: String

    init(data: Data) throws {
        let decoded = try JSONDecoder().decode(Decoded.self, from: data)
        fixtureID = decoded.fixtureID
        sourceKind = decoded.sourceKind
        capability = decoded.capability
        capabilityState = decoded.capabilityState
        evidenceRun = decoded.evidenceRun
        cliVersion = decoded.cliVersion
        historicalTransportEvidenceLabel = decoded.historicalTransportEvidenceLabel
        probeOrHarnessAvailability = decoded.probeOrHarnessAvailability
        sanitizerAvailability = decoded.sanitizerAvailability
        sanitizerVersion = decoded.sanitizerVersion
        confidence = decoded.confidence
        limitations = decoded.limitations
        forwardTransportDecision = decoded.forwardTransportDecision
        serialized = String(decoding: data, as: UTF8.self)
    }

    private struct Decoded: Decodable {
        let fixtureID: String
        let sourceKind: String
        let capability: String
        let capabilityState: String
        let evidenceRun: String
        let cliVersion: String
        let historicalTransportEvidenceLabel: String
        let probeOrHarnessAvailability: String
        let sanitizerAvailability: String
        let sanitizerVersion: String
        let confidence: String
        let limitations: String
        let forwardTransportDecision: String
    }
}
