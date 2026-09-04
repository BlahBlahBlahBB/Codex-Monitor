import Foundation

/// Monitor-owned persistence for the approval lifecycle.  It stores only
/// opaque source identities, timestamps, and the log cursor—never a log body,
/// prompt, command, tool output, or resolution text.
public final class ApprovalLifecycleRuntimeOwner: @unchecked Sendable {
    public let adapter: ApprovalLocalAdapter
    private let store: ApprovalLifecycleCheckpointStore
    private var hookJournalCheckpoint: HookApprovalJournalCheckpoint?

    public init(databaseURL: URL, sourceID: ApprovalLocalSourceID, schema: ApprovalLogSchema, store: ApprovalLifecycleCheckpointStore, retryPolicy: ApprovalDBRetryPolicy = .init()) throws {
        self.store = store
        // A lost/corrupt Monitor-owned checkpoint is recoverable only by
        // replaying the immutable Codex source from zero.  Do not make a
        // caller manufacture a potentially stale pending set or go live.
        let checkpoint: ApprovalLifecycleCheckpoint
        do { checkpoint = try store.load() }
        catch ApprovalLifecycleCheckpointStoreError.invalidCheckpoint,
              ApprovalLifecycleCheckpointStoreError.unreadable {
            checkpoint = ApprovalLifecycleCheckpoint(cursor: nil, unresolved: [])
        }
        hookJournalCheckpoint = checkpoint.hookJournal
        adapter = ApprovalLocalAdapter(databaseURL: databaseURL, sourceID: sourceID, schema: schema, lifecycleCheckpoint: checkpoint, retryPolicy: retryPolicy)
    }

    /// The only production poll path commits the durable lifecycle checkpoint
    /// after the adapter's transactional admission point succeeds.
    public func poll() throws -> ApprovalPollResult {
        let result = try adapter.poll()
        try store.save(checkpoint())
        return result
    }

    /// Replays the incremental approval source until two consecutive available
    /// polls report the same cursor.  This proves the bounded reader has
    /// reached its current snapshot; it never treats a single page as an
    /// authoritative restart reconstruction.
    public func catchUpToStable(policy: ApprovalCatchUpPolicy = .init()) throws -> ApprovalCatchUpResult {
        var previousCursor: ApprovalLogCursor?
        var unchangedAvailablePolls = 0
        var lastResult: ApprovalPollResult?

        for pollNumber in 1...policy.maximumPolls {
            let result = try poll()
            lastResult = result
            if result.health.state == .unavailable {
                // A malformed historical row may have advanced the durable
                // cursor.  Continue within the bound so later valid rows can
                // recover; a non-progressing unavailable source is fail-closed.
                guard result.cursor != previousCursor else {
                    throw ApprovalCatchUpError.sourceUnavailable(result.health.reason)
                }
                previousCursor = result.cursor
                unchangedAvailablePolls = 0
                continue
            }
            if result.cursor == previousCursor { unchangedAvailablePolls += 1 }
            else { previousCursor = result.cursor; unchangedAvailablePolls = 0 }
            if unchangedAvailablePolls >= policy.requiredUnchangedAvailablePolls {
                return ApprovalCatchUpResult(polls: pollNumber, cursor: result.cursor, checkpoint: checkpoint())
            }
        }
        if let lastResult, lastResult.health.state == .unavailable {
            throw ApprovalCatchUpError.sourceUnavailable(lastResult.health.reason)
        }
        throw ApprovalCatchUpError.safetyBoundReached
    }

    public func shutdown() { adapter.shutdown() }

    /// The future Hook reader supplies only a sanitized opaque checkpoint here.
    /// This Monitor-side persistence API neither installs nor controls a Hook.
    public func replaceHookJournalCheckpoint(_ value: HookApprovalJournalCheckpoint?) throws {
        hookJournalCheckpoint = value
        try store.save(checkpoint())
    }

    public func checkpoint() -> ApprovalLifecycleCheckpoint {
        let legacy = adapter.lifecycleCheckpoint()
        return ApprovalLifecycleCheckpoint(cursor: legacy.cursor, unresolved: legacy.unresolved, hookJournal: hookJournalCheckpoint)
    }
}

/// Bounded reconciliation policy for first start, checkpoint loss, and
/// pause/resume.  The default accommodates multiple normal SQLite pages while
/// retaining a finite fail-closed upper bound.
public struct ApprovalCatchUpPolicy: Sendable, Equatable {
    public let maximumPolls: Int
    public let requiredUnchangedAvailablePolls: Int
    public init(maximumPolls: Int = 256, requiredUnchangedAvailablePolls: Int = 1) {
        self.maximumPolls = max(2, maximumPolls)
        self.requiredUnchangedAvailablePolls = max(1, requiredUnchangedAvailablePolls)
    }
}

public struct ApprovalCatchUpResult: Sendable, Equatable {
    public let polls: Int
    public let cursor: ApprovalLogCursor?
    public let checkpoint: ApprovalLifecycleCheckpoint
}

public enum ApprovalCatchUpError: Error, Equatable {
    case sourceUnavailable(ApprovalSourceHealthReason?)
    case safetyBoundReached
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
        return ApprovalLifecycleCheckpoint(cursor: cursor, unresolved: unresolved, hookJournal: stored.hookJournal)
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
public enum RuntimeActivityReconciliationAdmission: Sendable, Equatable {
    case establishedProcess
    case requireFreshLiveEvidence
}

public enum LocalRuntimeReconciliationOwner {
    /// Reduces transient desktop rollout IDs through the same keyed contract
    /// used by the Hook writer. A missing session, turn, or resolver yields no
    /// owner; callers must then conservatively avoid Hook attachment.
    public static func derivedHookOwner(snapshot: DesktopThreadSnapshot, hydration: RolloutCheckpointHydration, resolver: (any HookApprovalIdentityResolving)?) -> HookApprovalTurnOwner? {
        guard let resolver, let session = hydration.sessionID, let turn = hydration.activeTurnID?.rawID else { return nil }
        return resolver.owner(sourceRawID: snapshot.threadID.sourceID.rawValue, sessionRawID: session, turnRawID: turn)
    }

    public static func thread(snapshot: DesktopThreadSnapshot, hydration: RolloutCheckpointHydration, approval: ApprovalLifecycleCheckpoint, approvalHealth: ApprovalCapabilityHealth, runtimeSourceAvailable: Bool, observedAt: Date, activityAdmission: RuntimeActivityReconciliationAdmission = .establishedProcess, hookOwner: HookApprovalTurnOwner? = nil, hookSourceHealth: HookApprovalSourceHealthState? = nil) -> RuntimeReconciliationThread {
        let hookCheckpoint = approval.hookJournal
        let hasExactHookSource = hookOwner.map { $0.sourceID == hookCheckpoint?.sourceID } ?? false
        let hookPending = hasExactHookSource ? hookCheckpoint!.unresolved.filter { $0.owner == hookOwner } : []
        // A durable, exact-owner Hook request is authoritative approval
        // evidence. It may retain the rollout's turn through a process
        // boundary, while ordinary historical activity remains suppressed.
        let activeTurnID = activityAdmission == .establishedProcess || !hookPending.isEmpty ? hydration.activeTurnID : nil
        let activeItemCategory = activityAdmission == .establishedProcess ? hydration.activeItemCategory : nil
        let pending = approval.unresolved.filter { $0.threadID == snapshot.threadID && $0.turnID == activeTurnID }
        let effectiveApprovalHealth: ApprovalCapabilityHealth
        if let effectiveHookSourceHealth = hookSourceHealth ?? (hasExactHookSource ? hookCheckpoint?.sourceHealth : nil) {
            switch effectiveHookSourceHealth {
            case .available: effectiveApprovalHealth = hookPending.isEmpty ? .availableKnownNotWaiting : .availableWaiting
            case .unavailable: effectiveApprovalHealth = .unavailable
            case .unknown: effectiveApprovalHealth = .unknown
            }
        } else {
            effectiveApprovalHealth = approvalHealth
        }
        let activity: RuntimeActivityCategory? = switch activeItemCategory {
        case .tool?: .tool
        case .fileChange?: .fileChange
        case .thinking?, .agentResponse?, nil: nil
        }
        let meaningfulAt = RuntimeStateEngine.desktopUpdatedAt(snapshot.updatedAtMilliseconds)
            ?? hydration.terminal?.authoritativeEventAt
            ?? hydration.latestActiveStateAt
            ?? hydration.turnStartedAt
        return RuntimeReconciliationThread(threadID: snapshot.threadID, conversationName: snapshot.conversationName, model: snapshot.model, activeTurnID: activeTurnID, turnStartedAt: activityAdmission == .establishedProcess ? hydration.turnStartedAt : nil, latestActiveState: activityAdmission == .establishedProcess ? hydration.latestActiveState : nil, latestActiveStateAt: activityAdmission == .establishedProcess ? hydration.latestActiveStateAt : nil, activeItemID: activityAdmission == .establishedProcess ? hydration.activeItemID : nil, activeItemCategory: activity, terminal: hydration.terminal, sessionTokenCumulative: hydration.authoritativeTokenTotal ?? snapshot.tokensUsed, sessionTokenProvenance: hydration.authoritativeTokenTotal == nil ? (snapshot.tokensUsed == nil ? nil : .stateDBSeedOrCrosscheck) : .rolloutCumulativeAuthoritative, approvalHealth: effectiveApprovalHealth, unresolvedApprovals: pending, unresolvedHookApprovals: hookPending, hookApprovalOwner: hasExactHookSource ? hookOwner : nil, runtimeSourceAvailable: runtimeSourceAvailable, runtimeObservedAt: observedAt, approvalObservedAt: observedAt, lastMeaningfulActivityAt: meaningfulAt)
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
    /// Opaque binding for this already-selected desktop thread. It never holds
    /// raw Hook session, turn, or tool-use identifiers.
    public let hookApprovalOwner: HookApprovalTurnOwner?
    public init?(threadRawID: String, rolloutCursor: RolloutCursor?, hookApprovalOwner: HookApprovalTurnOwner? = nil) {
        guard !threadRawID.isEmpty else { return nil }
        self.threadRawID = threadRawID; self.rolloutCursor = rolloutCursor; self.hookApprovalOwner = hookApprovalOwner
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
    private let approvalCatchUpPolicy: ApprovalCatchUpPolicy
    /// Aggregate reconciliation diagnostic only; it contains no log content.
    public private(set) var lastApprovalCatchUp: ApprovalCatchUpResult?

    public init(desktop: DesktopLocalAdapter, approvals: ApprovalLifecycleRuntimeOwner, engine: RuntimeStateEngine, approvalCatchUpPolicy: ApprovalCatchUpPolicy = .init()) {
        self.desktop = desktop; self.approvals = approvals; self.engine = engine; self.approvalCatchUpPolicy = approvalCatchUpPolicy
    }

    @discardableResult
    public func install(threadCheckpoints: [LocalRuntimeThreadCheckpoint]) throws -> [RuntimeReconciliationThread] {
        engine.beginReconciliation()
        // Do not install a one-page approval projection.  If catch-up cannot
        // establish a current source snapshot, this throws while the engine
        // remains reconciling/paused rather than fabricating live certainty.
        let approvalCatchUp = try approvals.catchUpToStable(policy: approvalCatchUpPolicy)
        lastApprovalCatchUp = approvalCatchUp
        let approvalCheckpoint = approvalCatchUp.checkpoint
        let approvalHealth: ApprovalCapabilityHealth = .availableKnownNotWaiting
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
            rebuilt.append(LocalRuntimeReconciliationOwner.thread(snapshot: snapshot, hydration: hydration, approval: approvalCheckpoint, approvalHealth: approvalHealth, runtimeSourceAvailable: runtimeAvailable, observedAt: now, activityAdmission: .requireFreshLiveEvidence, hookOwner: checkpoint.hookApprovalOwner))
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
    let hookJournal: HookApprovalJournalCheckpoint?
    init(_ checkpoint: ApprovalLifecycleCheckpoint) {
        cursor = checkpoint.cursor.map { Cursor(device: $0.fileIdentity.device, inode: $0.fileIdentity.inode, lastLogID: $0.lastLogID) }
        unresolved = checkpoint.unresolved.map { Request(sourceID: $0.threadID.sourceID.rawValue, threadID: $0.threadID.rawID, turnID: $0.turnID.rawID, requestID: $0.requestID.rawID, observedAt: $0.observedAt) }
        hookJournal = checkpoint.hookJournal
    }
}
