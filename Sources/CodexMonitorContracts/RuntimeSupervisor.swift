import Foundation

/// This initializer is internal: only an authorized Monitor-owned thread
/// creation boundary in this module may mint a receipt. H2 does not implement
/// that creation operation.
public struct MonitorCreatedThreadReceipt: Sendable, Equatable {
    public let threadID: NamespacedID
    public let creationProvenance: Provenance
    init(threadID: NamespacedID, creationProvenance: Provenance) { self.threadID = threadID; self.creationProvenance = creationProvenance }
}

/// Placeholder boundary for the separately authorized future creation action.
/// It exposes no start/resume/fork/kill/restart/terminate operation in H2.
enum MonitorOwnedThreadCreationBoundary {
    static func issue(threadID: NamespacedID, provenance: Provenance) -> MonitorCreatedThreadReceipt { MonitorCreatedThreadReceipt(threadID: threadID, creationProvenance: provenance) }
}

public enum RuntimeSupervisorError: Error, Sendable, Equatable {
    case desktopOrForeignThreadRejected, invalidCreationProvenance, duplicateOwnedThread, lifecycleNotConnected, staleReceipt
}

/// Monitor-owned lifecycle bookkeeping only. Reconnect produces a new transport
/// context; it never reconstructs active runtime state or retains process handles.
public actor MonitorOwnedRuntimeSupervisor {
    private let adapter: MonitorOwnedRuntimeTransportAdapter
    private var ownershipByThread: [NamespacedID: OwnershipRecord] = [:]
    private var latestHealth: SourceHealth?

    public init(adapter: MonitorOwnedRuntimeTransportAdapter) { self.adapter = adapter }
    public func connectTransport() async throws -> SourceHealth { let health = try await adapter.connect(); latestHealth = health; return health }
    public func closeTransport() async -> SourceHealth { let health = await adapter.close(); latestHealth = health; return health }

    public func register(_ receipt: MonitorCreatedThreadReceipt) async throws -> OwnershipRecord {
        guard latestHealth?.state == .connected, let context = await adapter.currentConnectionContext() else { throw RuntimeSupervisorError.lifecycleNotConnected }
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
}
