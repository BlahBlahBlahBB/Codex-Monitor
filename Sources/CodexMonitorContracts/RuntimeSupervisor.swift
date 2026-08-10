import Foundation

/// A receipt is supplied only after Monitor intentionally creates a runtime
/// Thread through a separately authorized future operation. H2 does not issue
/// that operation; it records and validates the ownership boundary.
public struct MonitorCreatedThreadReceipt: Sendable, Equatable {
    public let threadID: NamespacedID
    public let creationProvenance: Provenance

    public init(threadID: NamespacedID, creationProvenance: Provenance) {
        self.threadID = threadID
        self.creationProvenance = creationProvenance
    }
}

public enum RuntimeSupervisorError: Error, Sendable, Equatable {
    case desktopOrForeignThreadRejected
    case invalidCreationProvenance
    case duplicateOwnedThread
    case lifecycleNotConnected
}

/// Monitor-owned lifecycle bookkeeping only. It has no reducer, no terminal
/// state, no UI retention, and no active runtime reconstruction. A reconnect
/// simply receives a new connection epoch from the adapter.
public actor MonitorOwnedRuntimeSupervisor {
    private let adapter: MonitorOwnedRuntimeTransportAdapter
    private var ownershipByThread: [NamespacedID: OwnershipRecord] = [:]
    private var latestHealth: SourceHealth?

    public init(adapter: MonitorOwnedRuntimeTransportAdapter) { self.adapter = adapter }

    public func connectTransport() async throws -> SourceHealth {
        let health = try await adapter.connect()
        latestHealth = health
        return health
    }

    public func closeTransport() async -> SourceHealth {
        let health = await adapter.close()
        latestHealth = health
        return health
    }

    public func register(_ receipt: MonitorCreatedThreadReceipt) async throws -> OwnershipRecord {
        let descriptor = adapter.descriptor
        let provenance = receipt.creationProvenance
        guard receipt.threadID.sourceID == descriptor.sourceID,
              receipt.threadID.entityKind == .thread,
              provenance.sourceKind == .monitorOwnedRuntime,
              provenance.sourceID == descriptor.sourceID,
              provenance.adapterID == descriptor.adapterID,
              provenance.adapterVersion == descriptor.adapterVersion,
              provenance.runtimeInstanceID != nil,
              provenance.lifecycleEpoch != nil else {
            throw RuntimeSupervisorError.desktopOrForeignThreadRejected
        }
        guard provenance.origin == .adapter,
              provenance.observationMode == .live,
              provenance.runtimeInstanceID != nil,
              provenance.lifecycleEpoch != nil else {
            throw RuntimeSupervisorError.invalidCreationProvenance
        }
        guard ownershipByThread[receipt.threadID] == nil else { throw RuntimeSupervisorError.duplicateOwnedThread }
        let record = OwnershipRecord(sourceID: descriptor.sourceID, runtimeInstanceID: provenance.runtimeInstanceID!, namespacedThreadID: receipt.threadID, creationProvenance: provenance, accountEpoch: provenance.accountEpoch, lifecycleEpoch: provenance.lifecycleEpoch!)
        ownershipByThread[receipt.threadID] = record
        return record
    }

    public func ownership(for threadID: NamespacedID) -> OwnershipRecord? { ownershipByThread[threadID] }
    public func sourceHealth() -> SourceHealth? { latestHealth }
}
