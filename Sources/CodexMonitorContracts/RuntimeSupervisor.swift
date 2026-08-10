import Foundation

/// This initializer is internal: only an authorized Monitor-owned thread
/// creation boundary in this module may mint a receipt. H2 does not implement
/// that creation operation.
public struct MonitorCreatedThreadReceipt: Sendable, Equatable {
    public let threadID: NamespacedID
    public let creationProvenance: Provenance
    fileprivate let issuanceToken: UUID
    fileprivate init(threadID: NamespacedID, creationProvenance: Provenance, issuanceToken: UUID) { self.threadID = threadID; self.creationProvenance = creationProvenance; self.issuanceToken = issuanceToken }
}

/// Issuance state is kept by the boundary, not derivable from receipt fields.
/// This boundary represents the authorized creation-operation result; it does
/// not expose any Desktop or process lifecycle operation in H2.
actor MonitorOwnedThreadCreationBoundary {
    private var issuances: [UUID: Provenance] = [:]
    func issueAuthorizedCreationResult(threadID: NamespacedID, provenance: Provenance) -> MonitorCreatedThreadReceipt {
        let token = UUID(); issuances[token] = provenance
        return MonitorCreatedThreadReceipt(threadID: threadID, creationProvenance: provenance, issuanceToken: token)
    }
    func validates(_ receipt: MonitorCreatedThreadReceipt, current: ConnectionContext) -> Bool {
        guard let issued = issuances[receipt.issuanceToken] else { return false }
        return issued == receipt.creationProvenance && issued.connectionEpoch == current.epoch && issued.sourceID == current.binding.sourceID && issued.runtimeInstanceID == current.binding.runtimeInstanceID && issued.accountEpoch == current.binding.accountEpoch && issued.lifecycleEpoch == current.binding.lifecycleEpoch
    }
}

public enum RuntimeSupervisorError: Error, Sendable, Equatable {
    case desktopOrForeignThreadRejected, invalidCreationProvenance, duplicateOwnedThread, lifecycleNotConnected, staleReceipt, forgedReceipt
}

/// Monitor-owned lifecycle bookkeeping only. Reconnect produces a new transport
/// context; it never reconstructs active runtime state or retains process handles.
public actor MonitorOwnedRuntimeSupervisor {
    private let adapter: MonitorOwnedRuntimeTransportAdapter
    private var ownershipByThread: [NamespacedID: OwnershipRecord] = [:]
    private var latestHealth: SourceHealth?
    private let creationBoundary = MonitorOwnedThreadCreationBoundary()

    public init(adapter: MonitorOwnedRuntimeTransportAdapter) { self.adapter = adapter }
    public func connectTransport() async throws -> SourceHealth { let health = try await adapter.connect(); latestHealth = health; return health }
    public func closeTransport() async -> SourceHealth { let health = await adapter.close(); latestHealth = health; return health }

    public func register(_ receipt: MonitorCreatedThreadReceipt) async throws -> OwnershipRecord {
        guard latestHealth?.state == .connected, let context = await adapter.currentConnectionContext() else { throw RuntimeSupervisorError.lifecycleNotConnected }
        guard await creationBoundary.validates(receipt, current: context) else { throw RuntimeSupervisorError.forgedReceipt }
        let descriptor = adapter.descriptor; let provenance = receipt.creationProvenance
        guard receipt.threadID.sourceID == descriptor.sourceID, receipt.threadID.entityKind == .thread,
              provenance.sourceKind == .monitorOwnedRuntime, provenance.sourceID == descriptor.sourceID,
              provenance.adapterID == descriptor.adapterID, provenance.adapterVersion == descriptor.adapterVersion,
              provenance.runtimeInstanceID == context.binding.runtimeInstanceID,
              provenance.connectionEpoch == context.epoch, provenance.lifecycleEpoch != nil,
              provenance.origin == .adapter, provenance.observationMode == .live,
              provenance.authority == .partial else { throw RuntimeSupervisorError.invalidCreationProvenance }
        let currentLifecycle = await lifecycleEpoch()
        let currentAccount = await accountEpoch()
        guard provenance.lifecycleEpoch == currentLifecycle, provenance.accountEpoch == currentAccount else { throw RuntimeSupervisorError.staleReceipt }
        guard ownershipByThread[receipt.threadID] == nil else { throw RuntimeSupervisorError.duplicateOwnedThread }
        let record = OwnershipRecord(sourceID: descriptor.sourceID, runtimeInstanceID: provenance.runtimeInstanceID!, namespacedThreadID: receipt.threadID, creationProvenance: provenance, accountEpoch: provenance.accountEpoch, lifecycleEpoch: provenance.lifecycleEpoch!)
        ownershipByThread[receipt.threadID] = record
        await adapter.recordOwnership(record)
        return record
    }

    private func lifecycleEpoch() async -> LifecycleEpoch? { await adapter.lifecycleEpochValue() }
    private func accountEpoch() async -> AccountEpoch? { await adapter.accountEpochValue() }
    public func ownership(for threadID: NamespacedID) -> OwnershipRecord? { ownershipByThread[threadID] }
    public func sourceHealth() -> SourceHealth? { latestHealth }

    /// Internal bridge used only by the separately authorized Monitor-owned
    /// creation operation. It derives all provenance from the current connected
    /// adapter context, so a caller cannot mint a receipt from matching fields.
    func receiveAuthorizedCreationResult(threadID: NamespacedID) async throws -> MonitorCreatedThreadReceipt {
        guard latestHealth?.state == .connected, let context = await adapter.currentConnectionContext() else { throw RuntimeSupervisorError.lifecycleNotConnected }
        let descriptor = adapter.descriptor; let now = Date()
        guard let provenance = Provenance(sourceID: descriptor.sourceID, sourceKind: .monitorOwnedRuntime, adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, runtimeInstanceID: context.binding.runtimeInstanceID, observationMode: .live, authority: .partial, observedAt: now, freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now), accountEpoch: context.binding.accountEpoch, connectionEpoch: context.epoch, lifecycleEpoch: context.binding.lifecycleEpoch, capability: .threadStartObservation, evidence: descriptor.evidenceMetadata, origin: .adapter) else { throw RuntimeSupervisorError.invalidCreationProvenance }
        return await creationBoundary.issueAuthorizedCreationResult(threadID: threadID, provenance: provenance)
    }
}
