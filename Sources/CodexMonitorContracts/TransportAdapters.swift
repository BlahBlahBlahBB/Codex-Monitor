import Foundation

/// Shared source-local transport boundary. It deliberately has no operation
/// that can send arbitrary JSON-RPC method names.
public protocol SourceTransportAdapter: Sendable {
    var descriptor: AdapterDescriptor { get }
    func connect() async throws -> SourceHealth
    func close() async -> SourceHealth
}

public actor AccountTransportAdapter: SourceTransportAdapter {
    public nonisolated let descriptor: AdapterDescriptor
    private let client: JSONRPCClient
    private var connectionEpoch: ConnectionEpoch?

    public init(descriptor: AdapterDescriptor, client: JSONRPCClient) {
        self.descriptor = descriptor
        self.client = client
    }

    public func connect() async throws -> SourceHealth {
        connectionEpoch = try await client.connect()
        return health(.connected)
    }

    public func close() async -> SourceHealth {
        await client.close()
        return health(.closed)
    }

    /// H2 validates the account lane's transport boundary only. H4 owns
    /// account/rateLimit/usage decoding and account-product semantics.
    public func verifyAccountReadRoute() async throws -> SanitizedDiagnostic {
        _ = try await client.request(method: "account/read")
        return DiagnosticSanitizer.summarize(sourceKind: .account, code: "accountReadResponseDiscarded", method: "account/read")
    }

    private func health(_ state: SourceHealthState) -> SourceHealth {
        let now = Date()
        let provenance = Provenance(sourceID: descriptor.sourceID, sourceKind: .account, adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, observationMode: .snapshot, authority: .unavailable, observedAt: now, freshness: Freshness(state: state == .connected ? .fresh : .unknown, assessedAt: now, observedAt: now), connectionEpoch: connectionEpoch, capability: .accountReturnedFields, evidence: descriptor.evidenceMetadata, origin: .adapter)!
        return SourceHealth(provenance: provenance, state: state)!
    }
}

public actor MonitorOwnedRuntimeTransportAdapter: SourceTransportAdapter {
    public nonisolated let descriptor: AdapterDescriptor
    private let client: JSONRPCClient
    private let runtimeInstanceID: RuntimeInstanceID
    private let lifecycleEpoch: LifecycleEpoch
    private let accountEpoch: AccountEpoch?
    private var connectionEpoch: ConnectionEpoch?
    private var notificationContinuation: AsyncStream<CandidateRuntimeObservationEnvelope>.Continuation?
    public nonisolated let observations: AsyncStream<CandidateRuntimeObservationEnvelope>

    public init(descriptor: AdapterDescriptor, client: JSONRPCClient, runtimeInstanceID: RuntimeInstanceID, lifecycleEpoch: LifecycleEpoch, accountEpoch: AccountEpoch?) {
        self.descriptor = descriptor
        self.client = client
        self.runtimeInstanceID = runtimeInstanceID
        self.lifecycleEpoch = lifecycleEpoch
        self.accountEpoch = accountEpoch
        var continuation: AsyncStream<CandidateRuntimeObservationEnvelope>.Continuation?
        self.observations = AsyncStream { continuation = $0 }
        self.notificationContinuation = continuation
    }

    public func connect() async throws -> SourceHealth {
        connectionEpoch = try await client.connect()
        await client.setNotificationHandler { [weak self] notification in
            await self?.route(notification)
        }
        return health(.connected)
    }

    public func close() async -> SourceHealth {
        await client.close()
        return health(.closed)
    }

    /// Only observed success-lifecycle notification names are decoded. The
    /// result remains a candidate with its H1 capability; this adapter never
    /// promotes it or invokes the H3 reducer.
    public func route(_ notification: JSONRPCNotification) {
        guard let kind = Self.observedKinds[notification.method], let connectionEpoch else { return }
        let params = notification.params?.objectValue ?? [:]
        let threadID = Self.identity("threadId", kind: .thread, sourceID: descriptor.sourceID, params: params)
        let turnID = Self.identity("turnId", kind: .turn, sourceID: descriptor.sourceID, params: params)
        let itemID = Self.identity("itemId", kind: .item, sourceID: descriptor.sourceID, params: params)
        let itemKind = params["itemKind"]?.stringValue.flatMap(RuntimeItemKind.init(rawValue:))
        let opaqueStatus = notification.method == "thread/status/changed" ? params["status"]?.stringValue : nil
        let now = Date()
        let provenance = Provenance(sourceID: descriptor.sourceID, sourceKind: .monitorOwnedRuntime, adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, runtimeInstanceID: runtimeInstanceID, observationMode: .live, authority: .partial, observedAt: now, freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now), accountEpoch: accountEpoch, connectionEpoch: connectionEpoch, lifecycleEpoch: lifecycleEpoch, capability: kind.requiredCapability, evidence: descriptor.evidenceMetadata, origin: .adapter)!
        guard let candidate = CandidateRuntimeObservationEnvelope(provenance: provenance, kind: kind, threadID: threadID, turnID: turnID, itemID: itemID, itemKind: itemKind, opaqueStatus: opaqueStatus) else { return }
        notificationContinuation?.yield(candidate)
    }

    public func diagnostic(for notification: JSONRPCNotification) -> SanitizedDiagnostic {
        DiagnosticSanitizer.summarize(sourceKind: .monitorOwnedRuntime, code: "unsupportedNotification", method: notification.method, payload: notification.params, transport: TransportProvenance(kind: .unixSocketWebSocket))
    }

    private func health(_ state: SourceHealthState) -> SourceHealth {
        let now = Date()
        let provenance = Provenance(sourceID: descriptor.sourceID, sourceKind: .monitorOwnedRuntime, adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, runtimeInstanceID: runtimeInstanceID, observationMode: .live, authority: .unavailable, observedAt: now, freshness: Freshness(state: state == .connected ? .fresh : .unknown, assessedAt: now, observedAt: now), accountEpoch: accountEpoch, connectionEpoch: connectionEpoch ?? ConnectionEpoch("connection-unavailable")!, lifecycleEpoch: lifecycleEpoch, capability: .ownedRuntimeProvenance, evidence: descriptor.evidenceMetadata, origin: .adapter)!
        return SourceHealth(provenance: provenance, state: state)!
    }

    private static let observedKinds: [String: RuntimeObservationKind] = [
        "thread/started": .threadStarted,
        "thread/status/changed": .threadStatusChanged,
        "turn/started": .turnStarted,
        "item/started": .itemStarted,
        "item/completed": .itemCompleted,
        "turn/completed": .turnCompletedSuccess,
        "thread/tokenUsage/updated": .threadTokenUsageUpdated
    ]

    private static func identity(_ key: String, kind: EntityKind, sourceID: SourceID, params: [String: JSONValue]) -> NamespacedID? {
        guard let raw = params[key]?.stringValue else { return nil }
        return NamespacedID(sourceID: sourceID, entityKind: kind, rawID: raw)
    }
}

public actor DesktopSnapshotTransportAdapter: SourceTransportAdapter {
    public nonisolated let descriptor: AdapterDescriptor
    private let client: JSONRPCClient
    private var connectionEpoch: ConnectionEpoch?

    public init(descriptor: AdapterDescriptor, client: JSONRPCClient) {
        self.descriptor = descriptor
        self.client = client
    }

    public func connect() async throws -> SourceHealth {
        connectionEpoch = try await client.connect()
        return health(.connected)
    }

    public func close() async -> SourceHealth {
        await client.close()
        return health(.closed)
    }

    /// H2's only Desktop calls are static read operations. This type contains
    /// no resume/start/fork or notification API, so it cannot manufacture an
    /// observer or emit realtime Desktop state.
    public func loadedList() async throws -> SnapshotSummary { try await readSnapshot(operation: .loadedList, params: nil) }
    public func list() async throws -> SnapshotSummary { try await readSnapshot(operation: .list, params: nil) }
    public func read(threadID: NamespacedID) async throws -> SnapshotSummary {
        guard threadID.sourceID == descriptor.sourceID, threadID.entityKind == .thread else { throw DesktopTransportError.foreignThreadIdentity }
        return try await readSnapshot(operation: .read, params: .object(["threadId": .string(threadID.rawID), "includeTurns": .bool(true)]))
    }

    private func readSnapshot(operation: DesktopReadOperation, params: JSONValue?) async throws -> SnapshotSummary {
        let result = try await client.request(method: operation.method, params: params)
        let fields = result.objectValue ?? [:]
        let now = Date()
        let provenance = Provenance(sourceID: descriptor.sourceID, sourceKind: .desktopSnapshot, adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, observationMode: .snapshot, authority: .partial, observedAt: now, freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now), connectionEpoch: connectionEpoch, capability: .desktopSummaryHistoryRead, evidence: descriptor.evidenceMetadata, origin: .adapter)!
        return try SnapshotSummary(provenance: provenance, readAt: now, rawStatus: fields["status"]?.stringValue, titleAvailability: fields["title"] == nil ? .unknown : .available, previewAvailability: fields["preview"] == nil ? .unknown : .available, historyAvailability: operation == .read ? .available : .unknown, sourceClassification: .unclassified, staleness: provenance.freshness)
    }

    private func health(_ state: SourceHealthState) -> SourceHealth {
        let now = Date()
        let provenance = Provenance(sourceID: descriptor.sourceID, sourceKind: .desktopSnapshot, adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, observationMode: .snapshot, authority: .unavailable, observedAt: now, freshness: Freshness(state: state == .connected ? .fresh : .unknown, assessedAt: now, observedAt: now), connectionEpoch: connectionEpoch, capability: .desktopSummaryHistoryRead, evidence: descriptor.evidenceMetadata, origin: .adapter)!
        return SourceHealth(provenance: provenance, state: state)!
    }

}

/// Exhaustive allow-list: no Desktop start/resume/fork/write/lifecycle case is
/// representable by the H2 snapshot adapter.
public enum DesktopReadOperation: String, CaseIterable, Sendable {
    case loadedList = "thread/loaded/list"
    case list = "thread/list"
    case read = "thread/read"
    var method: String { rawValue }
}

public enum DesktopTransportError: Error, Sendable, Equatable {
    case foreignThreadIdentity
}
