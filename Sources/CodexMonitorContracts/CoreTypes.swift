import Foundation

/// Evidence states are intentionally granular. No composite realtime state exists.
public enum CapabilityState: String, CaseIterable, Codable, Sendable {
    case unsupported
    case unvalidated
    case snapshot
    case liveAuthoritative
    case mutationValidated
}

public enum CapabilityName: String, CaseIterable, Codable, Sendable {
    case accountReturnedFields
    case planAndAuthModeFields
    case stableLocalAccountDiscriminator
    case primaryRateLimitSnapshot
    case secondaryRateLimitSnapshot
    case sparseRateLimitUpdateMerge
    case usageResponsePresence
    case authoritativeCost
    case resetCreditCount
    case resetCreditDetails
    case resetCreditConsume
    case accountSwitching
    case ownedRuntimeProvenance
    case threadStartObservation
    case threadStatusChangeObservation
    case turnStartObservation
    case itemLifecycleObservation
    case successTurnCompletionObservation
    case tokenUsageUpdateShape
    case exactParentCorrelation
    case thinkingWorkingReduction
    case currentActivityText
    case approvalLifecycle
    case failedInterruptedProjection
    case liveMultiThreadAggregation
    case reconnectReconstruction
    case ownerUISurvival
    case desktopSummaryHistoryRead
    case desktopSourceClassification
    case desktopTitlePreviewStatusHistory
    case desktopRealtimeLifecycle
    case desktopApproval
    case desktopSessionToken
    case desktopTerminalRetention
}

public enum SourceKind: String, CaseIterable, Codable, Sendable {
    case account
    case monitorOwnedRuntime
    case desktopSnapshot
    case futureObserver
}

public struct SourceID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ rawValue: String) {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public enum EntityKind: String, CaseIterable, Codable, Sendable {
    case thread
    case turn
    case item
}

public struct NamespacedID: Hashable, Codable, Sendable {
    public let sourceID: SourceID
    public let entityKind: EntityKind
    public let rawID: String

    public init?(sourceID: SourceID, entityKind: EntityKind, rawID: String) {
        guard !rawID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.sourceID = sourceID
        self.entityKind = entityKind
        self.rawID = rawID
    }
}

public struct AdapterID: Hashable, Codable, Sendable {
    public let rawValue: String
    public init?(_ rawValue: String) {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

public struct AdapterVersion: Hashable, Codable, Sendable {
    public let rawValue: String
    public init?(_ rawValue: String) {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

public struct RuntimeInstanceID: Hashable, Codable, Sendable { public let rawValue: String; public init?(_ value: String) { guard !value.isEmpty else { return nil }; rawValue = value } }
public struct AccountEpoch: Hashable, Codable, Sendable { public let rawValue: String; public init?(_ value: String) { guard !value.isEmpty else { return nil }; rawValue = value } }
public struct ConnectionEpoch: Hashable, Codable, Sendable { public let rawValue: String; public init?(_ value: String) { guard !value.isEmpty else { return nil }; rawValue = value } }
public struct LifecycleEpoch: Hashable, Codable, Sendable { public let rawValue: String; public init?(_ value: String) { guard !value.isEmpty else { return nil }; rawValue = value } }

public enum FreshnessState: String, Codable, Sendable { case fresh, stale, unknown }

public struct Freshness: Codable, Sendable, Equatable {
    public let state: FreshnessState
    public let assessedAt: Date
    public let observedAt: Date
    public let reason: String?
    public init(state: FreshnessState, assessedAt: Date, observedAt: Date, reason: String? = nil) {
        self.state = state
        self.assessedAt = assessedAt
        self.observedAt = observedAt
        self.reason = reason
    }
}

public enum ObservationMode: String, Codable, Sendable { case snapshot, live }
public enum Authority: String, Codable, Sendable { case authoritative, partial, unavailable }
public enum EvidenceOrigin: String, Codable, Sendable { case adapter, fixture }

public struct EvidenceMetadata: Codable, Sendable, Equatable {
    public let evidenceRun: String
    public let cliVersion: String
    public let historicalTransportEvidenceLabel: String
    public let probeOrHarnessAvailability: String
    public let sanitizerAvailability: String
    public let sanitizerVersion: String
    public let confidence: String
    public let limitations: String
    /// A forward H2 decision, deliberately separate from historical evidence.
    public let forwardTransportDecision: String

    public init(evidenceRun: String, cliVersion: String, historicalTransportEvidenceLabel: String, probeOrHarnessAvailability: String, sanitizerAvailability: String, sanitizerVersion: String, confidence: String, limitations: String, forwardTransportDecision: String = "Unix-socket WebSocket") {
        self.evidenceRun = evidenceRun
        self.cliVersion = cliVersion
        self.historicalTransportEvidenceLabel = historicalTransportEvidenceLabel
        self.probeOrHarnessAvailability = probeOrHarnessAvailability
        self.sanitizerAvailability = sanitizerAvailability
        self.sanitizerVersion = sanitizerVersion
        self.confidence = confidence
        self.limitations = limitations
        self.forwardTransportDecision = forwardTransportDecision
    }
}

public struct Provenance: Codable, Sendable, Equatable {
    public let sourceID: SourceID
    public let sourceKind: SourceKind
    public let adapterID: AdapterID
    public let adapterVersion: AdapterVersion
    public let runtimeInstanceID: RuntimeInstanceID?
    public let observationMode: ObservationMode
    public let authority: Authority
    public let observedAt: Date
    public let freshness: Freshness
    public let accountEpoch: AccountEpoch?
    public let connectionEpoch: ConnectionEpoch?
    public let lifecycleEpoch: LifecycleEpoch?
    public let capability: CapabilityName
    public let evidence: EvidenceMetadata
    public let origin: EvidenceOrigin

    public init?(sourceID: SourceID, sourceKind: SourceKind, adapterID: AdapterID, adapterVersion: AdapterVersion, runtimeInstanceID: RuntimeInstanceID? = nil, observationMode: ObservationMode, authority: Authority, observedAt: Date, freshness: Freshness, accountEpoch: AccountEpoch? = nil, connectionEpoch: ConnectionEpoch? = nil, lifecycleEpoch: LifecycleEpoch? = nil, capability: CapabilityName, evidence: EvidenceMetadata, origin: EvidenceOrigin) {
        let runtimeRequiresEpochs = sourceKind == .monitorOwnedRuntime
        guard !runtimeRequiresEpochs || (runtimeInstanceID != nil && connectionEpoch != nil && lifecycleEpoch != nil) else { return nil }
        guard freshness.observedAt == observedAt else { return nil }
        self.sourceID = sourceID; self.sourceKind = sourceKind; self.adapterID = adapterID; self.adapterVersion = adapterVersion
        self.runtimeInstanceID = runtimeInstanceID; self.observationMode = observationMode; self.authority = authority
        self.observedAt = observedAt; self.freshness = freshness; self.accountEpoch = accountEpoch
        self.connectionEpoch = connectionEpoch; self.lifecycleEpoch = lifecycleEpoch; self.capability = capability
        self.evidence = evidence; self.origin = origin
    }
}
