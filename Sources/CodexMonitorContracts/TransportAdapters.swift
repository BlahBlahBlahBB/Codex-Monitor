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

    /// The only creation path that can yield a receipt.  It invokes the
    /// authorized Monitor-owned `thread/start` operation and validates the
    /// authoritative returned Thread before producing an opaque result.
    func performAuthorizedThreadCreation() async throws -> AuthorizedThreadCreationResult {
        let result = try await client.request(method: "thread/start", params: .object(["ephemeral": .bool(true)]))
        guard let thread = result.objectValue?["thread"]?.objectValue,
              Pinned0147DTOValidator.thread(thread),
              let rawID = thread["id"]?.stringValue,
              let threadID = NamespacedID(sourceID: descriptor.sourceID, entityKind: .thread, rawID: rawID) else {
            throw RuntimeSupervisorError.unauthorizedCreationResult
        }
        return AuthorizedThreadCreationResult(threadID: threadID, operationToken: UUID())
    }

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
    /// Faithful, pinned-0.147.0 DTO validation boundary.  We retain only the
    /// identifiers after this point, but validate the complete required
    /// structure (including tagged items) before accepting wire data.
    private static func schemaThreadID(_ value: JSONValue?) -> String? {
        guard let object = value?.objectValue, Pinned0147DTOValidator.thread(object) else { return nil }
        return object["id"]?.stringValue
    }
    private static func schemaTurnID(_ value: JSONValue?) -> String? {
        guard let object = value?.objectValue, Pinned0147DTOValidator.turn(object) else { return nil }
        return object["id"]?.stringValue
    }
    private static func schemaItemID(_ value: JSONValue?) -> String? {
        guard let object = value?.objectValue, Pinned0147DTOValidator.threadItem(object) else { return nil }
        return object["id"]?.stringValue
    }
    private static func schemaTokenUsage(_ value: JSONValue?) -> Bool {
        guard let usage = value?.objectValue else { return false }
        return Pinned0147DTOValidator.tokenUsage(usage)
    }
}

/// Hand-written generated-equivalent validator for the finite DTO surface H2
/// consumes.  It is deliberately stricter than selected-field presence checks:
/// every required object/array/scalar, enum and ThreadItem tagged variant is
/// validated before any normalized event can be created.
enum Pinned0147DTOValidator {
    private static let turnStatuses: Set<String> = ["completed", "interrupted", "failed", "inProgress"]
    private static let commandStatuses: Set<String> = ["inProgress", "completed", "failed", "declined"]
    private static let threadStatusTypes: Set<String> = ["notLoaded", "idle", "systemError", "active"]
    private static let sessionSources: Set<String> = ["cli", "vscode", "exec", "appServer", "unknown"]
    private static let requiredItems: [String: Set<String>] = [
        "userMessage": ["content", "id", "type"], "hookPrompt": ["fragments", "id", "type"],
        "agentMessage": ["id", "text", "type"], "plan": ["id", "text", "type"],
        "reasoning": ["id", "type"], "commandExecution": ["command", "commandActions", "cwd", "id", "status", "type"],
        "fileChange": ["changes", "id", "status", "type"], "mcpToolCall": ["arguments", "id", "server", "status", "tool", "type"],
        "dynamicToolCall": ["arguments", "id", "status", "tool", "type"],
        "collabAgentToolCall": ["agentsStates", "id", "receiverThreadIds", "senderThreadId", "status", "tool", "type"],
        "subAgentActivity": ["agentPath", "agentThreadId", "id", "kind", "type"], "webSearch": ["id", "query", "type"],
        "imageView": ["id", "path", "type"], "sleep": ["durationMs", "id", "type"],
        "imageGeneration": ["id", "result", "status", "type"], "enteredReviewMode": ["id", "review", "type"],
        "exitedReviewMode": ["id", "review", "type"], "contextCompaction": ["id", "type"]
    ]

    static func thread(_ object: [String: JSONValue]) -> Bool {
        let required = ["cliVersion", "createdAt", "cwd", "ephemeral", "id", "modelProvider", "preview", "sessionId", "source", "status", "turns", "updatedAt"]
        guard required.allSatisfy({ object[$0] != nil }), object["cliVersion"]?.stringValue != nil,
              object["createdAt"]?.integerValue != nil, object["cwd"]?.stringValue != nil,
              bool(object["ephemeral"]), object["id"]?.stringValue != nil, object["modelProvider"]?.stringValue != nil,
              object["preview"]?.stringValue != nil, object["sessionId"]?.stringValue != nil,
              sessionSource(object["source"]), threadStatus(object["status"]), object["updatedAt"]?.integerValue != nil,
              let turns = array(object["turns"]) else { return false }
        return turns.allSatisfy { $0.objectValue.map(turn) ?? false }
    }

    static func turn(_ object: [String: JSONValue]) -> Bool {
        guard object["id"]?.stringValue != nil, let status = object["status"]?.stringValue, turnStatuses.contains(status),
              let items = array(object["items"]), items.allSatisfy({ $0.objectValue.map(threadItem) ?? false }) else { return false }
        for name in ["completedAt", "durationMs", "startedAt"] { if let value = object[name], !integerOrNull(value) { return false } }
        if let view = object["itemsView"]?.stringValue, view != "full" && view != "summary" { return false }
        return true
    }

    static func threadItem(_ object: [String: JSONValue]) -> Bool {
        guard let type = object["type"]?.stringValue, let required = requiredItems[type], required.allSatisfy({ object[$0] != nil }), object["id"]?.stringValue != nil else { return false }
        switch type {
        case "userMessage": return array(object["content"]) != nil
        case "hookPrompt": return array(object["fragments"]) != nil
        case "agentMessage", "plan": return object["text"]?.stringValue != nil
        case "reasoning": return optionalStringArray(object["content"]) && optionalStringArray(object["summary"])
        case "commandExecution":
            guard object["command"]?.stringValue != nil, array(object["commandActions"])?.allSatisfy(commandAction) == true,
                  object["cwd"]?.stringValue != nil, let status = object["status"]?.stringValue, commandStatuses.contains(status) else { return false }
            return optionalIntegerOrNull(object["durationMs"]) && optionalIntegerOrNull(object["exitCode"])
        case "fileChange": return array(object["changes"]) != nil && object["status"]?.stringValue != nil
        case "mcpToolCall": return object["server"]?.stringValue != nil && object["tool"]?.stringValue != nil && object["status"]?.stringValue != nil
        case "dynamicToolCall": return object["tool"]?.stringValue != nil && object["status"]?.stringValue != nil
        case "collabAgentToolCall": return object["agentsStates"]?.objectValue != nil && array(object["receiverThreadIds"])?.allSatisfy({ $0.stringValue != nil }) == true && object["senderThreadId"]?.stringValue != nil && object["status"]?.stringValue != nil && object["tool"]?.stringValue != nil
        case "subAgentActivity": return object["agentPath"]?.stringValue != nil && object["agentThreadId"]?.stringValue != nil && object["kind"]?.stringValue != nil
        case "webSearch": return object["query"]?.stringValue != nil
        case "imageView": return object["path"]?.stringValue != nil
        case "sleep": return object["durationMs"]?.integerValue != nil
        case "imageGeneration": return object["result"]?.stringValue != nil && object["status"]?.stringValue != nil
        case "enteredReviewMode", "exitedReviewMode": return object["review"]?.stringValue != nil
        case "contextCompaction": return true
        default: return false
        }
    }

    static func tokenUsage(_ object: [String: JSONValue]) -> Bool {
        guard let last = object["last"]?.objectValue, let total = object["total"]?.objectValue else { return false }
        let required = ["cachedInputTokens", "inputTokens", "outputTokens", "reasoningOutputTokens", "totalTokens"]
        return required.allSatisfy { last[$0]?.integerValue != nil && total[$0]?.integerValue != nil }
    }

    private static func threadStatus(_ value: JSONValue?) -> Bool {
        guard let value = value?.objectValue, let type = value["type"]?.stringValue, threadStatusTypes.contains(type) else { return false }
        return type != "active" || array(value["activeFlags"])?.allSatisfy({ $0.stringValue == "waitingOnApproval" || $0.stringValue == "waitingOnUserInput" }) == true
    }
    private static func sessionSource(_ value: JSONValue?) -> Bool {
        if let source = value?.stringValue { return sessionSources.contains(source) }
        guard let object = value?.objectValue else { return false }
        if object.count == 1, object["custom"]?.stringValue != nil { return true }
        return object.count == 1 && object["subAgent"]?.objectValue != nil
    }
    private static func commandAction(_ value: JSONValue) -> Bool {
        guard let object = value.objectValue, let type = object["type"]?.stringValue, object["command"]?.stringValue != nil else { return false }
        switch type { case "read": return object["name"]?.stringValue != nil && object["path"]?.stringValue != nil; case "listFiles": return optionalStringOrNull(object["path"]); case "search": return optionalStringOrNull(object["path"]) && optionalStringOrNull(object["query"]); case "unknown": return true; default: return false }
    }
    private static func array(_ value: JSONValue?) -> [JSONValue]? { guard case .array(let values) = value else { return nil }; return values }
    private static func bool(_ value: JSONValue?) -> Bool { if case .bool = value { return true }; return false }
    private static func integerOrNull(_ value: JSONValue) -> Bool { value.integerValue != nil || value == .null }
    private static func optionalIntegerOrNull(_ value: JSONValue?) -> Bool { value.map(integerOrNull) ?? true }
    private static func optionalStringOrNull(_ value: JSONValue?) -> Bool { value.map { $0.stringValue != nil || $0 == .null } ?? true }
    private static func optionalStringArray(_ value: JSONValue?) -> Bool { array(value)?.allSatisfy({ $0.stringValue != nil }) ?? (value == nil) }
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
