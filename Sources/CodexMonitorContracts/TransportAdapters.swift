import Foundation

public enum TransportAdapterError: Error, Sendable, Equatable { case laneMismatch, clientBindingMismatch }

public protocol SourceTransportAdapter: Sendable {
    var descriptor: AdapterDescriptor { get }
    func connect() async throws -> SourceHealth
    func close() async -> SourceHealth
}

private func matches(_ descriptor: AdapterDescriptor, _ binding: JSONRPCClientBinding, runtimeInstanceID: RuntimeInstanceID? = nil, accountEpoch: AccountEpoch? = nil, lifecycleEpoch: LifecycleEpoch? = nil) -> Bool {
    binding.sourceID == descriptor.sourceID && binding.sourceKind == descriptor.sourceKind && binding.adapterID == descriptor.adapterID && binding.adapterVersion == descriptor.adapterVersion && binding.runtimeInstanceID == runtimeInstanceID && binding.accountEpoch == accountEpoch && binding.lifecycleEpoch == lifecycleEpoch
}

public actor AccountTransportAdapter: SourceTransportAdapter {
    public nonisolated let descriptor: AdapterDescriptor; private let client: JSONRPCClient; private let lease = JSONRPCAdapterLease(); private var connectionEpoch: ConnectionEpoch?
    public init(descriptor: AdapterDescriptor, client: JSONRPCClient) throws {
        guard descriptor.sourceKind == .account else { throw TransportAdapterError.laneMismatch }
        guard matches(descriptor, client.binding) else { throw TransportAdapterError.clientBindingMismatch }
        self.descriptor = descriptor; self.client = client
    }
    public func connect() async throws -> SourceHealth { try await client.installNotificationHandler(owner: lease) { _, _ in }; connectionEpoch = try await client.connect(); return health(.connected) }
    public func close() async -> SourceHealth { await client.close(); return health(.closed) }
    public func verifyAccountReadRoute() async throws -> SanitizedDiagnostic {
        _ = try await client.request(method: SanitizedMethod.accountRead.rawValue)
        return DiagnosticSanitizer.summarize(sourceKind: .account, code: .accountReadResponseDiscarded, method: .accountRead)
    }
    private func health(_ state: SourceHealthState) -> SourceHealth {
        let now = Date()
        let provenance = Provenance(sourceID: descriptor.sourceID, sourceKind: .account, adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, observationMode: .snapshot, authority: .unavailable, observedAt: now, freshness: Freshness(state: state == .connected ? .fresh : .unknown, assessedAt: now, observedAt: now), connectionEpoch: connectionEpoch, capability: .accountReturnedFields, evidence: descriptor.evidenceMetadata, origin: .adapter)!
        return SourceHealth(provenance: provenance, state: state)!
    }
}

public actor MonitorOwnedRuntimeTransportAdapter: SourceTransportAdapter {
    public nonisolated let descriptor: AdapterDescriptor
    private let client: JSONRPCClient; private let lease = JSONRPCAdapterLease(); private let runtimeInstanceID: RuntimeInstanceID; private let lifecycleEpoch: LifecycleEpoch; private let accountEpoch: AccountEpoch?
    private var connectionEpoch: ConnectionEpoch?; private var ownershipByThread: [NamespacedID: OwnershipRecord] = [:]
    private var notificationContinuation: AsyncStream<CandidateRuntimeObservationEnvelope>.Continuation?
    public nonisolated let observations: AsyncStream<CandidateRuntimeObservationEnvelope>

    public init(descriptor: AdapterDescriptor, client: JSONRPCClient, runtimeInstanceID: RuntimeInstanceID, lifecycleEpoch: LifecycleEpoch, accountEpoch: AccountEpoch?) throws {
        guard descriptor.sourceKind == .monitorOwnedRuntime else { throw TransportAdapterError.laneMismatch }
        guard matches(descriptor, client.binding, runtimeInstanceID: runtimeInstanceID, accountEpoch: accountEpoch, lifecycleEpoch: lifecycleEpoch) else { throw TransportAdapterError.clientBindingMismatch }
        self.descriptor = descriptor; self.client = client; self.runtimeInstanceID = runtimeInstanceID; self.lifecycleEpoch = lifecycleEpoch; self.accountEpoch = accountEpoch
        var continuation: AsyncStream<CandidateRuntimeObservationEnvelope>.Continuation?
        self.observations = AsyncStream { continuation = $0 }; self.notificationContinuation = continuation
    }

    public func connect() async throws -> SourceHealth {
        try await client.installNotificationHandler(owner: lease) { [weak self] notification, context in _ = await self?.route(notification, context: context) }
        connectionEpoch = try await client.connect(); return health(.connected)
    }
    public func close() async -> SourceHealth { await client.close(); return health(.closed) }
    public func currentConnectionContext() async -> ConnectionContext? { await client.currentConnectionContext() }
    func lifecycleEpochValue() -> LifecycleEpoch { lifecycleEpoch }
    func accountEpochValue() -> AccountEpoch? { accountEpoch }
    func recordOwnership(_ record: OwnershipRecord) { ownershipByThread[record.namespacedThreadID] = record }

    /// Pinned 0.147.0 layouts have deliberately different parent locations per
    /// notification. Do not normalize them by guessing a nested `thread.id`.
    @discardableResult public func route(_ notification: JSONRPCNotification, context: ConnectionContext) -> Bool {
        guard connectionEpoch == context.epoch, matches(descriptor, context.binding, runtimeInstanceID: runtimeInstanceID, accountEpoch: accountEpoch, lifecycleEpoch: lifecycleEpoch), let kind = Self.observedKinds[notification.method], let decoded = RuntimeLifecycleWireEvent.decode(notification: notification, kind: kind, sourceID: descriptor.sourceID) else { return false }
        guard let record = ownershipByThread[decoded.threadID], record.isConsistent(with: descriptor), record.runtimeInstanceID == runtimeInstanceID, record.lifecycleEpoch == lifecycleEpoch, record.accountEpoch == accountEpoch else { return false }
        let now = Date()
        let provenance = Provenance(sourceID: descriptor.sourceID, sourceKind: .monitorOwnedRuntime, adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, runtimeInstanceID: runtimeInstanceID, observationMode: .live, authority: .partial, observedAt: now, freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now), accountEpoch: accountEpoch, connectionEpoch: context.epoch, lifecycleEpoch: lifecycleEpoch, capability: kind.requiredCapability, evidence: descriptor.evidenceMetadata, origin: .adapter)!
        guard let candidate = CandidateRuntimeObservationEnvelope(provenance: provenance, kind: kind, threadID: decoded.threadID, turnID: decoded.turnID, itemID: decoded.itemID, itemKind: decoded.itemKind, opaqueStatus: decoded.opaqueStatus), kind.acceptsSuppliedIdentityShape(threadID: decoded.threadID, turnID: decoded.turnID, itemID: decoded.itemID) else { return false }
        notificationContinuation?.yield(candidate)
        return true
    }

    public func diagnostic(for notification: JSONRPCNotification) -> SanitizedDiagnostic {
        let method = SanitizedMethod(rawValue: notification.method)
        return DiagnosticSanitizer.summarize(sourceKind: .monitorOwnedRuntime, code: method == nil ? .unsupportedNotification : .malformedMessage, method: method, payload: notification.params, transport: TransportProvenance(kind: .unixSocketWebSocket))
    }
    private func health(_ state: SourceHealthState) -> SourceHealth {
        let now = Date()
        let provenance = Provenance(sourceID: descriptor.sourceID, sourceKind: .monitorOwnedRuntime, adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, runtimeInstanceID: runtimeInstanceID, observationMode: .live, authority: .unavailable, observedAt: now, freshness: Freshness(state: state == .connected ? .fresh : .unknown, assessedAt: now, observedAt: now), accountEpoch: accountEpoch, connectionEpoch: connectionEpoch ?? ConnectionEpoch("connection-unavailable")!, lifecycleEpoch: lifecycleEpoch, capability: .ownedRuntimeProvenance, evidence: descriptor.evidenceMetadata, origin: .adapter)!
        return SourceHealth(provenance: provenance, state: state)!
    }
    private static let observedKinds: [String: RuntimeObservationKind] = ["thread/started": .threadStarted, "thread/status/changed": .threadStatusChanged, "turn/started": .turnStarted, "item/started": .itemStarted, "item/completed": .itemCompleted, "turn/completed": .turnCompletedSuccess, "thread/tokenUsage/updated": .threadTokenUsageUpdated]
}

struct RuntimeLifecycleWireEvent {
    let threadID: NamespacedID; let turnID: NamespacedID?; let itemID: NamespacedID?; let itemKind: RuntimeItemKind?; let opaqueStatus: String?
    static func decode(notification: JSONRPCNotification, kind: RuntimeObservationKind, sourceID: SourceID) -> Self? {
        guard let params = notification.params?.objectValue else { return nil }
        let thread: String?
        switch kind {
        case .threadStarted: thread = schemaThreadID(params["thread"])
        case .threadStatusChanged, .turnStarted, .itemStarted, .itemCompleted, .turnCompletedSuccess, .threadTokenUsageUpdated: thread = params["threadId"]?.stringValue
        }
        guard let thread, let threadID = NamespacedID(sourceID: sourceID, entityKind: .thread, rawID: thread) else { return nil }
        let turn: String?
        switch kind {
        case .turnStarted, .turnCompletedSuccess: turn = schemaTurnID(params["turn"])
        case .itemStarted, .itemCompleted, .threadTokenUsageUpdated: turn = params["turnId"]?.stringValue
        default: turn = nil
        }
        let item = schemaItemID(params["item"])
        let turnID = turn.flatMap { NamespacedID(sourceID: sourceID, entityKind: .turn, rawID: $0) }
        let itemID = item.flatMap { NamespacedID(sourceID: sourceID, entityKind: .item, rawID: $0) }
        let itemKind = params["item"]?.objectValue?["type"]?.stringValue.flatMap(RuntimeItemKind.init(rawValue:))
        let status = params["status"]?.objectValue?["type"]?.stringValue
        switch kind {
        case .threadStarted: guard schemaThreadID(params["thread"]) != nil, turnID == nil && itemID == nil else { return nil }
        case .threadTokenUsageUpdated: guard turnID != nil && itemID == nil && schemaTokenUsage(params["tokenUsage"]) else { return nil }
        case .threadStatusChanged: guard turnID == nil && itemID == nil && status != nil else { return nil }
        case .turnStarted: guard turnID != nil && itemID == nil else { return nil }
        case .itemStarted: guard turnID != nil && itemID != nil && itemKind != nil && params["startedAtMs"]?.integerValue != nil else { return nil }
        case .itemCompleted: guard turnID != nil && itemID != nil && itemKind != nil && params["completedAtMs"]?.integerValue != nil else { return nil }
        case .turnCompletedSuccess:
            guard turnID != nil, itemID == nil, params["turn"]?.objectValue?["status"]?.stringValue == "completed" else { return nil }
        }
        return Self(threadID: threadID, turnID: turnID, itemID: itemID, itemKind: itemKind, opaqueStatus: status)
    }
    /// Required fields from generated 0.147.0 `Thread`. We retain only the id,
    /// but reject abbreviated hand-written thread shapes.
    private static func schemaThreadID(_ value: JSONValue?) -> String? {
        guard let object = value?.objectValue,
              ["cliVersion", "createdAt", "cwd", "ephemeral", "id", "modelProvider", "preview", "sessionId", "source", "status", "turns", "updatedAt"].allSatisfy({ object[$0] != nil }),
              object["id"]?.stringValue != nil, object["cliVersion"]?.stringValue != nil, object["createdAt"]?.integerValue != nil,
              object["ephemeral"] != nil, object["modelProvider"]?.stringValue != nil, object["preview"]?.stringValue != nil,
              object["sessionId"]?.stringValue != nil, object["turns"] != nil, object["updatedAt"]?.integerValue != nil else { return nil }
        return object["id"]?.stringValue
    }
    private static func schemaTurnID(_ value: JSONValue?) -> String? {
        guard let object = value?.objectValue, object["id"]?.stringValue != nil, object["status"]?.stringValue != nil, object["items"] != nil else { return nil }
        return object["id"]?.stringValue
    }
    private static func schemaItemID(_ value: JSONValue?) -> String? {
        guard let object = value?.objectValue, object["id"]?.stringValue != nil, object["type"]?.stringValue != nil else { return nil }
        return object["id"]?.stringValue
    }
    private static func schemaTokenUsage(_ value: JSONValue?) -> Bool {
        guard let usage = value?.objectValue, let last = usage["last"]?.objectValue, let total = usage["total"]?.objectValue else { return false }
        let required = ["cachedInputTokens", "inputTokens", "outputTokens", "reasoningOutputTokens", "totalTokens"]
        return required.allSatisfy { last[$0]?.integerValue != nil && total[$0]?.integerValue != nil }
    }
}

public actor DesktopSnapshotTransportAdapter: SourceTransportAdapter {
    public nonisolated let descriptor: AdapterDescriptor; private let client: JSONRPCClient; private let lease = JSONRPCAdapterLease(); private var connectionEpoch: ConnectionEpoch?
    public init(descriptor: AdapterDescriptor, client: JSONRPCClient) throws {
        guard descriptor.sourceKind == .desktopSnapshot else { throw TransportAdapterError.laneMismatch }
        guard matches(descriptor, client.binding) else { throw TransportAdapterError.clientBindingMismatch }
        self.descriptor = descriptor; self.client = client
    }
    public func connect() async throws -> SourceHealth { try await client.installNotificationHandler(owner: lease) { _, _ in }; connectionEpoch = try await client.connect(); return health(.connected) }
    public func close() async -> SourceHealth { await client.close(); return health(.closed) }
    public func loadedList() async throws -> SnapshotSummary { try await readSnapshot(operation: .loadedList, params: nil) }
    public func list() async throws -> SnapshotSummary { try await readSnapshot(operation: .list, params: nil) }
    public func read(threadID: NamespacedID) async throws -> SnapshotSummary { guard threadID.sourceID == descriptor.sourceID, threadID.entityKind == .thread else { throw DesktopTransportError.foreignThreadIdentity }; return try await readSnapshot(operation: .read, params: .object(["threadId": .string(threadID.rawID), "includeTurns": .bool(true)])) }
    private func readSnapshot(operation: DesktopReadOperation, params: JSONValue?) async throws -> SnapshotSummary {
        let result = try await client.request(method: operation.method, params: params); let fields = result.objectValue ?? [:]; let now = Date()
        let provenance = Provenance(sourceID: descriptor.sourceID, sourceKind: .desktopSnapshot, adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, observationMode: .snapshot, authority: .partial, observedAt: now, freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now), connectionEpoch: connectionEpoch, capability: .desktopSummaryHistoryRead, evidence: descriptor.evidenceMetadata, origin: .adapter)!
        return try SnapshotSummary(provenance: provenance, readAt: now, rawStatus: fields["status"]?.stringValue, titleAvailability: fields["title"] == nil ? .unknown : .available, previewAvailability: fields["preview"] == nil ? .unknown : .available, historyAvailability: operation == .read ? .available : .unknown, sourceClassification: .unclassified, staleness: provenance.freshness)
    }
    private func health(_ state: SourceHealthState) -> SourceHealth { let now = Date(); let provenance = Provenance(sourceID: descriptor.sourceID, sourceKind: .desktopSnapshot, adapterID: descriptor.adapterID, adapterVersion: descriptor.adapterVersion, observationMode: .snapshot, authority: .unavailable, observedAt: now, freshness: Freshness(state: state == .connected ? .fresh : .unknown, assessedAt: now, observedAt: now), connectionEpoch: connectionEpoch, capability: .desktopSummaryHistoryRead, evidence: descriptor.evidenceMetadata, origin: .adapter)!; return SourceHealth(provenance: provenance, state: state)! }
}

public enum DesktopReadOperation: String, CaseIterable, Sendable { case loadedList = "thread/loaded/list", list = "thread/list", read = "thread/read"; var method: String { rawValue } }
public enum DesktopTransportError: Error, Sendable, Equatable { case foreignThreadIdentity }
