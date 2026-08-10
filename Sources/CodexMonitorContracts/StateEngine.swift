import Foundation

/// Frozen presentation-domain states.  The raw values are deliberately the
/// approved product vocabulary so a future UI has no lossy ERROR bucket.
public enum MonitorRuntimeState: String, CaseIterable, Sendable, Equatable {
    case disconnected = "DISCONNECTED"
    case paused = "PAUSED"
    case idle = "IDLE"
    case thinking = "THINKING"
    case working = "WORKING"
    case waitingApproval = "WAITING_APPROVAL"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case interrupted = "INTERRUPTED"
    case systemError = "SYSTEM_ERROR"
}

public enum RuntimeActivityCategory: String, CaseIterable, Sendable, Equatable {
    case thinking, tool, fileChange, agentResponse, waitingApproval, completed, failed, interrupted, systemError, idle, disconnected
    public var shortSafeLabel: String { rawValue }
}

public protocol StateEngineClock: Sendable { func now() -> Date }
public struct SystemStateEngineClock: StateEngineClock { public init() {}; public func now() -> Date { Date() } }

public struct ThreadRuntimeSnapshot: Sendable, Equatable {
    public let threadID: NamespacedID
    public let taskTitle: String?
    public let model: String?
    public let state: MonitorRuntimeState
    public let stateSince: Date
    public let turnRuntimeStartedAt: Date?
    public let sessionTokenCumulative: Int64?
    public let sourceFreshness: Freshness
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
    public let representativeThread: ThreadRuntimeSnapshot?
    public let threads: [ThreadRuntimeSnapshot]
}

/// Domain-only pause control.  `completeResumeReconciliation` must be called
/// only after the owner has completed the V3-1 exact checkpoint/rebind poll.
/// Until then the snapshot remains PAUSED and stale; observation ingestion is
/// intentionally ignored while paused, avoiding replayed terminal states.
public enum MonitoringPausePhase: Sendable, Equatable { case live, paused, reconciling }

public final class RuntimeStateEngine: @unchecked Sendable {
    private let clock: any StateEngineClock
    private var records: [NamespacedID: ThreadRecord] = [:]
    private var pausePhase: MonitoringPausePhase = .live
    private var pauseSince: Date?

    public init(clock: any StateEngineClock = SystemStateEngineClock()) { self.clock = clock }

    public func register(_ snapshot: DesktopThreadSnapshot, sourceHealthAvailable: Bool = true, observedAt: Date? = nil) {
        guard pausePhase == .live else { return }
        let now = observedAt ?? clock.now()
        var record = records[snapshot.threadID] ?? ThreadRecord(threadID: snapshot.threadID, at: now)
        record.title = safeTitle(snapshot.title); record.model = snapshot.model
        if let tokens = snapshot.tokensUsed { record.tokens = tokens }
        record.sourceAvailable = sourceHealthAvailable; record.sourceObservedAt = now
        records[snapshot.threadID] = record
    }

    public func ingest(_ observation: DesktopObservation) {
        guard pausePhase == .live else { return }
        switch observation {
        case .rollout(let rollout): ingest(rollout)
        case .sourceHealth(let health): ingest(health)
        case .capabilityUnavailable(let threadID, _): markUnavailable(threadID, at: clock.now())
        }
    }

    public func ingest(_ rollout: RolloutRecordEnvelope) {
        guard pausePhase == .live else { return }
        var record = record(for: rollout.threadID, at: rollout.observedAt)
        record.sourceAvailable = true; record.sourceObservedAt = rollout.observedAt
        if let model = rollout.model { record.model = model }
        if let tokens = rollout.tokenSnapshot?.totalTokens { record.tokens = tokens }
        switch rollout.kind {
        case .taskStarted:
            guard let turnID = rollout.turnID else { records[rollout.threadID] = record; return }
            record.activeTurnID = turnID; record.turnStartedAt = rollout.observedAt
            record.lastActiveState = .thinking; record.lastActiveStateAt = rollout.observedAt; record.lastActivity = .thinking
            record.terminal = nil; record.pendingApprovals.removeAll()
        case .activity:
            guard rollout.turnID == record.activeTurnID else { records[rollout.threadID] = record; return }
            switch rollout.activity {
            case .thinking?: record.lastActiveState = .thinking; record.lastActiveStateAt = rollout.observedAt; record.lastActivity = .thinking
            case .tool?: record.lastActiveState = .working; record.lastActiveStateAt = rollout.observedAt; record.lastActivity = .tool
            case .fileChange?: record.lastActiveState = .working; record.lastActiveStateAt = rollout.observedAt; record.lastActivity = .fileChange
            case .agentResponse?: record.lastActivity = .agentResponse // never flips Thinking/Working
            case nil: break
            }
        case .taskCompletedSuccess, .taskCompletedFailure, .turnAbortedInterrupted:
            guard acceptsTerminal(rollout.turnID, record: record) else { records[rollout.threadID] = record; return }
            let state: MonitorRuntimeState = switch rollout.kind {
            case .taskCompletedSuccess: .completed
            case .taskCompletedFailure: .failed
            case .turnAbortedInterrupted: .interrupted
            default: .systemError
            }
            record.activeTurnID = nil; record.pendingApprovals.removeAll()
            record.terminal = Terminal(state: state, at: rollout.observedAt)
            record.lastActivity = activity(for: state)
        case .tokenCount, .turnContext, .sessionMeta:
            break // token/context alone never change active state
        }
        records[rollout.threadID] = record
    }

    public func ingest(_ health: DesktopSourceHealth) {
        guard pausePhase == .live else { return }
        let now = clock.now()
        var record = record(for: health.threadID, at: now)
        record.sourceAvailable = health.state == .available; record.sourceObservedAt = now
        records[health.threadID] = record
    }

    public func ingest(_ approval: ApprovalObservation) {
        guard pausePhase == .live else { return }
        switch approval {
        case .requested(let request):
            var record = record(for: request.threadID, at: request.observedAt)
            guard record.activeTurnID == request.turnID else { return }
            record.pendingApprovals[request.requestID] = PendingApproval(turnID: request.turnID, requestedAt: request.observedAt)
            record.approvalAvailable = true; record.approvalObservedAt = request.observedAt
            records[request.threadID] = record
        case .resolved(let resolution):
            var record = record(for: resolution.threadID, at: resolution.observedAt)
            guard record.pendingApprovals[resolution.requestID]?.turnID == resolution.turnID else { return }
            record.pendingApprovals.removeValue(forKey: resolution.requestID)
            record.approvalAvailable = true; record.approvalObservedAt = resolution.observedAt
            records[resolution.threadID] = record
        case .sourceUnavailable(let health):
            for id in records.keys {
                records[id]?.approvalAvailable = false
                records[id]?.approvalObservedAt = health.observedAt
                records[id]?.pendingApprovals.removeAll()
            }
        }
    }

    /// Only the Monitor can report this condition; task failures must enter via
    /// an authoritative rollout terminal and therefore remain FAILED.
    public func recordSystemError(threadID: NamespacedID, observedAt: Date? = nil) {
        guard pausePhase == .live else { return }
        let now = observedAt ?? clock.now()
        var record = record(for: threadID, at: now)
        record.activeTurnID = nil; record.pendingApprovals.removeAll()
        record.terminal = Terminal(state: .systemError, at: now); record.lastActivity = .systemError
        records[threadID] = record
    }

    public func setPaused(_ paused: Bool) {
        if paused, pausePhase == .live { pausePhase = .paused; pauseSince = clock.now() }
        if !paused, pausePhase == .paused { pausePhase = .reconciling }
    }

    public func completeResumeReconciliation() {
        guard pausePhase == .reconciling else { return }
        pausePhase = .live; pauseSince = nil
    }

    public func snapshot() -> GlobalRuntimeSnapshot {
        let now = clock.now()
        let threadSnapshots = records.values.map { snapshot(for: $0, now: now) }.sorted { stableID($0.threadID) < stableID($1.threadID) }
        if pausePhase != .live {
            let since = pauseSince ?? now
            let pausedThreads = threadSnapshots.map { value in ThreadRuntimeSnapshot(threadID: value.threadID, taskTitle: value.taskTitle, model: value.model, state: .paused, stateSince: since, turnRuntimeStartedAt: value.turnRuntimeStartedAt, sessionTokenCumulative: value.sessionTokenCumulative, sourceFreshness: stale(value.sourceFreshness, at: now), currentActivityCategory: value.currentActivityCategory) }
            return GlobalRuntimeSnapshot(state: .paused, stateSince: since, representativeThreadID: nil, currentActivityCategory: .idle, currentActivityShortSafeLabel: RuntimeActivityCategory.idle.shortSafeLabel, sourceFreshness: Freshness(state: .stale, assessedAt: now, observedAt: since, reason: "monitorPausedOrRevalidating"), activeThreadCount: 0, waitingApprovalCount: 0, representativeThread: nil, threads: pausedThreads)
        }
        let ranked = threadSnapshots.sorted { lhs, rhs in
            let l = priority(lhs.state), r = priority(rhs.state)
            if l != r { return l > r }
            if lhs.stateSince != rhs.stateSince { return lhs.stateSince > rhs.stateSince }
            return stableID(lhs.threadID) < stableID(rhs.threadID)
        }
        let representative = ranked.first
        let globalFreshness = aggregateFreshness(threadSnapshots, now: now)
        return GlobalRuntimeSnapshot(state: representative?.state ?? .disconnected, stateSince: representative?.stateSince ?? now, representativeThreadID: representative?.threadID, currentActivityCategory: representative?.currentActivityCategory ?? .disconnected, currentActivityShortSafeLabel: (representative?.currentActivityCategory ?? .disconnected).shortSafeLabel, sourceFreshness: globalFreshness, activeThreadCount: threadSnapshots.filter { [.thinking, .working, .waitingApproval].contains($0.state) }.count, waitingApprovalCount: threadSnapshots.filter { $0.state == .waitingApproval }.count, representativeThread: representative, threads: threadSnapshots)
    }

    private func markUnavailable(_ threadID: NamespacedID, at: Date) {
        var record = record(for: threadID, at: at); record.sourceAvailable = false; record.sourceObservedAt = at; records[threadID] = record
    }

    private func record(for threadID: NamespacedID, at: Date) -> ThreadRecord { records[threadID] ?? ThreadRecord(threadID: threadID, at: at) }
    private func acceptsTerminal(_ turn: NamespacedID?, record: ThreadRecord) -> Bool { record.activeTurnID == nil || record.activeTurnID == turn }

    private func snapshot(for record: ThreadRecord, now: Date) -> ThreadRuntimeSnapshot {
        let state = state(for: record, now: now)
        let stateSince: Date = switch state {
        case .completed, .failed, .interrupted, .systemError: record.terminal?.at ?? record.createdAt
        case .thinking, .working: record.lastActiveStateAt ?? record.turnStartedAt ?? record.createdAt
        case .waitingApproval: record.pendingApprovals.values.map(\.requestedAt).max() ?? record.turnStartedAt ?? record.createdAt
        case .idle, .disconnected, .paused: record.sourceObservedAt
        }
        let category = state == .waitingApproval ? .waitingApproval : state == .thinking || state == .working ? record.lastActivity : activity(for: state)
        let freshness = Freshness(state: record.sourceAvailable ? .fresh : .unknown, assessedAt: now, observedAt: record.sourceObservedAt, reason: record.sourceAvailable ? nil : "runtimeSourceUnavailable")
        return ThreadRuntimeSnapshot(threadID: record.threadID, taskTitle: record.title, model: record.model, state: state, stateSince: stateSince, turnRuntimeStartedAt: record.turnStartedAt, sessionTokenCumulative: record.tokens, sourceFreshness: freshness, currentActivityCategory: category)
    }

    private func state(for record: ThreadRecord, now: Date) -> MonitorRuntimeState {
        if let terminal = record.terminal, now.timeIntervalSince(terminal.at) < retention(for: terminal.state) { return terminal.state }
        if record.activeTurnID != nil {
            guard record.sourceAvailable else { return .disconnected }
            if record.approvalAvailable && !record.pendingApprovals.isEmpty { return .waitingApproval }
            return record.lastActiveState ?? .thinking
        }
        return record.sourceAvailable ? .idle : .disconnected
    }

    private func retention(for state: MonitorRuntimeState) -> TimeInterval {
        switch state { case .completed: 5; case .failed, .interrupted, .systemError: 15; default: 0 }
    }
    private func activity(for state: MonitorRuntimeState) -> RuntimeActivityCategory {
        switch state {
        case .thinking: .thinking; case .working: .tool; case .waitingApproval: .waitingApproval
        case .completed: .completed; case .failed: .failed; case .interrupted: .interrupted
        case .systemError: .systemError; case .idle, .paused: .idle; case .disconnected: .disconnected
        }
    }
    private func priority(_ state: MonitorRuntimeState) -> Int {
        switch state {
        case .systemError, .failed, .interrupted: 6
        case .waitingApproval: 5
        case .working, .thinking: 4
        case .completed: 3
        case .idle: 2
        case .disconnected: 1
        case .paused: 7
        }
    }
    private func aggregateFreshness(_ values: [ThreadRuntimeSnapshot], now: Date) -> Freshness {
        guard let newest = values.map(\.sourceFreshness).max(by: { $0.observedAt < $1.observedAt }) else { return Freshness(state: .unknown, assessedAt: now, observedAt: now, reason: "noThreads") }
        let state: FreshnessState = values.allSatisfy { $0.sourceFreshness.state == .fresh } ? .fresh : (values.contains { $0.sourceFreshness.state == .fresh } ? .stale : .unknown)
        return Freshness(state: state, assessedAt: now, observedAt: newest.observedAt, reason: state == .fresh ? nil : "oneOrMoreRuntimeSourcesUnavailable")
    }
    private func stale(_ freshness: Freshness, at now: Date) -> Freshness { Freshness(state: .stale, assessedAt: now, observedAt: freshness.observedAt, reason: "monitorPausedOrRevalidating") }
}

private struct Terminal { let state: MonitorRuntimeState; let at: Date }
private struct ThreadRecord {
    let threadID: NamespacedID
    let createdAt: Date
    var title: String? = nil
    var model: String? = nil
    var activeTurnID: NamespacedID? = nil
    var turnStartedAt: Date? = nil
    var lastActiveState: MonitorRuntimeState? = nil
    var lastActiveStateAt: Date? = nil
    var lastActivity: RuntimeActivityCategory = .thinking
    var pendingApprovals: [NamespacedID: PendingApproval] = [:]
    var approvalAvailable = true
    var approvalObservedAt: Date? = nil
    var terminal: Terminal? = nil
    var tokens: Int64? = nil
    var sourceAvailable = true
    var sourceObservedAt: Date
    init(threadID: NamespacedID, at: Date) { self.threadID = threadID; createdAt = at; sourceObservedAt = at }
}

private struct PendingApproval { let turnID: NamespacedID; let requestedAt: Date }

private func safeTitle(_ value: String?) -> String? {
    guard let value else { return nil }
    let compact = value.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !compact.isEmpty else { return nil }
    return String(compact.prefix(120))
}

private func stableID(_ id: NamespacedID) -> String { id.sourceID.rawValue + "\u{0}" + id.entityKind.rawValue + "\u{0}" + id.rawID }
