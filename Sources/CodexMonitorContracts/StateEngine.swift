import Foundation

/// Frozen presentation-domain states. The raw values are the approved product
/// vocabulary; capability uncertainty is carried separately and never folded
/// into a fabricated lifecycle state.
public enum MonitorRuntimeState: String, CaseIterable, Sendable, Equatable {
    case disconnected = "DISCONNECTED", paused = "PAUSED", idle = "IDLE"
    case thinking = "THINKING", working = "WORKING", waitingApproval = "WAITING_APPROVAL"
    case completed = "COMPLETED", failed = "FAILED", interrupted = "INTERRUPTED", systemError = "SYSTEM_ERROR"
}

public enum RuntimeActivityCategory: String, CaseIterable, Sendable, Equatable {
    case thinking, tool, fileChange, agentResponse, waitingApproval, completed, failed, interrupted, systemError, idle, disconnected
    public var shortSafeLabel: String { rawValue }
}

/// Three-valued approval capability. A pending request remains visible when
/// the log source is lost; consumers can distinguish it from known not waiting.
public enum ApprovalCapabilityHealth: String, Sendable, Equatable {
    case unknown = "UNKNOWN"
    case availableKnownNotWaiting = "AVAILABLE_KNOWN_NOT_WAITING"
    case availableWaiting = "AVAILABLE_WAITING"
    case unavailable = "UNAVAILABLE"
    case stale = "STALE"
}

/// Privacy-bounded live Accessibility evidence. Structured logs correlate a
/// request; only this value can prove that approval controls are on screen.
public enum ApprovalUIPresence: String, Sendable, Equatable {
    case unknown = "UNKNOWN", notWaiting = "NOT_WAITING", waiting = "WAITING"
    case permissionRequired = "PERMISSION_REQUIRED", unavailable = "UNAVAILABLE"
}

public struct ApprovalUIObservation: Sendable, Equatable {
    public let presence: ApprovalUIPresence
    public let observedAt: Date
    public init(presence: ApprovalUIPresence, observedAt: Date) {
        self.presence = presence; self.observedAt = observedAt
    }
}

public enum SessionTokenProvenance: String, Sendable, Equatable {
    case rolloutCumulativeAuthoritative = "ROLLOUT_CUMULATIVE"
    case stateDBSeedOrCrosscheck = "STATE_DB_SEED_CROSSCHECK"
}

public protocol StateEngineClock: Sendable { func now() -> Date }
public struct SystemStateEngineClock: StateEngineClock { public init() {}; public func now() -> Date { Date() } }

public struct ThreadRuntimeSnapshot: Sendable, Equatable {
    public let threadID: NamespacedID
    /// The active turn is the only runtime-session attribution exposed by the
    /// reducer. It is absent when no exact local turn is active; consumers
    /// must not infer or manufacture one from a thread title or status.
    public let activeTurnID: NamespacedID?
    public let conversationName: String?
    public let model: String?
    public let state: MonitorRuntimeState
    public let stateSince: Date
    public let turnRuntimeStartedAt: Date?
    public let sessionTokenCumulative: Int64?
    public let sessionTokenProvenance: SessionTokenProvenance?
    public let sessionTokenAvailable: Bool
    public let sourceFreshness: Freshness
    public let approvalHealth: ApprovalCapabilityHealth
    public let approvalFreshness: Freshness
    /// A bounded request-only signal. It never asserts an ongoing wait or a
    /// resolved approval lifecycle.
    public let approvalRequestObserved: Bool
    /// Presentation-only attention gate derived from exact pending approval
    /// evidence and each Hook request's source-classified reviewer.
    public let userAttentionRequired: Bool
    public let currentActivityCategory: RuntimeActivityCategory
}

public struct GlobalRuntimeSnapshot: Sendable, Equatable {
    public let state: MonitorRuntimeState
    public let stateSince: Date
    public let representativeThreadID: NamespacedID?
    public let currentActivityCategory: RuntimeActivityCategory
    public let currentActivityShortSafeLabel: String
    public let sourceFreshness: Freshness
    public let activeThreadCount: Int
    public let waitingApprovalCount: Int
    /// Secondary information for the representative thread; never main state.
    public let approvalRequestObserved: Bool
    public let representativeThread: ThreadRuntimeSnapshot?
    public let threads: [ThreadRuntimeSnapshot]

    public var userAttentionRequired: Bool { representativeThread?.userAttentionRequired ?? false }
}

public enum MonitoringPausePhase: Sendable, Equatable { case live, paused, reconciling }

/// Explicit terminal source identity required for restart/reconciliation.
public struct ReconciledTerminal: Sendable, Equatable {
    public let turnID: NamespacedID
    public let eventID: String
    public let state: MonitorRuntimeState
    public let authoritativeEventAt: Date
    public init?(turnID: NamespacedID, eventID: String, state: MonitorRuntimeState, authoritativeEventAt: Date) {
        guard [.completed, .failed, .interrupted, .systemError].contains(state), !eventID.isEmpty else { return nil }
        self.turnID = turnID; self.eventID = eventID; self.state = state; self.authoritativeEventAt = authoritativeEventAt
    }
}

/// A closed reducer input obtained only after exact local-source revalidation.
/// Installation replaces all records in one operation while presentation is
/// PAUSED/STALE, so live state never leaks between old and rebuilt reducers.
public struct RuntimeReconciliationThread: Sendable, Equatable {
    public let threadID: NamespacedID
    public let conversationName: String?
    public let model: String?
    public let activeTurnID: NamespacedID?
    public let turnStartedAt: Date?
    public let latestActiveState: MonitorRuntimeState?
    public let latestActiveStateAt: Date?
    public let activeItemID: NamespacedID?
    public let activeItemCategory: RuntimeActivityCategory?
    public let terminal: ReconciledTerminal?
    public let sessionTokenCumulative: Int64?
    public let sessionTokenProvenance: SessionTokenProvenance?
    public let approvalHealth: ApprovalCapabilityHealth
    public let unresolvedApprovals: [ApprovalRequested]
    /// Sanitized opaque Hook evidence. It is intentionally separate from the
    /// legacy local-log request shape and has no raw Hook identifiers.
    public let unresolvedHookApprovals: [HookApprovalPendingEvidence]
    public let hookApprovalOwner: HookApprovalTurnOwner?
    public let runtimeSourceAvailable: Bool
    public let runtimeObservedAt: Date
    public let approvalObservedAt: Date
    /// Authoritative thread/task activity, deliberately separate from source
    /// freshness so an idle representative cannot be reordered by heartbeats.
    public let lastMeaningfulActivityAt: Date?

    public init(threadID: NamespacedID, conversationName: String? = nil, model: String? = nil, activeTurnID: NamespacedID?, turnStartedAt: Date?, latestActiveState: MonitorRuntimeState?, latestActiveStateAt: Date?, activeItemID: NamespacedID? = nil, activeItemCategory: RuntimeActivityCategory? = nil, terminal: ReconciledTerminal? = nil, sessionTokenCumulative: Int64? = nil, sessionTokenProvenance: SessionTokenProvenance? = nil, approvalHealth: ApprovalCapabilityHealth, unresolvedApprovals: [ApprovalRequested], unresolvedHookApprovals: [HookApprovalPendingEvidence] = [], hookApprovalOwner: HookApprovalTurnOwner? = nil, runtimeSourceAvailable: Bool, runtimeObservedAt: Date, approvalObservedAt: Date, lastMeaningfulActivityAt: Date? = nil) {
        self.threadID = threadID; self.conversationName = conversationName; self.model = model; self.activeTurnID = activeTurnID
        self.turnStartedAt = turnStartedAt; self.latestActiveState = latestActiveState; self.latestActiveStateAt = latestActiveStateAt
        self.activeItemID = activeItemID; self.activeItemCategory = activeItemCategory; self.terminal = terminal
        self.sessionTokenCumulative = sessionTokenCumulative; self.sessionTokenProvenance = sessionTokenProvenance
        self.approvalHealth = approvalHealth; self.unresolvedApprovals = unresolvedApprovals
        self.unresolvedHookApprovals = unresolvedHookApprovals; self.hookApprovalOwner = hookApprovalOwner
        self.runtimeSourceAvailable = runtimeSourceAvailable; self.runtimeObservedAt = runtimeObservedAt; self.approvalObservedAt = approvalObservedAt
        self.lastMeaningfulActivityAt = lastMeaningfulActivityAt
    }
}

public final class RuntimeStateEngine: @unchecked Sendable {
    private let clock: any StateEngineClock
    private var records: [NamespacedID: ThreadRecord] = [:]
    private var pausePhase: MonitoringPausePhase
    private var pauseSince: Date?
    /// Source-wide log health also applies to a thread first discovered after
    /// loss; otherwise that thread could be incorrectly born "known healthy".
    private var defaultApprovalHealth: ApprovalCapabilityHealth = .availableKnownNotWaiting
    /// Hook health is source-scoped. A Hook turn binding starts unknown until
    /// the sanitized journal supplies actual health or lifecycle evidence.
    private var hookApprovalHealthBySource: [HookOpaqueIdentity: HookApprovalSourceHealthState] = [:]
    private var approvalUIPresence: ApprovalUIPresence = .unknown
    private var approvalUIObservedAt: Date?

    /// A fresh Monitor has no authoritative runtime projection until local
    /// sources have been reconciled.  Production therefore starts paused;
    /// `initialPhase: .live` exists only for an already-reconciled host.
    public init(clock: any StateEngineClock = SystemStateEngineClock(), initialPhase: MonitoringPausePhase = .reconciling) {
        self.clock = clock; self.pausePhase = initialPhase
        self.pauseSince = initialPhase == .live ? nil : clock.now()
    }

    /// State DB is metadata/token seed only. It cannot clear a runtime-owner
    /// latch and cannot replace an admitted rollout cumulative token value.
    public func register(_ snapshot: DesktopThreadSnapshot, sourceHealthAvailable: Bool = true, observedAt: Date? = nil) {
        guard pausePhase == .live else { return }
        let now = observedAt ?? clock.now()
        var record = record(for: snapshot.threadID, at: now)
        record.conversationName = safeConversationName(snapshot.conversationName); record.model = snapshot.model
        if let updatedAt = Self.desktopUpdatedAt(snapshot.updatedAtMilliseconds) {
            record.lastMeaningfulActivityAt = latest(record.lastMeaningfulActivityAt, updatedAt)
        }
        if let tokens = snapshot.tokensUsed, record.tokenProvenance != .rolloutCumulativeAuthoritative {
            record.tokens = max(record.tokens ?? tokens, tokens)
            record.tokenProvenance = .stateDBSeedOrCrosscheck
        }
        if !sourceHealthAvailable { record.runtimeSourceAvailable = false; record.runtimeObservedAt = now }
        records[snapshot.threadID] = record
    }

    /// A conversation title may be presented only when the current desktop
    /// metadata cycle could authoritatively read it.
    public func clearConversationNames() {
        for id in records.keys {
            var record = records[id]!
            record.conversationName = nil
            records[id] = record
        }
    }

    public func ingest(_ observation: DesktopObservation) {
        guard pausePhase == .live else { return }
        switch observation {
        case .rollout(let rollout): ingest(rollout)
        case .sourceHealth(let health): ingest(health)
        case .capabilityUnavailable(let threadID, let capability):
            var record = record(for: threadID, at: clock.now())
            switch capability {
            case .sessionToken: record.sessionTokenAvailable = false
            case .stateDatabase, .rolloutFormat, .rolloutSessionIdentity:
                record.runtimeSourceAvailable = false; record.runtimeObservedAt = clock.now()
            }
            records[threadID] = record
        }
    }

    public func ingest(_ rollout: RolloutRecordEnvelope) {
        guard pausePhase == .live else { return }
        var record = record(for: rollout.threadID, at: rollout.observedAt)
        // A buffered rollout record is activity evidence, not renewed exact
        // ownership. It must never restore a newer ownership-unavailable latch.
        if let model = rollout.model { record.model = model }
        if let tokens = rollout.tokenSnapshot?.totalTokens {
            record.tokens = max(record.tokens ?? tokens, tokens)
            record.tokenProvenance = .rolloutCumulativeAuthoritative
            record.sessionTokenAvailable = true
        }
        switch rollout.kind {
        case .taskStarted:
            guard let turnID = rollout.turnID else { records[rollout.threadID] = record; return }
            let at = rollout.authoritativeEventAt ?? rollout.observedAt
            record.activeTurnID = turnID; record.turnStartedAt = at
            record.lastActiveState = .thinking; record.lastActiveStateAt = at
            record.lastMeaningfulActivityAt = latest(record.lastMeaningfulActivityAt, at)
            record.lastActivity = .thinking; record.activeItemID = nil; record.activeItemCategory = nil
            record.terminal = nil; record.pendingApprovals.removeAll(); record.hookPendingApprovals.removeAll(); record.hookApprovalOwner = nil; record.approvalRequestObservedAt = nil
            if record.approvalHealth != .unavailable && record.approvalHealth != .unknown { record.approvalHealth = .availableKnownNotWaiting }
        case .activity:
            guard rollout.turnID == record.activeTurnID else { records[rollout.threadID] = record; return }
            let at = rollout.authoritativeEventAt ?? rollout.observedAt
            record.lastMeaningfulActivityAt = latest(record.lastMeaningfulActivityAt, at)
            switch rollout.activity {
            case .tool?, .fileChange?:
                record.activeItemID = rollout.itemID
                record.activeItemCategory = rollout.activity == .tool ? .tool : .fileChange
                record.lastActiveState = .working; record.lastActiveStateAt = at; record.lastActivity = record.activeItemCategory ?? .tool
            case .thinking?:
                // A reasoning event from a different/unknown item cannot end
                // an exact active tool/file call.
                guard record.activeItemID == nil || rollout.itemID == record.activeItemID else { break }
                record.lastActiveState = .thinking; record.lastActiveStateAt = at; record.lastActivity = .thinking
            case .agentResponse?:
                if let item = rollout.itemID, item == record.activeItemID {
                    record.activeItemID = nil; record.activeItemCategory = nil
                    record.lastActiveState = .thinking; record.lastActiveStateAt = at; record.lastActivity = .thinking
                } else if record.activeItemID == nil { record.lastActivity = .agentResponse }
            case nil: break
            }
        case .taskCompletedSuccess, .taskCompletedFailure, .turnAbortedInterrupted:
            guard let terminal = terminal(from: rollout), acceptLiveTerminal(terminal, record: record) else { records[rollout.threadID] = record; return }
            installTerminal(terminal, into: &record)
        case .tokenCount, .turnContext, .sessionMeta: break
        }
        records[rollout.threadID] = record
    }

    public func ingest(_ health: DesktopSourceHealth) {
        guard pausePhase == .live else { return }
        var record = record(for: health.threadID, at: clock.now())
        // Only exact owner/source revalidation is allowed to restore runtime.
        record.runtimeSourceAvailable = health.state == .available
        record.runtimeObservedAt = clock.now()
        records[health.threadID] = record
    }

    public func ingest(_ approval: ApprovalObservation) {
        guard pausePhase == .live else { return }
        switch approval {
        case .requested(let request):
            var record = record(for: request.threadID, at: request.observedAt)
            guard record.activeTurnID == request.turnID else { return }
            // A request is authoritative waiting evidence for this exact
            // active turn. Resolution remains intentionally conservative.
            record.pendingApprovals[request.requestID] = PendingApproval(request: request)
            record.approvalRequestObservedAt = request.observedAt
            record.approvalHealth = .availableWaiting; record.approvalObservedAt = request.observedAt
            records[request.threadID] = record
        case .resolved(let resolution):
            // Do not synthesize Approved/Declined/Cancelled in V1.
            _ = resolution
        case .sourceHealth(let health): updateApprovalHealth(health)
        case .sourceUnavailable(let health): updateApprovalHealth(health)
        }
    }

    /// Establishes a memory-only correspondence between an already-active
    /// runtime turn and its opaque Hook owner. No raw Hook identifier is
    /// accepted here, and a Hook event cannot create a runtime turn by itself.
    public func bindHookApprovalOwner(_ owner: HookApprovalTurnOwner, to threadID: NamespacedID, turnID: NamespacedID, observedAt: Date? = nil) {
        guard pausePhase == .live else { return }
        let at = observedAt ?? clock.now()
        guard var record = records[threadID], record.activeTurnID == turnID,
              !records.values.contains(where: { $0.threadID != threadID && $0.activeTurnID != nil && $0.hookApprovalOwner == owner }) else { return }
        // Bootstrap may already have restored durable evidence for this exact
        // owner. Rebinding the same proven owner must not erase it before a
        // new journal record can be replayed; only a changed owner invalidates
        // the prior turn's pending evidence.
        if record.hookApprovalOwner != owner { record.hookPendingApprovals.removeAll() }
        record.hookApprovalOwner = owner
        record.approvalObservedAt = at
        updateHookApprovalHealth(for: owner.sourceID, record: &record)
        records[threadID] = record
    }

    /// Applies sanitized Hook lifecycle evidence. PostToolUse resolves only a
    /// sole unresolved request in the exact bound source/session/turn; with
    /// multiple requests it intentionally does nothing rather than guessing.
    public func ingest(_ event: HookApprovalEvent) {
        guard pausePhase == .live else { return }
        switch event {
        case .permissionRequest(let value):
            guard let threadID = boundThread(for: value.owner), var record = records[threadID] else { return }
            hookApprovalHealthBySource[value.owner.sourceID] = .available
            record.hookPendingApprovals[value.journalEventID] = PendingHookApproval(event: value)
            record.approvalRequestObservedAt = value.observedAt; record.approvalObservedAt = value.observedAt
            record.approvalHealth = .availableWaiting
            records[threadID] = record
        case .postToolUse(let value):
            guard let threadID = boundThread(for: value.owner), var record = records[threadID] else { return }
            hookApprovalHealthBySource[value.owner.sourceID] = .available
            if record.hookPendingApprovals.count == 1, let key = record.hookPendingApprovals.keys.first {
                record.hookPendingApprovals.removeValue(forKey: key)
            }
            record.approvalObservedAt = value.observedAt
            updateHookApprovalHealth(for: value.owner.sourceID, record: &record)
            records[threadID] = record
        case .stop(let value):
            guard let threadID = boundThread(for: value.owner), var record = records[threadID] else { return }
            hookApprovalHealthBySource[value.owner.sourceID] = .available
            record.hookPendingApprovals.removeAll()
            record.approvalObservedAt = value.observedAt
            updateHookApprovalHealth(for: value.owner.sourceID, record: &record)
            records[threadID] = record
        case .sourceHealth(let health):
            guard let sourceID = health.sourceID else { return }
            hookApprovalHealthBySource[sourceID] = health.state
            for id in records.keys {
                var record = records[id]!
                guard record.hookApprovalOwner?.sourceID == sourceID else { continue }
                record.approvalObservedAt = health.observedAt
                updateHookApprovalHealth(for: sourceID, record: &record)
                records[id] = record
            }
        }
    }

    /// Read-only proof that this exact sanitized PermissionRequest was
    /// admitted to its exact bound thread as a pending Hook approval. This is
    /// deliberately narrower than the global presentation state.
    public func pendingHookApprovalThreadID(for event: HookApprovalLifecycleEvent) -> NamespacedID? {
        guard let threadID = boundThread(for: event.owner),
              let record = records[threadID],
              let pending = record.hookPendingApprovals[event.journalEventID],
              pending.event.owner == event.owner else { return nil }
        return threadID
    }

    /// AX never reads a thread identifier. Attribute the visible sheet only
    /// when exactly one current runtime owner exists; otherwise keep it global.
    public func ingest(_ observation: ApprovalUIObservation) {
        guard pausePhase == .live else { return }
        approvalUIPresence = observation.presence
        approvalUIObservedAt = observation.observedAt
        for id in records.keys {
            var record = records[id]!
            record.uiApprovalWaitingAt = nil
            records[id] = record
        }
        guard observation.presence == .waiting else { return }
        let active = records.values.filter { $0.activeTurnID != nil && $0.terminal == nil }
        guard active.count == 1, let threadID = active.first?.threadID else { return }
        var record = records[threadID]!
        record.uiApprovalWaitingAt = observation.observedAt
        records[threadID] = record
    }

    public func ingestApprovalPoll(_ result: ApprovalPollResult) {
        for observation in result.observations { ingest(observation) }
        ingest(.sourceHealth(result.health))
    }

    /// A removed/archive-only historical reader must not survive as a global
    /// unavailable candidate. Current active failures are handled by the
    /// cycle-level runtime health before this removal is applied.
    public func remove(threadID: NamespacedID) {
        records.removeValue(forKey: threadID)
    }

    public func recordSystemError(threadID: NamespacedID, observedAt: Date? = nil) {
        guard pausePhase == .live else { return }
        let at = observedAt ?? clock.now(); var record = record(for: threadID, at: at)
        let turn = record.activeTurnID ?? NamespacedID(sourceID: threadID.sourceID, entityKind: .turn, rawID: "monitor-system")!
        let terminal = ReconciledTerminal(turnID: turn, eventID: "monitor-system-\(at.timeIntervalSince1970)", state: .systemError, authoritativeEventAt: at)!
        installTerminal(terminal, into: &record); records[threadID] = record
    }

    public func setPaused(_ paused: Bool) {
        if paused, pausePhase == .live { pausePhase = .paused; pauseSince = clock.now() }
        if !paused, pausePhase == .paused { pausePhase = .reconciling }
    }

    public func beginReconciliation() {
        guard pausePhase == .live else { return }
        pausePhase = .reconciling; pauseSince = clock.now()
    }

    /// One atomic rehydration point for both Monitor restart and pause/resume.
    public func installReconciliation(_ values: [RuntimeReconciliationThread]) {
        guard pausePhase == .reconciling || pausePhase == .paused else { return }
        let now = clock.now(); var rebuilt: [NamespacedID: ThreadRecord] = [:]
        hookApprovalHealthBySource.removeAll()
        for value in values {
            var record = ThreadRecord(threadID: value.threadID, at: now)
            record.conversationName = safeConversationName(value.conversationName); record.model = value.model; record.activeTurnID = value.activeTurnID
            record.turnStartedAt = value.turnStartedAt; record.lastActiveState = value.latestActiveState; record.lastActiveStateAt = value.latestActiveStateAt
            record.activeItemID = value.activeItemID; record.activeItemCategory = value.activeItemCategory; record.lastActivity = value.activeItemCategory ?? activity(for: value.latestActiveState ?? .idle)
            record.tokens = value.sessionTokenCumulative; record.tokenProvenance = value.sessionTokenProvenance
            record.runtimeSourceAvailable = value.runtimeSourceAvailable; record.runtimeObservedAt = value.runtimeObservedAt
            record.lastMeaningfulActivityAt = value.lastMeaningfulActivityAt
            record.approvalObservedAt = value.approvalObservedAt
            record.pendingApprovals = Dictionary(uniqueKeysWithValues: value.unresolvedApprovals.filter { $0.threadID == value.threadID && $0.turnID == value.activeTurnID }.map { ($0.requestID, PendingApproval(request: $0)) })
            record.hookApprovalOwner = value.hookApprovalOwner
            record.hookPendingApprovals = Dictionary(uniqueKeysWithValues: value.unresolvedHookApprovals.map { evidence in
                (evidence.journalEventID, PendingHookApproval(event: HookApprovalLifecycleEvent(journalEventID: evidence.journalEventID, owner: evidence.owner, observedAt: evidence.observedAt, reviewer: evidence.reviewer ?? .unknown)))
            })
            if let owner = value.hookApprovalOwner {
                hookApprovalHealthBySource[owner.sourceID] = switch value.approvalHealth {
                case .availableWaiting, .availableKnownNotWaiting: .available
                case .unavailable: .unavailable
                case .unknown, .stale: .unknown
                }
            }
            record.approvalHealth = hasPendingApproval(record) ? (value.approvalHealth == .unavailable || value.approvalHealth == .stale || value.approvalHealth == .unknown ? value.approvalHealth : .availableWaiting) : value.approvalHealth
            if let terminal = value.terminal { installTerminal(terminal, into: &record) }
            rebuilt[value.threadID] = record
        }
        records = rebuilt; pausePhase = .live; pauseSince = nil
    }

    /// Kept as a compatibility guard: it never incorrectly declares old state
    /// live. Owners must supply `installReconciliation` to leave reconciling.
    public func completeResumeReconciliation() { }

    public func snapshot() -> GlobalRuntimeSnapshot {
        let now = clock.now()
        let threadSnapshots = records.values.map { snapshot(for: $0, now: now) }.sorted { stableID($0.threadID) < stableID($1.threadID) }
        if pausePhase != .live {
            let since = pauseSince ?? now
            let pausedThreads = threadSnapshots.map { value in ThreadRuntimeSnapshot(threadID: value.threadID, activeTurnID: value.activeTurnID, conversationName: value.conversationName, model: value.model, state: .paused, stateSince: since, turnRuntimeStartedAt: value.turnRuntimeStartedAt, sessionTokenCumulative: value.sessionTokenCumulative, sessionTokenProvenance: value.sessionTokenProvenance, sessionTokenAvailable: value.sessionTokenAvailable, sourceFreshness: stale(value.sourceFreshness, at: now), approvalHealth: .stale, approvalFreshness: stale(value.approvalFreshness, at: now), approvalRequestObserved: false, userAttentionRequired: false, currentActivityCategory: value.currentActivityCategory) }
            return GlobalRuntimeSnapshot(state: .paused, stateSince: since, representativeThreadID: nil, currentActivityCategory: .idle, currentActivityShortSafeLabel: RuntimeActivityCategory.idle.shortSafeLabel, sourceFreshness: Freshness(state: .stale, assessedAt: now, observedAt: since, reason: "monitorPausedOrRevalidating"), activeThreadCount: 0, waitingApprovalCount: 0, approvalRequestObserved: false, representativeThread: nil, threads: pausedThreads)
        }
        let ranked = threadSnapshots.sorted { lhs, rhs in
            let l = priority(lhs.state), r = priority(rhs.state)
            if l != r { return l > r }; if lhs.stateSince != rhs.stateSince { return lhs.stateSince > rhs.stateSince }
            return stableID(lhs.threadID) < stableID(rhs.threadID)
        }
        let representative = ranked.first
        return GlobalRuntimeSnapshot(state: representative?.state ?? .disconnected, stateSince: representative?.stateSince ?? now, representativeThreadID: representative?.threadID, currentActivityCategory: representative?.currentActivityCategory ?? .disconnected, currentActivityShortSafeLabel: (representative?.currentActivityCategory ?? .disconnected).shortSafeLabel, sourceFreshness: aggregateFreshness(threadSnapshots, now: now), activeThreadCount: threadSnapshots.filter { [.thinking, .working].contains($0.state) }.count, waitingApprovalCount: threadSnapshots.filter { $0.state == .waitingApproval }.count, approvalRequestObserved: representative?.approvalRequestObserved ?? false, representativeThread: representative, threads: threadSnapshots)
    }

    /// Terminal states are deliberately retained for a brief, user-visible
    /// interval. Hosts use this deadline to schedule one presentation wake-up
    /// instead of polling the reducer; a new turn or source transition simply
    /// replaces the deadline.
    public func nextPresentationTransitionDeadline() -> Date? {
        guard pausePhase == .live else { return nil }
        let now = clock.now()
        return records.values.compactMap { record -> Date? in
            guard record.runtimeSourceAvailable, let terminal = record.terminal else { return nil }
            let interval = retention(for: terminal.state)
            guard interval > 0 else { return nil }
            let deadline = terminal.authoritativeEventAt.addingTimeInterval(interval)
            return deadline > now ? deadline : nil
        }.min()
    }

    private func updateApprovalHealth(_ health: ApprovalSourceHealth) {
        defaultApprovalHealth = health.state == .unavailable ? .unavailable : .availableKnownNotWaiting
        for id in records.keys {
            var record = records[id]!
            record.approvalObservedAt = health.observedAt
            if health.state == .unavailable { record.approvalHealth = .unavailable }
            else { record.approvalHealth = hasPendingApproval(record) ? .availableWaiting : .availableKnownNotWaiting }
            records[id] = record
        }
    }

    private func boundThread(for owner: HookApprovalTurnOwner) -> NamespacedID? {
        records.values.first { $0.activeTurnID != nil && $0.terminal == nil && $0.hookApprovalOwner == owner }?.threadID
    }

    private func hasPendingApproval(_ record: ThreadRecord) -> Bool {
        !record.pendingApprovals.isEmpty || !record.hookPendingApprovals.isEmpty
    }

    private func userAttentionRequired(for record: ThreadRecord) -> Bool {
        // Legacy request evidence stays conservative. Hook classification
        // belongs to each pending event, never to a global or latest turn.
        !record.pendingApprovals.isEmpty
            || record.hookPendingApprovals.values.contains { $0.event.reviewer.requiresUserAttention }
    }

    private func updateHookApprovalHealth(for sourceID: HookOpaqueIdentity, record: inout ThreadRecord) {
        switch hookApprovalHealthBySource[sourceID] ?? .unknown {
        case .available:
            record.approvalHealth = hasPendingApproval(record) ? .availableWaiting : .availableKnownNotWaiting
        case .unavailable:
            record.approvalHealth = .unavailable
        case .unknown:
            record.approvalHealth = .unknown
        }
    }

    private func terminal(from rollout: RolloutRecordEnvelope) -> ReconciledTerminal? {
        guard let turn = rollout.turnID else { return nil }
        let state: MonitorRuntimeState
        switch rollout.kind {
        case .taskCompletedSuccess: state = .completed
        case .taskCompletedFailure: state = .failed
        case .turnAbortedInterrupted: state = .interrupted
        default: return nil
        }
        let eventID = rollout.eventID ?? "rollout-offset-\(rollout.fileOffset)-\(rollout.kind.rawValue)"
        return ReconciledTerminal(turnID: turn, eventID: eventID, state: state, authoritativeEventAt: rollout.authoritativeEventAt ?? rollout.observedAt)
    }

    private func acceptLiveTerminal(_ terminal: ReconciledTerminal, record: ThreadRecord) -> Bool {
        guard record.activeTurnID == terminal.turnID else { return false }
        return record.terminal?.eventID != terminal.eventID
    }

    private func installTerminal(_ terminal: ReconciledTerminal, into record: inout ThreadRecord) {
        guard record.terminal?.eventID != terminal.eventID else { return }
        record.activeTurnID = nil; record.activeItemID = nil; record.activeItemCategory = nil; record.pendingApprovals.removeAll(); record.hookPendingApprovals.removeAll(); record.hookApprovalOwner = nil; record.approvalRequestObservedAt = nil
        record.terminal = Terminal(turnID: terminal.turnID, eventID: terminal.eventID, state: terminal.state, authoritativeEventAt: terminal.authoritativeEventAt)
        record.lastMeaningfulActivityAt = latest(record.lastMeaningfulActivityAt, terminal.authoritativeEventAt)
        record.lastActivity = activity(for: terminal.state)
        if record.approvalHealth != .unavailable && record.approvalHealth != .unknown { record.approvalHealth = .availableKnownNotWaiting }
    }

    private func record(for threadID: NamespacedID, at: Date) -> ThreadRecord {
        if let existing = records[threadID] { return existing }
        var created = ThreadRecord(threadID: threadID, at: at)
        created.approvalHealth = defaultApprovalHealth
        return created
    }

    /// State DB deployments have emitted Unix seconds and milliseconds. This
    /// preserves source ordering without inventing local bootstrap activity.
    public static func desktopUpdatedAt(_ rawValue: Int64?) -> Date? {
        guard let rawValue, rawValue > 0 else { return nil }
        let seconds = rawValue >= 100_000_000_000 ? Double(rawValue) / 1_000 : Double(rawValue)
        return Date(timeIntervalSince1970: seconds)
    }

    private func latest(_ existing: Date?, _ candidate: Date) -> Date {
        guard let existing else { return candidate }
        return max(existing, candidate)
    }

    private func snapshot(for record: ThreadRecord, now: Date) -> ThreadRuntimeSnapshot {
        let state = state(for: record, now: now)
        let since: Date = switch state { case .completed, .failed, .interrupted, .systemError: record.terminal?.authoritativeEventAt ?? record.createdAt; case .thinking, .working: record.lastActiveStateAt ?? record.turnStartedAt ?? record.createdAt; case .waitingApproval: record.uiApprovalWaitingAt ?? (record.pendingApprovals.values.map { $0.request.observedAt } + record.hookPendingApprovals.values.map { $0.event.observedAt }).max() ?? record.turnStartedAt ?? record.createdAt; case .idle: record.lastMeaningfulActivityAt ?? .distantPast; case .disconnected, .paused: record.runtimeObservedAt }
        let runtimeFreshness = Freshness(state: record.runtimeSourceAvailable ? .fresh : .unknown, assessedAt: now, observedAt: record.runtimeObservedAt, reason: record.runtimeSourceAvailable ? nil : "runtimeSourceUnavailable")
        let approvalFreshness = Freshness(state: record.approvalHealth == .unavailable || record.approvalHealth == .unknown ? .unknown : (record.approvalHealth == .stale ? .stale : .fresh), assessedAt: now, observedAt: record.approvalObservedAt, reason: record.approvalHealth == .unavailable ? "approvalSourceUnavailable" : (record.approvalHealth == .unknown ? "approvalSourceUnknown" : nil))
        let category = [.thinking, .working].contains(state) ? record.lastActivity : activity(for: state)
        return ThreadRuntimeSnapshot(threadID: record.threadID, activeTurnID: record.activeTurnID, conversationName: record.conversationName, model: record.model, state: state, stateSince: since, turnRuntimeStartedAt: record.turnStartedAt, sessionTokenCumulative: record.tokens, sessionTokenProvenance: record.tokenProvenance, sessionTokenAvailable: record.sessionTokenAvailable, sourceFreshness: runtimeFreshness, approvalHealth: record.approvalHealth, approvalFreshness: approvalFreshness, approvalRequestObserved: record.approvalRequestObservedAt != nil, userAttentionRequired: userAttentionRequired(for: record), currentActivityCategory: category)
    }

    private func state(for record: ThreadRecord, now: Date) -> MonitorRuntimeState {
        if let terminal = record.terminal, now.timeIntervalSince(terminal.authoritativeEventAt) < retention(for: terminal.state) { return terminal.state }
        if record.activeTurnID != nil {
            guard record.runtimeSourceAvailable else { return .disconnected }
            if hasPendingApproval(record) { return .waitingApproval }
            return record.lastActiveState ?? .thinking
        }
        return record.runtimeSourceAvailable ? .idle : .disconnected
    }
    private func retention(for state: MonitorRuntimeState) -> TimeInterval { switch state { case .completed: 5; case .failed, .interrupted, .systemError: 15; default: 0 } }
    private func activity(for state: MonitorRuntimeState) -> RuntimeActivityCategory { switch state { case .thinking: .thinking; case .working: .tool; case .waitingApproval: .waitingApproval; case .completed: .completed; case .failed: .failed; case .interrupted: .interrupted; case .systemError: .systemError; case .idle, .paused: .idle; case .disconnected: .disconnected } }
    private func priority(_ state: MonitorRuntimeState) -> Int { switch state { case .systemError, .failed, .interrupted: 6; case .waitingApproval: 5; case .working, .thinking: 4; case .completed: 3; case .idle: 2; case .disconnected: 1; case .paused: 7 } }
    private func aggregateFreshness(_ values: [ThreadRuntimeSnapshot], now: Date) -> Freshness { guard let newest = values.map(\.sourceFreshness).max(by: { $0.observedAt < $1.observedAt }) else { return Freshness(state: .unknown, assessedAt: now, observedAt: now, reason: "noThreads") }; let state: FreshnessState = values.allSatisfy { $0.sourceFreshness.state == .fresh } ? .fresh : (values.contains { $0.sourceFreshness.state == .fresh } ? .stale : .unknown); return Freshness(state: state, assessedAt: now, observedAt: newest.observedAt, reason: state == .fresh ? nil : "oneOrMoreRuntimeSourcesUnavailable") }
    private func stale(_ freshness: Freshness, at now: Date) -> Freshness { Freshness(state: .stale, assessedAt: now, observedAt: freshness.observedAt, reason: "monitorPausedOrRevalidating") }
}

private struct Terminal { let turnID: NamespacedID; let eventID: String; let state: MonitorRuntimeState; let authoritativeEventAt: Date }
private struct PendingApproval { let request: ApprovalRequested }
private struct PendingHookApproval { let event: HookApprovalLifecycleEvent }
private struct ThreadRecord {
    let threadID: NamespacedID; let createdAt: Date
    var conversationName: String? = nil; var model: String? = nil; var activeTurnID: NamespacedID? = nil; var turnStartedAt: Date? = nil
    var lastActiveState: MonitorRuntimeState? = nil; var lastActiveStateAt: Date? = nil; var lastActivity: RuntimeActivityCategory = .thinking
    var activeItemID: NamespacedID? = nil; var activeItemCategory: RuntimeActivityCategory? = nil
    var pendingApprovals: [NamespacedID: PendingApproval] = [:]; var hookPendingApprovals: [HookApprovalJournalEventID: PendingHookApproval] = [:]; var hookApprovalOwner: HookApprovalTurnOwner? = nil; var approvalHealth: ApprovalCapabilityHealth = .availableKnownNotWaiting; var approvalObservedAt: Date
    var uiApprovalWaitingAt: Date? = nil
    var approvalRequestObservedAt: Date? = nil
    var terminal: Terminal? = nil; var tokens: Int64? = nil; var tokenProvenance: SessionTokenProvenance? = nil; var sessionTokenAvailable = true
    var runtimeSourceAvailable = true; var runtimeObservedAt: Date
    var lastMeaningfulActivityAt: Date? = nil
    init(threadID: NamespacedID, at: Date) { self.threadID = threadID; createdAt = at; runtimeObservedAt = at; approvalObservedAt = at }
}

private func safeConversationName(_ value: String?) -> String? { guard let value else { return nil }; let compact = value.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines); return compact.isEmpty ? nil : String(compact.prefix(120)) }
private func stableID(_ id: NamespacedID) -> String { id.sourceID.rawValue + "\u{0}" + id.entityKind.rawValue + "\u{0}" + id.rawID }
