import Foundation

/// Monitor-owned persistence for the approval lifecycle.  It stores only
/// opaque source identities, timestamps, and the log cursor—never a log body,
/// prompt, command, tool output, or resolution text.
public final class ApprovalLifecycleRuntimeOwner: @unchecked Sendable {
    public let adapter: ApprovalLocalAdapter
    private let store: ApprovalLifecycleCheckpointStore

    public init(databaseURL: URL, sourceID: ApprovalLocalSourceID, schema: ApprovalLogSchema, store: ApprovalLifecycleCheckpointStore, retryPolicy: ApprovalDBRetryPolicy = .init()) throws {
        self.store = store
        adapter = ApprovalLocalAdapter(databaseURL: databaseURL, sourceID: sourceID, schema: schema, lifecycleCheckpoint: try store.load(), retryPolicy: retryPolicy)
    }

    /// The only production poll path commits the durable lifecycle checkpoint
    /// after the adapter's transactional admission point succeeds.
    public func poll() throws -> ApprovalPollResult {
        let result = try adapter.poll()
        try store.save(adapter.lifecycleCheckpoint())
        return result
    }

    public func shutdown() { adapter.shutdown() }
}

public enum ApprovalLifecycleCheckpointStoreError: Error, Equatable { case unreadable, invalidCheckpoint, writeFailed }

public final class ApprovalLifecycleCheckpointStore: @unchecked Sendable {
    private let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> ApprovalLifecycleCheckpoint {
        guard FileManager.default.fileExists(atPath: url.path) else { return ApprovalLifecycleCheckpoint(cursor: nil, unresolved: []) }
        guard let stored = try? JSONDecoder().decode(StoredApprovalCheckpoint.self, from: Data(contentsOf: url)) else { throw ApprovalLifecycleCheckpointStoreError.invalidCheckpoint }
        let cursor = stored.cursor.flatMap { value -> ApprovalLogCursor? in
            guard value.lastLogID >= 0 else { return nil }
            return ApprovalLogCursor(fileIdentity: FileIdentity(device: value.device, inode: value.inode), lastLogID: value.lastLogID)
        }
        if stored.cursor != nil && cursor == nil { throw ApprovalLifecycleCheckpointStoreError.invalidCheckpoint }
        let unresolved = try stored.unresolved.map { value -> ApprovalRequested in
            guard let source = SourceID(value.sourceID),
                  let thread = NamespacedID(sourceID: source, entityKind: .thread, rawID: value.threadID),
                  let turn = NamespacedID(sourceID: source, entityKind: .turn, rawID: value.turnID),
                  let request = NamespacedID(sourceID: source, entityKind: .item, rawID: value.requestID) else { throw ApprovalLifecycleCheckpointStoreError.invalidCheckpoint }
            return ApprovalRequested(threadID: thread, turnID: turn, requestID: request, observedAt: value.observedAt)
        }
        return ApprovalLifecycleCheckpoint(cursor: cursor, unresolved: unresolved)
    }

    public func save(_ checkpoint: ApprovalLifecycleCheckpoint) throws {
        let stored = StoredApprovalCheckpoint(checkpoint)
        do {
            let data = try JSONEncoder().encode(stored)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch { throw ApprovalLifecycleCheckpointStoreError.writeFailed }
    }
}

/// Converts the exact checkpoint-hydration result emitted by the rollout
/// reader into the sole reducer reconciliation input.  In particular a State
/// DB token seed cannot replace its rollout-authoritative cumulative value.
public enum LocalRuntimeReconciliationOwner {
    public static func thread(snapshot: DesktopThreadSnapshot, hydration: RolloutCheckpointHydration, approval: ApprovalLifecycleCheckpoint, approvalHealth: ApprovalCapabilityHealth, runtimeSourceAvailable: Bool, observedAt: Date) -> RuntimeReconciliationThread {
        let pending = approval.unresolved.filter { $0.threadID == snapshot.threadID && $0.turnID == hydration.activeTurnID }
        let activity: RuntimeActivityCategory? = switch hydration.activeItemCategory {
        case .tool?: .tool
        case .fileChange?: .fileChange
        case .thinking?, .agentResponse?, nil: nil
        }
        return RuntimeReconciliationThread(threadID: snapshot.threadID, title: snapshot.title, model: snapshot.model, activeTurnID: hydration.activeTurnID, turnStartedAt: hydration.turnStartedAt, latestActiveState: hydration.latestActiveState, latestActiveStateAt: hydration.latestActiveStateAt, activeItemID: hydration.activeItemID, activeItemCategory: activity, terminal: hydration.terminal, sessionTokenCumulative: hydration.authoritativeTokenTotal ?? snapshot.tokensUsed, sessionTokenProvenance: hydration.authoritativeTokenTotal == nil ? (snapshot.tokensUsed == nil ? nil : .stateDBSeedOrCrosscheck) : .rolloutCumulativeAuthoritative, approvalHealth: approvalHealth, unresolvedApprovals: pending, runtimeSourceAvailable: runtimeSourceAvailable, runtimeObservedAt: observedAt, approvalObservedAt: observedAt)
    }

    /// Startup/pause owners call this exactly once after all selected local
    /// sources have been exact-revalidated.  It never exposes a live reducer
    /// before the complete reconstructed set is installed.
    public static func install(_ values: [RuntimeReconciliationThread], into engine: RuntimeStateEngine) {
        engine.beginReconciliation()
        engine.installReconciliation(values)
    }
}

/// Monitor-owned restart/pause input.  The rollout cursor is created only by
/// the local reader and is passed back to that same reader for exact descriptor
/// and session revalidation; it contains no rollout content.
public struct LocalRuntimeThreadCheckpoint: Sendable, Equatable {
    public let threadRawID: String
    public let rolloutCursor: RolloutCursor?
    public init?(threadRawID: String, rolloutCursor: RolloutCursor?) {
        guard !threadRawID.isEmpty else { return nil }
        self.threadRawID = threadRawID; self.rolloutCursor = rolloutCursor
    }
}

/// The sole production installation path for a restart or pause/resume.  It
/// reads each local source itself, derives closed reconciliation values from
/// reader hydration and durable approval lifecycle state, then atomically
/// enters the reducer.  Callers never manufacture `RuntimeReconciliationThread`
/// values from test or UI state.
public final class LocalRuntimeReconciliationInstaller: @unchecked Sendable {
    private let desktop: DesktopLocalAdapter
    private let approvals: ApprovalLifecycleRuntimeOwner
    private let engine: RuntimeStateEngine

    public init(desktop: DesktopLocalAdapter, approvals: ApprovalLifecycleRuntimeOwner, engine: RuntimeStateEngine) {
        self.desktop = desktop; self.approvals = approvals; self.engine = engine
    }

    @discardableResult
    public func install(threadCheckpoints: [LocalRuntimeThreadCheckpoint]) throws -> [RuntimeReconciliationThread] {
        engine.beginReconciliation()
        let approvalPoll = try approvals.poll()
        let approvalCheckpoint = approvals.adapter.lifecycleCheckpoint()
        let approvalHealth: ApprovalCapabilityHealth = approvalPoll.health.state == .available ? .availableKnownNotWaiting : .unavailable
        let now = Date()
        var rebuilt: [RuntimeReconciliationThread] = []
        for checkpoint in threadCheckpoints {
            let snapshot = try desktop.open(threadRawID: checkpoint.threadRawID, checkpoint: checkpoint.rolloutCursor)
            let result = try desktop.poll(threadID: snapshot.threadID)
            guard result.invalidation == nil else { continue }
            let hydration = result.hydration ?? RolloutCheckpointHydration(activeTurnID: nil, turnStartedAt: nil, activeItemID: nil, activeItemCategory: nil, latestActiveState: nil, latestActiveStateAt: nil, terminal: nil, authoritativeTokenTotal: nil)
            let runtimeAvailable = result.observations.contains { observation in
                if case .sourceHealth(let health) = observation { return health.state == .available }
                return false
            }
            rebuilt.append(LocalRuntimeReconciliationOwner.thread(snapshot: snapshot, hydration: hydration, approval: approvalCheckpoint, approvalHealth: approvalHealth, runtimeSourceAvailable: runtimeAvailable, observedAt: now))
        }
        engine.installReconciliation(rebuilt)
        return rebuilt
    }
}

private struct StoredApprovalCheckpoint: Codable {
    struct Cursor: Codable { let device: UInt64; let inode: UInt64; let lastLogID: Int64 }
    struct Request: Codable { let sourceID: String; let threadID: String; let turnID: String; let requestID: String; let observedAt: Date }
    let cursor: Cursor?
    let unresolved: [Request]
    init(_ checkpoint: ApprovalLifecycleCheckpoint) {
        cursor = checkpoint.cursor.map { Cursor(device: $0.fileIdentity.device, inode: $0.fileIdentity.inode, lastLogID: $0.lastLogID) }
        unresolved = checkpoint.unresolved.map { Request(sourceID: $0.threadID.sourceID.rawValue, threadID: $0.threadID.rawID, turnID: $0.turnID.rawID, requestID: $0.requestID.rawID, observedAt: $0.observedAt) }
    }
}
