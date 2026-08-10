import Foundation

public struct CapabilitySnapshot: Sendable, Equatable {
    private let states: [CapabilityName: CapabilityState]
    public init(_ states: [CapabilityName: CapabilityState]) { self.states = states }
    public func state(for capability: CapabilityName) -> CapabilityState { states[capability] ?? .unsupported }
    public var allStates: [CapabilityName: CapabilityState] { states }
}

public struct AdapterDescriptor: Sendable, Equatable {
    public let adapterID: AdapterID
    public let adapterVersion: AdapterVersion
    public let sourceKind: SourceKind
    public let sourceID: SourceID
    public let capabilitySnapshot: CapabilitySnapshot
    public let evidenceMetadata: EvidenceMetadata

    public init(adapterID: AdapterID, adapterVersion: AdapterVersion, sourceKind: SourceKind, sourceID: SourceID, capabilitySnapshot: CapabilitySnapshot, evidenceMetadata: EvidenceMetadata) {
        self.adapterID = adapterID; self.adapterVersion = adapterVersion; self.sourceKind = sourceKind; self.sourceID = sourceID
        self.capabilitySnapshot = capabilitySnapshot; self.evidenceMetadata = evidenceMetadata
    }
}

public enum RegistryError: Error, Equatable {
    case duplicateDescriptor
    case incompatibleDescriptor
}

public struct AdapterRegistry: Sendable {
    private let descriptors: [DescriptorKey: AdapterDescriptor]
    public init(_ values: [AdapterDescriptor]) throws {
        var built: [DescriptorKey: AdapterDescriptor] = [:]
        for descriptor in values {
            guard descriptor.isLaneCompatible else { throw RegistryError.incompatibleDescriptor }
            let key = DescriptorKey(descriptor)
            guard built[key] == nil else { throw RegistryError.duplicateDescriptor }
            built[key] = descriptor
        }
        descriptors = built
    }
    public func descriptor(adapterID: AdapterID, adapterVersion: AdapterVersion, sourceKind: SourceKind, sourceID: SourceID) -> AdapterDescriptor? {
        descriptors[DescriptorKey(adapterID: adapterID, adapterVersion: adapterVersion, sourceKind: sourceKind, sourceID: sourceID)]
    }
    public var allDescriptors: [AdapterDescriptor] { Array(descriptors.values) }
    public var realLiveAuthoritativeCapabilityCount: Int {
        descriptors.values.reduce(0) { partial, descriptor in
            partial + descriptor.capabilitySnapshot.allStates.values.filter { $0 == .liveAuthoritative }.count
        }
    }

    /// A uniform output boundary. Construction of a payload alone never asserts
    /// that it belongs to the descriptor currently registered for its source.
    public func validatedOutput(_ output: AdapterOutput) throws -> AdapterOutput {
        let provenance = output.provenance
        guard let descriptor = descriptor(
            adapterID: provenance.adapterID,
            adapterVersion: provenance.adapterVersion,
            sourceKind: provenance.sourceKind,
            sourceID: provenance.sourceID
        ) else {
            throw AdapterOutputRejection.descriptorNotRegistered
        }
        guard descriptor.isLaneCompatible,
              provenance.capability.isCompatible(with: descriptor.sourceKind) else {
            throw AdapterOutputRejection.incompatibleDescriptor
        }
        switch output {
        case .accountSnapshot:
            guard descriptor.sourceKind == .account,
                  provenance.observationMode == .snapshot else {
                throw AdapterOutputRejection.laneMismatch
            }
        case .candidateRuntimeObservation:
            guard descriptor.sourceKind == .monitorOwnedRuntime,
                  provenance.observationMode == .live else {
                throw AdapterOutputRejection.laneMismatch
            }
        case .snapshotSummary:
            guard descriptor.sourceKind == .desktopSnapshot,
                  provenance.observationMode == .snapshot else {
                throw AdapterOutputRejection.laneMismatch
            }
        case .sourceHealth:
            guard provenance.sourceKind != .futureObserver else {
                throw AdapterOutputRejection.laneMismatch
            }
        }
        return output
    }
}

public enum AdapterOutputRejection: Error, Equatable {
    case descriptorNotRegistered
    case incompatibleDescriptor
    case laneMismatch
}

private extension AdapterDescriptor {
    var isLaneCompatible: Bool {
        if sourceKind == .futureObserver {
            return CapabilityName.allCases.allSatisfy {
                capabilitySnapshot.state(for: $0) == .unsupported
            }
        }
        return capabilitySnapshot.allStates.keys.allSatisfy { $0.isCompatible(with: sourceKind) }
    }
}

public extension CapabilityName {
    func isCompatible(with sourceKind: SourceKind) -> Bool {
        switch sourceKind {
        case .account:
            switch self {
            case .accountReturnedFields, .planAndAuthModeFields, .stableLocalAccountDiscriminator,
                 .primaryRateLimitSnapshot, .secondaryRateLimitSnapshot, .sparseRateLimitUpdateMerge,
                 .usageResponsePresence, .authoritativeCost, .resetCreditCount, .resetCreditDetails,
                 .resetCreditConsume, .accountSwitching:
                return true
            default:
                return false
            }
        case .monitorOwnedRuntime:
            switch self {
            case .ownedRuntimeProvenance, .threadStartObservation, .threadStatusChangeObservation,
                 .turnStartObservation, .itemLifecycleObservation, .successTurnCompletionObservation,
                 .tokenUsageUpdateShape, .exactParentCorrelation, .thinkingWorkingReduction,
                 .currentActivityText, .approvalLifecycle, .failedInterruptedProjection,
                 .liveMultiThreadAggregation, .reconnectReconstruction, .ownerUISurvival:
                return true
            default:
                return false
            }
        case .desktopSnapshot:
            switch self {
            case .desktopSummaryHistoryRead, .desktopSourceClassification,
                 .desktopTitlePreviewStatusHistory, .desktopRealtimeLifecycle,
                 .desktopApproval, .desktopSessionToken, .desktopTerminalRetention:
                return true
            default:
                return false
            }
        case .futureObserver:
            return true
        }
    }
}

private struct DescriptorKey: Hashable, Sendable {
    let adapterID: AdapterID; let adapterVersion: AdapterVersion; let sourceKind: SourceKind; let sourceID: SourceID
    init(_ descriptor: AdapterDescriptor) { self.init(adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, sourceKind: descriptor.sourceKind, sourceID: descriptor.sourceID) }
    init(adapterID: AdapterID, adapterVersion: AdapterVersion, sourceKind: SourceKind, sourceID: SourceID) { self.adapterID = adapterID; self.adapterVersion = adapterVersion; self.sourceKind = sourceKind; self.sourceID = sourceID }
}

public struct RateLimitWindow: Codable, Sendable, Equatable {
    public let usedPercent: Double?
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?
    public let reachedType: String?
    public init(usedPercent: Double? = nil, windowDurationMinutes: Int? = nil, resetsAt: Date? = nil, reachedType: String? = nil) { self.usedPercent = usedPercent; self.windowDurationMinutes = windowDurationMinutes; self.resetsAt = resetsAt; self.reachedType = reachedType }
}

public struct UsagePresence: Codable, Sendable, Equatable {
    public let summaryAvailable: Bool?
    public let dailyBucketsAvailable: Bool?
    public let inputTokens: Int?
    public let cachedInputTokens: Int?
    public let outputTokens: Int?
    public let reasoningOutputTokens: Int?
    public let totalTokens: Int?
    public let costUSD: Decimal? = nil
    public init(summaryAvailable: Bool? = nil, dailyBucketsAvailable: Bool? = nil, inputTokens: Int? = nil, cachedInputTokens: Int? = nil, outputTokens: Int? = nil, reasoningOutputTokens: Int? = nil, totalTokens: Int? = nil) {
        self.summaryAvailable = summaryAvailable; self.dailyBucketsAvailable = dailyBucketsAvailable; self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens; self.outputTokens = outputTokens; self.reasoningOutputTokens = reasoningOutputTokens; self.totalTokens = totalTokens
    }
    private enum CodingKeys: String, CodingKey { case summaryAvailable, dailyBucketsAvailable, inputTokens, cachedInputTokens, outputTokens, reasoningOutputTokens, totalTokens }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(summaryAvailable: try values.decodeIfPresent(Bool.self, forKey: .summaryAvailable), dailyBucketsAvailable: try values.decodeIfPresent(Bool.self, forKey: .dailyBucketsAvailable), inputTokens: try values.decodeIfPresent(Int.self, forKey: .inputTokens), cachedInputTokens: try values.decodeIfPresent(Int.self, forKey: .cachedInputTokens), outputTokens: try values.decodeIfPresent(Int.self, forKey: .outputTokens), reasoningOutputTokens: try values.decodeIfPresent(Int.self, forKey: .reasoningOutputTokens), totalTokens: try values.decodeIfPresent(Int.self, forKey: .totalTokens))
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(summaryAvailable, forKey: .summaryAvailable); try values.encodeIfPresent(dailyBucketsAvailable, forKey: .dailyBucketsAvailable)
        try values.encodeIfPresent(inputTokens, forKey: .inputTokens); try values.encodeIfPresent(cachedInputTokens, forKey: .cachedInputTokens)
        try values.encodeIfPresent(outputTokens, forKey: .outputTokens); try values.encodeIfPresent(reasoningOutputTokens, forKey: .reasoningOutputTokens); try values.encodeIfPresent(totalTokens, forKey: .totalTokens)
    }
}

public struct AccountSnapshot: Codable, Sendable, Equatable {
    public let provenance: Provenance
    public let email: String?
    public let planType: String?
    public let authMode: String?
    public let primaryRateLimit: RateLimitWindow?
    public let secondaryRateLimit: RateLimitWindow?
    public let usage: UsagePresence?
    public let resetCreditCount: Int?
    public let resetCreditDetails: [String]?
    public init?(provenance: Provenance, email: String? = nil, planType: String? = nil, authMode: String? = nil, primaryRateLimit: RateLimitWindow? = nil, secondaryRateLimit: RateLimitWindow? = nil, usage: UsagePresence? = nil, resetCreditCount: Int? = nil, resetCreditDetails: [String]? = nil) {
        guard provenance.sourceKind == .account,
              provenance.observationMode == .snapshot,
              provenance.capability.isCompatible(with: .account) else { return nil }
        self.provenance = provenance; self.email = email; self.planType = planType; self.authMode = authMode
        self.primaryRateLimit = primaryRateLimit; self.secondaryRateLimit = secondaryRateLimit; self.usage = usage
        self.resetCreditCount = resetCreditCount; self.resetCreditDetails = resetCreditDetails
    }
}

public enum Availability: String, Codable, Sendable { case available, unavailable, unknown }
public enum SourceClassification: String, Codable, Sendable { case unclassified, unvalidated, validated }
public enum SnapshotSummaryError: Error, Equatable {
    case mustBeDesktopSnapshot
    case mustBeSnapshot
    case incompatibleCapability
    case validatedClassificationNotAllowed
}

public struct SnapshotSummary: Codable, Sendable, Equatable {
    public let provenance: Provenance
    public let readAt: Date
    public let rawStatus: String?
    public let titleAvailability: Availability
    public let previewAvailability: Availability
    public let historyAvailability: Availability
    public let sourceClassification: SourceClassification
    public let staleness: Freshness
    public init(provenance: Provenance, readAt: Date, rawStatus: String? = nil, titleAvailability: Availability, previewAvailability: Availability, historyAvailability: Availability, sourceClassification: SourceClassification, staleness: Freshness) throws {
        guard provenance.sourceKind == .desktopSnapshot else { throw SnapshotSummaryError.mustBeDesktopSnapshot }
        guard provenance.observationMode == .snapshot else { throw SnapshotSummaryError.mustBeSnapshot }
        guard provenance.capability.isCompatible(with: .desktopSnapshot) else { throw SnapshotSummaryError.incompatibleCapability }
        guard sourceClassification != .validated else { throw SnapshotSummaryError.validatedClassificationNotAllowed }
        self.provenance = provenance; self.readAt = readAt; self.rawStatus = rawStatus; self.titleAvailability = titleAvailability
        self.previewAvailability = previewAvailability; self.historyAvailability = historyAvailability; self.sourceClassification = sourceClassification; self.staleness = staleness
    }
}

public enum RuntimeObservationKind: String, Codable, CaseIterable, Sendable {
    case threadStarted, threadStatusChanged, turnStarted, itemStarted, itemCompleted, turnCompletedSuccess, threadTokenUsageUpdated
}

public extension RuntimeObservationKind {
    var requiredCapability: CapabilityName {
        switch self {
        case .threadStarted: .threadStartObservation
        case .threadStatusChanged: .threadStatusChangeObservation
        case .turnStarted: .turnStartObservation
        case .itemStarted, .itemCompleted: .itemLifecycleObservation
        case .turnCompletedSuccess: .successTurnCompletionObservation
        case .threadTokenUsageUpdated: .tokenUsageUpdateShape
        }
    }

    /// The retained H1 evidence makes identities optional, but never changes the
    /// namespace or entity kind of any identity that is actually supplied.
    func acceptsSuppliedIdentityShape(threadID: NamespacedID?, turnID: NamespacedID?, itemID: NamespacedID?) -> Bool {
        let validThread = threadID.map { $0.entityKind == .thread } ?? true
        let validTurn = turnID.map { $0.entityKind == .turn } ?? true
        let validItem = itemID.map { $0.entityKind == .item } ?? true
        switch self {
        case .threadStarted, .threadStatusChanged:
            return validThread && turnID == nil && itemID == nil
        case .threadTokenUsageUpdated:
            return validThread && validTurn && itemID == nil
        case .turnStarted, .turnCompletedSuccess:
            return validThread && validTurn && itemID == nil
        case .itemStarted, .itemCompleted:
            return validThread && validTurn && validItem
        }
    }
}

public enum RuntimeItemKind: String, Codable, Sendable { case reasoning, commandExecution, agentMessage, userMessage }

public struct CandidateRuntimeObservationEnvelope: Codable, Sendable, Equatable {
    public let provenance: Provenance
    public let kind: RuntimeObservationKind
    public let threadID: NamespacedID?
    public let turnID: NamespacedID?
    public let itemID: NamespacedID?
    public let itemKind: RuntimeItemKind?
    public let opaqueStatus: String?
    public init?(provenance: Provenance, kind: RuntimeObservationKind, threadID: NamespacedID? = nil, turnID: NamespacedID? = nil, itemID: NamespacedID? = nil, itemKind: RuntimeItemKind? = nil, opaqueStatus: String? = nil) {
        guard provenance.sourceKind == .monitorOwnedRuntime, provenance.observationMode == .live else { return nil }
        self.provenance = provenance; self.kind = kind; self.threadID = threadID; self.turnID = turnID; self.itemID = itemID; self.itemKind = itemKind; self.opaqueStatus = opaqueStatus
    }
}

public struct OwnershipRecord: Codable, Sendable, Equatable {
    public let sourceID: SourceID
    public let runtimeInstanceID: RuntimeInstanceID
    public let namespacedThreadID: NamespacedID
    public let creationProvenance: Provenance
    public let accountEpoch: AccountEpoch?
    public let lifecycleEpoch: LifecycleEpoch
    public init(sourceID: SourceID, runtimeInstanceID: RuntimeInstanceID, namespacedThreadID: NamespacedID, creationProvenance: Provenance, accountEpoch: AccountEpoch?, lifecycleEpoch: LifecycleEpoch) {
        self.sourceID = sourceID; self.runtimeInstanceID = runtimeInstanceID; self.namespacedThreadID = namespacedThreadID
        self.creationProvenance = creationProvenance; self.accountEpoch = accountEpoch; self.lifecycleEpoch = lifecycleEpoch
    }

    func isConsistent(with descriptor: AdapterDescriptor) -> Bool {
        sourceID == descriptor.sourceID &&
        namespacedThreadID.sourceID == sourceID &&
        namespacedThreadID.entityKind == .thread &&
        creationProvenance.sourceID == sourceID &&
        creationProvenance.sourceKind == .monitorOwnedRuntime &&
        creationProvenance.adapterID == descriptor.adapterID &&
        creationProvenance.adapterVersion == descriptor.adapterVersion &&
        creationProvenance.runtimeInstanceID == runtimeInstanceID &&
        creationProvenance.accountEpoch == accountEpoch &&
        creationProvenance.lifecycleEpoch == lifecycleEpoch
    }
}

public enum AdapterOutput: Sendable, Equatable {
    case accountSnapshot(AccountSnapshot)
    case candidateRuntimeObservation(CandidateRuntimeObservationEnvelope)
    case snapshotSummary(SnapshotSummary)
    case sourceHealth(SourceHealth)

    fileprivate var provenance: Provenance {
        switch self {
        case .accountSnapshot(let snapshot): snapshot.provenance
        case .candidateRuntimeObservation(let candidate): candidate.provenance
        case .snapshotSummary(let summary): summary.provenance
        case .sourceHealth(let health): health.provenance
        }
    }
}

/// Transport health is strictly source-local.  It is intentionally not a task
/// state and has no route through `H1LiveBoundary`.
public enum SourceHealthState: String, Codable, Sendable, Equatable {
    case connecting
    case connected
    case unavailable
    case closed
}

public enum SourceHealthReasonCode: String, Codable, Sendable, Equatable {
    case socketClosed
    case sourceUnavailable
    case malformedMessage
}

public struct SourceHealth: Codable, Sendable, Equatable {
    public let provenance: Provenance
    public let state: SourceHealthState
    /// A sanitizer-produced machine-readable reason, never a raw socket path,
    /// JSON-RPC payload, credential, or server error message.
    public let reasonCode: SourceHealthReasonCode?

    public init?(provenance: Provenance, state: SourceHealthState, reasonCode: SourceHealthReasonCode? = nil) {
        self.provenance = provenance
        self.state = state
        self.reasonCode = reasonCode
    }
}

/// This is the only H1 extraction point for a future live-admission primitive.
/// Snapshot and account outputs have no conversion route into it.
public enum H1LiveBoundary {
    public static func candidate(from output: AdapterOutput) -> CandidateRuntimeObservationEnvelope? {
        guard case .candidateRuntimeObservation(let candidate) = output else { return nil }
        return candidate
    }
}

public struct FutureObserverAdapter: Sendable {
    public let descriptor: AdapterDescriptor
    public init?(descriptor: AdapterDescriptor) {
        guard descriptor.sourceKind == .futureObserver,
              CapabilityName.allCases.allSatisfy({ descriptor.capabilitySnapshot.state(for: $0) == .unsupported }) else {
            return nil
        }
        self.descriptor = descriptor
    }
    public var outputs: [AdapterOutput] { [] }
    public var isAllUnsupported: Bool { descriptor.capabilitySnapshot.allStates.values.allSatisfy { $0 == .unsupported } }
}

public enum H1Baseline {
    public static func registry(accountSourceID: SourceID, runtimeSourceID: SourceID, desktopSourceID: SourceID, futureSourceID: SourceID, evidence: EvidenceMetadata) throws -> AdapterRegistry {
        func snapshot(_ values: [CapabilityName: CapabilityState]) -> CapabilitySnapshot {
            CapabilitySnapshot(values)
        }
        let account = AdapterDescriptor(adapterID: AdapterID("account")!, adapterVersion: AdapterVersion("h1")!, sourceKind: .account, sourceID: accountSourceID, capabilitySnapshot: snapshot([
            .accountReturnedFields: .snapshot, .planAndAuthModeFields: .snapshot, .stableLocalAccountDiscriminator: .unvalidated,
            .primaryRateLimitSnapshot: .snapshot, .secondaryRateLimitSnapshot: .unvalidated, .sparseRateLimitUpdateMerge: .unvalidated,
            .usageResponsePresence: .snapshot, .authoritativeCost: .unsupported, .resetCreditCount: .snapshot,
            .resetCreditDetails: .unvalidated, .resetCreditConsume: .unvalidated, .accountSwitching: .unvalidated
        ]), evidenceMetadata: evidence)
        let runtime = AdapterDescriptor(adapterID: AdapterID("monitor-runtime")!, adapterVersion: AdapterVersion("h1")!, sourceKind: .monitorOwnedRuntime, sourceID: runtimeSourceID, capabilitySnapshot: snapshot([
            .ownedRuntimeProvenance: .unvalidated, .threadStartObservation: .unvalidated, .threadStatusChangeObservation: .unvalidated,
            .turnStartObservation: .unvalidated, .itemLifecycleObservation: .unvalidated, .successTurnCompletionObservation: .unvalidated,
            .tokenUsageUpdateShape: .unvalidated, .exactParentCorrelation: .unvalidated, .thinkingWorkingReduction: .unvalidated,
            .currentActivityText: .unvalidated, .approvalLifecycle: .unvalidated, .failedInterruptedProjection: .unvalidated,
            .liveMultiThreadAggregation: .unvalidated, .reconnectReconstruction: .unvalidated, .ownerUISurvival: .unvalidated
        ]), evidenceMetadata: evidence)
        let desktop = AdapterDescriptor(adapterID: AdapterID("desktop")!, adapterVersion: AdapterVersion("h1")!, sourceKind: .desktopSnapshot, sourceID: desktopSourceID, capabilitySnapshot: snapshot([
            .desktopSummaryHistoryRead: .snapshot, .desktopSourceClassification: .unvalidated, .desktopTitlePreviewStatusHistory: .snapshot,
            .desktopRealtimeLifecycle: .unsupported, .desktopApproval: .unsupported, .desktopSessionToken: .unsupported, .desktopTerminalRetention: .unsupported
        ]), evidenceMetadata: evidence)
        return try AdapterRegistry([account, runtime, desktop, futureObserverDescriptor(sourceID: futureSourceID, evidence: evidence)])
    }

    public static func futureObserverDescriptor(sourceID: SourceID, evidence: EvidenceMetadata) -> AdapterDescriptor {
        AdapterDescriptor(adapterID: AdapterID("future-observer")!, adapterVersion: AdapterVersion("h1")!, sourceKind: .futureObserver, sourceID: sourceID, capabilitySnapshot: CapabilitySnapshot(Dictionary(uniqueKeysWithValues: CapabilityName.allCases.map { ($0, .unsupported) })), evidenceMetadata: evidence)
    }
}
