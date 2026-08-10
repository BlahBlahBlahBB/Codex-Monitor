import Foundation

/// An active runtime identity supplied by a future authorized transport phase.
/// It is data only; this module performs no transport, reduction, or callbacks on rejection.
public struct LiveAdmissionContext: Sendable, Equatable {
    public let descriptor: AdapterDescriptor
    public let ownership: OwnershipRecord
    public let connectionEpoch: ConnectionEpoch
    public init(descriptor: AdapterDescriptor, ownership: OwnershipRecord, connectionEpoch: ConnectionEpoch) {
        self.descriptor = descriptor; self.ownership = ownership; self.connectionEpoch = connectionEpoch
    }
}

public struct LiveAdmittedRuntimeObservation: Sendable, Equatable {
    public let candidate: CandidateRuntimeObservationEnvelope
    fileprivate init(_ candidate: CandidateRuntimeObservationEnvelope) { self.candidate = candidate }
}

public enum AdmissionRejection: Error, Equatable {
    case fixtureOrigin
    case descriptorNotRegistered
    case capabilityNotLiveAuthoritative(CapabilityState)
    case capabilityKindMismatch(required: CapabilityName, supplied: CapabilityName)
    case sourceMismatch
    case adapterMismatch
    case runtimeMismatch
    case accountEpochMismatch
    case connectionEpochMismatch
    case lifecycleEpochMismatch
    case parentIdentityMissing
    case parentIdentityMismatch
    case suppliedIdentitySourceMismatch
    case suppliedIdentityKindMismatch
    case suppliedIdentityShapeMismatch
    case ownershipInconsistent
}

public struct LiveProductAdmissionGate: Sendable {
    private let registry: AdapterRegistry
    public init(registry: AdapterRegistry) { self.registry = registry }

    public func admit(_ candidate: CandidateRuntimeObservationEnvelope, using context: LiveAdmissionContext) -> Result<LiveAdmittedRuntimeObservation, AdmissionRejection> {
        let provenance = candidate.provenance
        guard provenance.origin == .adapter else { return .failure(.fixtureOrigin) }
        guard let registered = registry.descriptor(adapterID: provenance.adapterID, adapterVersion: provenance.adapterVersion, sourceKind: provenance.sourceKind, sourceID: provenance.sourceID) else { return .failure(.descriptorNotRegistered) }
        guard registered == context.descriptor else { return .failure(.adapterMismatch) }
        guard provenance.capability == candidate.kind.requiredCapability else {
            return .failure(.capabilityKindMismatch(required: candidate.kind.requiredCapability, supplied: provenance.capability))
        }
        let state = registered.capabilitySnapshot.state(for: provenance.capability)
        guard state == .liveAuthoritative else { return .failure(.capabilityNotLiveAuthoritative(state)) }
        guard context.ownership.isConsistent(with: context.descriptor) else { return .failure(.ownershipInconsistent) }
        guard provenance.sourceKind == .monitorOwnedRuntime, provenance.sourceID == context.ownership.sourceID else { return .failure(.sourceMismatch) }
        guard provenance.runtimeInstanceID == context.ownership.runtimeInstanceID else { return .failure(.runtimeMismatch) }
        guard provenance.accountEpoch == context.ownership.accountEpoch else { return .failure(.accountEpochMismatch) }
        guard provenance.connectionEpoch == context.connectionEpoch else { return .failure(.connectionEpochMismatch) }
        guard provenance.lifecycleEpoch == context.ownership.lifecycleEpoch else { return .failure(.lifecycleEpochMismatch) }
        let suppliedIDs = [candidate.threadID, candidate.turnID, candidate.itemID].compactMap { $0 }
        guard suppliedIDs.allSatisfy({ $0.sourceID == provenance.sourceID }) else {
            return .failure(.suppliedIdentitySourceMismatch)
        }
        guard (candidate.threadID == nil || candidate.threadID?.entityKind == .thread),
              (candidate.turnID == nil || candidate.turnID?.entityKind == .turn),
              (candidate.itemID == nil || candidate.itemID?.entityKind == .item) else {
            return .failure(.suppliedIdentityKindMismatch)
        }
        guard candidate.kind.acceptsSuppliedIdentityShape(threadID: candidate.threadID, turnID: candidate.turnID, itemID: candidate.itemID) else {
            return .failure(.suppliedIdentityShapeMismatch)
        }
        guard let threadID = candidate.threadID else { return .failure(.parentIdentityMissing) }
        guard threadID == context.ownership.namespacedThreadID else { return .failure(.parentIdentityMismatch) }
        return .success(LiveAdmittedRuntimeObservation(candidate))
    }

    /// The callback is intentionally reachable only through a successful admission result.
    @discardableResult
    public func deliver(_ candidate: CandidateRuntimeObservationEnvelope, using context: LiveAdmissionContext, to productCallback: (LiveAdmittedRuntimeObservation) -> Void) -> Result<LiveAdmittedRuntimeObservation, AdmissionRejection> {
        let result = admit(candidate, using: context)
        if case .success(let admitted) = result { productCallback(admitted) }
        return result
    }
}
