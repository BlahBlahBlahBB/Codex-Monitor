import Foundation

/// UI-facing availability is deliberately separate from product state. A
/// missing value is never silently converted into a zero, false, or terminal
/// outcome.
public enum MonitorDataAvailability: String, Sendable, Equatable {
    case available
    case unavailable
    case stale
    case unknown
}

public enum MonitorUnavailabilityReason: String, Sendable, Equatable {
    case noCurrentThread
    case noObservedValue
    case sourceUnavailable
    case sourceStale
    case capabilityUnvalidated
    case capabilityUnsupported
    case externalCodexDesktopCapability
    case monitorPausedOrRevalidating
}

public struct MonitorCapabilityAvailability: Sendable, Equatable {
    public let availability: MonitorDataAvailability
    public let reason: MonitorUnavailabilityReason?

    public init(availability: MonitorDataAvailability, reason: MonitorUnavailabilityReason? = nil) {
        self.availability = availability
        self.reason = reason
    }
}

/// This intentionally has a separate vocabulary from `CapabilityName`: it is
/// the stable product contract consumed by the UI, rather than a description
/// of an individual adapter or protocol field.
public enum MonitorRuntimeCapability: String, CaseIterable, Sendable, Equatable {
    case currentState
    case sessionThreadAttribution
    case waitingApproval
    case approvalResolution
    case sessionToken
    case usage
    case quota
    case resetInformation
}

public enum MonitorRuntimeSource: String, CaseIterable, Sendable, Equatable {
    case desktopLocal
    case approvalLocal
    case account
}

public struct MonitorSourceHealth: Sendable, Equatable {
    public let source: MonitorRuntimeSource
    public let availability: MonitorDataAvailability
    public let freshness: Freshness
    public let reason: MonitorUnavailabilityReason?

    public init(source: MonitorRuntimeSource, availability: MonitorDataAvailability, freshness: Freshness, reason: MonitorUnavailabilityReason? = nil) {
        self.source = source
        self.availability = availability
        self.freshness = freshness
        self.reason = reason
    }
}

public struct MonitorThreadViewModel: Sendable, Equatable {
    public let threadID: NamespacedID
    public let activeTurnID: NamespacedID?
    public let taskTitle: String?
    public let model: String?
    public let state: MonitorRuntimeState
    public let stateSince: Date
    public let activity: RuntimeActivityCategory
    public let waitingApproval: MonitorCapabilityAvailability
    public let sessionToken: Int64?
    public let sessionTokenAvailability: MonitorDataAvailability
    public let sessionTokenProvenance: SessionTokenProvenance?
    public let freshness: Freshness

    init(_ value: ThreadRuntimeSnapshot) {
        threadID = value.threadID
        activeTurnID = value.activeTurnID
        taskTitle = value.taskTitle
        model = value.model
        state = value.state
        stateSince = value.stateSince
        activity = value.currentActivityCategory
        waitingApproval = MonitorRuntimeSnapshotBuilder.waitingApprovalAvailability(for: value)
        let tokenAvailability = MonitorRuntimeSnapshotBuilder.sessionTokenAvailability(for: value)
        sessionToken = tokenAvailability == .available ? value.sessionTokenCumulative : nil
        sessionTokenAvailability = tokenAvailability
        sessionTokenProvenance = tokenAvailability == .available ? value.sessionTokenProvenance : nil
        freshness = value.sourceFreshness
    }
}

public struct MonitorSessionThreadAttribution: Sendable, Equatable {
    public let sourceID: SourceID
    public let threadID: NamespacedID
    public let activeTurnID: NamespacedID?

    init?(thread: MonitorThreadViewModel?) {
        guard let thread else { return nil }
        sourceID = thread.threadID.sourceID
        threadID = thread.threadID
        activeTurnID = thread.activeTurnID
    }
}

public struct MonitorUsageViewModel: Sendable, Equatable {
    public let availability: MonitorDataAvailability
    public let usage: UsagePresence?
}

public struct MonitorAccountViewModel: Sendable, Equatable {
    public let availability: MonitorDataAvailability
    public let accountKind: String?
    public let plan: String?
}

public struct MonitorQuotaViewModel: Sendable, Equatable {
    public let primaryAvailability: MonitorDataAvailability
    public let primary: RateLimitWindow?
    public let secondaryAvailability: MonitorDataAvailability
    public let secondary: RateLimitWindow?
}

public struct MonitorResetInformationViewModel: Sendable, Equatable {
    public let countAvailability: MonitorDataAvailability
    public let count: Int?
    public let detailsAvailability: MonitorDataAvailability
    public let details: [String]?
}

/// The one snapshot a UI needs. It contains only product projection and
/// source/capability health; SQLite, rollout files, logs, RPC and fallbacks
/// stay behind this boundary.
public struct MonitorRuntimeSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let monitoringPhase: MonitoringPausePhase
    public let currentState: MonitorRuntimeState
    public let currentStateSince: Date
    public let currentActivity: RuntimeActivityCategory
    public let currentThread: MonitorThreadViewModel?
    public let currentSessionThread: MonitorSessionThreadAttribution?
    public let activeThreadCount: Int
    public let waitingApprovalCount: Int
    public let threads: [MonitorThreadViewModel]
    public let sessionToken: Int64?
    public let account: MonitorAccountViewModel
    public let usage: MonitorUsageViewModel
    public let quota: MonitorQuotaViewModel
    public let resetInformation: MonitorResetInformationViewModel
    public let sourceHealth: [MonitorRuntimeSource: MonitorSourceHealth]
    public let capabilities: [MonitorRuntimeCapability: MonitorCapabilityAvailability]

    /// `capturedAt` and freshness assessment timestamps are sampling metadata,
    /// not presentation changes. UI bindings use this to avoid rerendering on
    /// a timer when the observable product state has not changed.
    public func isPresentationEquivalent(to other: MonitorRuntimeSnapshot) -> Bool {
        monitoringPhase == other.monitoringPhase &&
        currentState == other.currentState &&
        currentStateSince == other.currentStateSince &&
        currentActivity == other.currentActivity &&
        equivalent(currentThread, other.currentThread) &&
        currentSessionThread == other.currentSessionThread &&
        activeThreadCount == other.activeThreadCount &&
        waitingApprovalCount == other.waitingApprovalCount &&
        threads.count == other.threads.count && zip(threads, other.threads).allSatisfy { equivalent($0, $1) } &&
        sessionToken == other.sessionToken &&
        account == other.account &&
        usage == other.usage &&
        quota == other.quota &&
        resetInformation == other.resetInformation &&
        sourceHealth.count == other.sourceHealth.count && sourceHealth.allSatisfy { entry in
            other.sourceHealth[entry.key].map { equivalent(entry.value, $0) } ?? false
        } &&
        capabilities == other.capabilities
    }

    private func equivalent(_ lhs: MonitorThreadViewModel?, _ rhs: MonitorThreadViewModel?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case let (.some(lhs), .some(rhs)): equivalent(lhs, rhs)
        default: false
        }
    }

    private func equivalent(_ lhs: MonitorThreadViewModel, _ rhs: MonitorThreadViewModel) -> Bool {
        lhs.threadID == rhs.threadID && lhs.activeTurnID == rhs.activeTurnID && lhs.taskTitle == rhs.taskTitle && lhs.model == rhs.model && lhs.state == rhs.state && lhs.stateSince == rhs.stateSince && lhs.activity == rhs.activity && lhs.waitingApproval == rhs.waitingApproval && lhs.sessionToken == rhs.sessionToken && lhs.sessionTokenAvailability == rhs.sessionTokenAvailability && lhs.sessionTokenProvenance == rhs.sessionTokenProvenance && equivalent(lhs.freshness, rhs.freshness)
    }

    private func equivalent(_ lhs: MonitorSourceHealth, _ rhs: MonitorSourceHealth) -> Bool {
        lhs.source == rhs.source && lhs.availability == rhs.availability && lhs.reason == rhs.reason && equivalent(lhs.freshness, rhs.freshness)
    }

    private func equivalent(_ lhs: Freshness, _ rhs: Freshness) -> Bool {
        lhs.state == rhs.state && lhs.observedAt == rhs.observedAt && lhs.reason == rhs.reason
    }
}

public protocol MonitorRuntimeClock: Sendable { func now() -> Date }
public struct SystemMonitorRuntimeClock: MonitorRuntimeClock { public init() {} ; public func now() -> Date { Date() } }

public struct MonitorRuntimeFreshnessPolicy: Sendable, Equatable {
    /// Account data is snapshot-only. This bound prevents a permanently old
    /// quota/usage payload from looking current when its producer is idle.
    public let maximumAccountAge: TimeInterval

    public init(maximumAccountAge: TimeInterval = 300) {
        self.maximumAccountAge = max(1, maximumAccountAge)
    }
}

/// Describes read capability supplied by the host's validated account route.
/// Unvalidated and unsupported fields are omitted even if an input object
/// happens to contain a value.
public struct MonitorAccountCapabilityConfiguration: Sendable, Equatable {
    public let usage: CapabilityState
    public let primaryQuota: CapabilityState
    public let secondaryQuota: CapabilityState
    public let resetCount: CapabilityState
    public let resetDetails: CapabilityState

    public init(usage: CapabilityState = .snapshot, primaryQuota: CapabilityState = .snapshot, secondaryQuota: CapabilityState = .unvalidated, resetCount: CapabilityState = .snapshot, resetDetails: CapabilityState = .unvalidated) {
        self.usage = usage
        self.primaryQuota = primaryQuota
        self.secondaryQuota = secondaryQuota
        self.resetCount = resetCount
        self.resetDetails = resetDetails
    }
}

/// A passive, actor-isolated projection store for a resident macOS app. It
/// performs no file/database/network I/O and starts no timer or polling loop:
/// the host feeds it already-admitted incremental observations on a background
/// task, while UI code obtains one coherent snapshot at a time.
public actor MonitorRuntimeStore {
    private let engine: RuntimeStateEngine
    private let clock: any MonitorRuntimeClock
    private let freshnessPolicy: MonitorRuntimeFreshnessPolicy
    private let accountCapabilities: MonitorAccountCapabilityConfiguration
    private var accountSnapshot: AccountSnapshot?
    private var accountSource: SourceState
    private var desktopSource: SourceState
    private var approvalSource: SourceState
    private var monitoringPhase: MonitoringPausePhase
    private var snapshotContinuations: [UUID: AsyncStream<MonitorRuntimeSnapshot>.Continuation] = [:]
    private var terminalTransitionTask: Task<Void, Never>?
    private var terminalTransitionDeadline: Date?

    public init(
        engine: RuntimeStateEngine = RuntimeStateEngine(),
        clock: any MonitorRuntimeClock = SystemMonitorRuntimeClock(),
        freshnessPolicy: MonitorRuntimeFreshnessPolicy = .init(),
        accountCapabilities: MonitorAccountCapabilityConfiguration = .init(),
        initialPhase: MonitoringPausePhase = .reconciling
    ) {
        self.engine = engine
        self.clock = clock
        self.freshnessPolicy = freshnessPolicy
        self.accountCapabilities = accountCapabilities
        let now = clock.now()
        accountSnapshot = nil
        accountSource = SourceState(availability: .unknown, observedAt: now, reason: nil)
        desktopSource = SourceState(availability: initialPhase == .live ? .unknown : .stale, observedAt: now, reason: initialPhase == .live ? nil : .monitorPausedOrRevalidating)
        approvalSource = SourceState(availability: .unknown, observedAt: now, reason: nil)
        monitoringPhase = initialPhase
    }

    public func registerDesktopThread(_ snapshot: DesktopThreadSnapshot, sourceHealthAvailable: Bool = true, observedAt: Date? = nil) {
        let at = observedAt ?? clock.now()
        engine.register(snapshot, sourceHealthAvailable: sourceHealthAvailable, observedAt: at)
        desktopSource = SourceState(availability: sourceHealthAvailable ? .available : .unavailable, observedAt: at, reason: sourceHealthAvailable ? nil : .sourceUnavailable)
        publishSnapshot()
    }

    public func ingest(_ observation: DesktopObservation) {
        engine.ingest(observation)
        let at = clock.now()
        switch observation {
        case .rollout:
            desktopSource = SourceState(availability: .available, observedAt: at, reason: nil)
        case .sourceHealth(let health):
            desktopSource = SourceState(availability: health.state == .available ? .available : .unavailable, observedAt: at, reason: health.state == .available ? nil : .sourceUnavailable)
        case .capabilityUnavailable:
            desktopSource = SourceState(availability: .unavailable, observedAt: at, reason: .capabilityUnsupported)
        }
        publishSnapshot()
    }

    /// Resolution is deliberately not admitted here. V3-2 established that
    /// Codex Desktop does not expose a reliable resolution source. Requested
    /// approvals and source health remain useful; exact tool-completion/turn
    /// evidence continues to drive the existing reducer fallback.
    public func ingest(_ observation: ApprovalObservation) {
        switch observation {
        case .resolved:
            return
        case .requested:
            approvalSource = SourceState(availability: .available, observedAt: clock.now(), reason: nil)
        case .sourceHealth(let health), .sourceUnavailable(let health):
            approvalSource = SourceState(availability: health.state == .available ? .available : .unavailable, observedAt: health.observedAt, reason: health.state == .available ? nil : .sourceUnavailable)
        }
        engine.ingest(observation)
        publishSnapshot()
    }

    public func ingestApprovalPoll(_ result: ApprovalPollResult) {
        for observation in result.observations { ingest(observation) }
        let health = result.health
        approvalSource = SourceState(availability: health.state == .available ? .available : .unavailable, observedAt: health.observedAt, reason: health.state == .available ? nil : .sourceUnavailable)
        engine.ingest(.sourceHealth(health))
        publishSnapshot()
    }

    public func ingest(account snapshot: AccountSnapshot) {
        accountSnapshot = snapshot
        let freshness = snapshot.provenance.freshness
        accountSource = SourceState(availability: freshness.state == .fresh ? .available : monitorAvailability(for: freshness.state), observedAt: freshness.observedAt, reason: freshness.state == .fresh ? nil : monitorReason(for: freshness.state))
        publishSnapshot()
    }

    public func markSourceUnavailable(_ source: MonitorRuntimeSource, observedAt: Date? = nil) {
        let state = SourceState(availability: .unavailable, observedAt: observedAt ?? clock.now(), reason: .sourceUnavailable)
        switch source {
        case .desktopLocal: desktopSource = state
        case .approvalLocal: approvalSource = state
        case .account: accountSource = state; accountSnapshot = nil
        }
        publishSnapshot()
    }

    public func setPaused(_ paused: Bool) {
        engine.setPaused(paused)
        if paused {
            monitoringPhase = .paused
            desktopSource = SourceState(availability: .stale, observedAt: clock.now(), reason: .monitorPausedOrRevalidating)
            approvalSource = SourceState(availability: .stale, observedAt: clock.now(), reason: .monitorPausedOrRevalidating)
        } else {
            monitoringPhase = .reconciling
            desktopSource = SourceState(availability: .stale, observedAt: clock.now(), reason: .monitorPausedOrRevalidating)
            approvalSource = SourceState(availability: .stale, observedAt: clock.now(), reason: .monitorPausedOrRevalidating)
        }
        publishSnapshot()
    }

    public func beginReconciliation() {
        engine.beginReconciliation()
        monitoringPhase = .reconciling
        let now = clock.now()
        desktopSource = SourceState(availability: .stale, observedAt: now, reason: .monitorPausedOrRevalidating)
        approvalSource = SourceState(availability: .stale, observedAt: now, reason: .monitorPausedOrRevalidating)
        publishSnapshot()
    }

    public func installReconciliation(_ values: [RuntimeReconciliationThread]) {
        engine.installReconciliation(values)
        monitoringPhase = .live
        let now = clock.now()
        desktopSource = SourceState(availability: values.isEmpty ? .unknown : .available, observedAt: now, reason: nil)
        approvalSource = SourceState(availability: values.isEmpty ? .unknown : .available, observedAt: now, reason: nil)
        publishSnapshot()
    }

    /// Event-driven UI subscription. A new subscriber receives one coherent
    /// snapshot immediately, then only mutations that can change the product
    /// projection. No UI-side timer or source reread is involved.
    public func snapshots() -> AsyncStream<MonitorRuntimeSnapshot> {
        let id = UUID()
        let stream = AsyncStream<MonitorRuntimeSnapshot>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            snapshotContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSnapshotContinuation(id) }
            }
        }
        snapshotContinuations[id]?.yield(snapshot())
        return stream
    }

    public func snapshot() -> MonitorRuntimeSnapshot {
        let now = clock.now()
        let runtime = engine.snapshot()
        let threads = runtime.threads.map(MonitorThreadViewModel.init)
        let current = runtime.representativeThread.flatMap { candidate in threads.first { $0.threadID == candidate.threadID } }
        let account = freshAccount(at: now)
        let effectiveAccountSource = accountSourceForSnapshot(at: now)
        let accountHealth = sourceHealth(for: .account, state: effectiveAccountSource, now: now)
        let desktopHealth = desktopHealth(for: current, lane: desktopSource, now: now)
        let approvalHealth = sourceHealth(for: .approvalLocal, state: approvalSource, now: now)
        let capabilities = MonitorRuntimeSnapshotBuilder.capabilities(
            runtime: runtime,
            current: current,
            desktop: desktopHealth,
            approval: approvalHealth,
            account: account,
            accountSource: accountHealth,
            accountCapabilities: accountCapabilities
        )
        let accountView = MonitorRuntimeSnapshotBuilder.account(account, source: accountHealth)
        let usage = MonitorRuntimeSnapshotBuilder.usage(account, source: accountHealth, capability: accountCapabilities.usage)
        let quota = MonitorRuntimeSnapshotBuilder.quota(account, source: accountHealth, primaryCapability: accountCapabilities.primaryQuota, secondaryCapability: accountCapabilities.secondaryQuota)
        let reset = MonitorRuntimeSnapshotBuilder.reset(account, source: accountHealth, countCapability: accountCapabilities.resetCount, detailsCapability: accountCapabilities.resetDetails)
        return MonitorRuntimeSnapshot(capturedAt: now, monitoringPhase: monitoringPhase, currentState: runtime.state, currentStateSince: runtime.stateSince, currentActivity: runtime.currentActivityCategory, currentThread: current, currentSessionThread: MonitorSessionThreadAttribution(thread: current), activeThreadCount: runtime.activeThreadCount, waitingApprovalCount: runtime.waitingApprovalCount, threads: threads, sessionToken: current?.sessionToken, account: accountView, usage: usage, quota: quota, resetInformation: reset, sourceHealth: [.desktopLocal: desktopHealth, .approvalLocal: approvalHealth, .account: accountHealth], capabilities: capabilities)
    }

    private func freshAccount(at now: Date) -> AccountSnapshot? {
        guard let accountSnapshot, accountSource.availability == .available else { return nil }
        guard now.timeIntervalSince(accountSnapshot.provenance.observedAt) <= freshnessPolicy.maximumAccountAge else { return nil }
        return accountSnapshot
    }

    private func accountSourceForSnapshot(at now: Date) -> SourceState {
        guard let accountSnapshot,
              accountSource.availability == .available,
              now.timeIntervalSince(accountSnapshot.provenance.observedAt) > freshnessPolicy.maximumAccountAge else {
            return accountSource
        }
        return SourceState(availability: .stale, observedAt: accountSnapshot.provenance.observedAt, reason: .sourceStale)
    }

    private func sourceHealth(for source: MonitorRuntimeSource, state: SourceState, fallback: Freshness? = nil, now: Date) -> MonitorSourceHealth {
        let fallbackAvailability = fallback.map { monitorAvailability(for: $0.state) }
        // The reducer aggregates exact per-thread source health. A single
        // most-recent desktop observation cannot conceal an older thread that
        // is unavailable or stale, so aggregate freshness wins for this lane.
        let runtimeAggregateRequiresDowngrade = source == .desktopLocal && state.availability == .available && fallbackAvailability != .available && fallbackAvailability != nil
        let resolvedAvailability = monitoringPhase == .live
            ? (runtimeAggregateRequiresDowngrade ? fallbackAvailability! : (state.availability == .unknown ? (fallbackAvailability ?? .unknown) : state.availability))
            : .stale
        let resolvedReason = monitoringPhase == .live
            ? (runtimeAggregateRequiresDowngrade ? fallback.flatMap { monitorReason(for: $0.state) } : state.reason ?? fallback.flatMap { monitorReason(for: $0.state) })
            : .monitorPausedOrRevalidating
        let observedAt = fallback?.observedAt ?? state.observedAt
        let freshnessState: FreshnessState = switch resolvedAvailability { case .available: .fresh; case .stale: .stale; case .unavailable, .unknown: .unknown }
        return MonitorSourceHealth(source: source, availability: resolvedAvailability, freshness: Freshness(state: freshnessState, assessedAt: now, observedAt: observedAt, reason: resolvedReason?.rawValue), reason: resolvedReason)
    }

    /// Historical threads remain in `threads`, but their freshness is not a
    /// presentation veto for a fresh representative thread. This prevents an
    /// old unavailable record from turning a current IDLE/WORKING/THINKING
    /// snapshot into Source Unavailable.
    private func desktopHealth(for current: MonitorThreadViewModel?, lane: SourceState, now: Date) -> MonitorSourceHealth {
        guard let current else {
            return sourceHealth(for: .desktopLocal, state: lane, now: now)
        }
        // A representative thread with unknown runtime freshness is an exact
        // current-source loss, not an innocuous absence of metadata. Preserve
        // the established fail-closed `unavailable` contract for that case.
        let availability: MonitorDataAvailability = switch current.freshness.state {
        case .fresh: .available
        case .stale: .stale
        case .unknown: .unavailable
        }
        let reason = monitorReason(for: current.freshness.state)
        return MonitorSourceHealth(
            source: .desktopLocal,
            availability: availability,
            freshness: Freshness(state: current.freshness.state, assessedAt: now, observedAt: current.freshness.observedAt, reason: reason?.rawValue),
            reason: reason
        )
    }

    private func publishSnapshot() {
        let value = snapshot()
        for continuation in snapshotContinuations.values { continuation.yield(value) }
        scheduleTerminalPresentationTransition()
    }

    /// A single deadline wake-up preserves the event-driven runtime contract.
    /// It exists only while a terminal retention interval is visible, and is
    /// replaced or cancelled by every later source mutation/reconciliation.
    private func scheduleTerminalPresentationTransition() {
        let next = engine.nextPresentationTransitionDeadline()
        guard next != terminalTransitionDeadline || terminalTransitionTask == nil else { return }
        terminalTransitionTask?.cancel()
        terminalTransitionTask = nil
        terminalTransitionDeadline = next
        guard let next else { return }

        let delay = max(0, next.timeIntervalSince(clock.now()))
        terminalTransitionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            await self?.terminalPresentationDeadlineDidFire(expected: next)
        }
    }

    private func terminalPresentationDeadlineDidFire(expected: Date) {
        guard terminalTransitionDeadline == expected else { return }
        terminalTransitionTask = nil
        terminalTransitionDeadline = nil
        publishSnapshot()
    }

    private func removeSnapshotContinuation(_ id: UUID) {
        snapshotContinuations.removeValue(forKey: id)
    }

    private func monitorAvailability(for state: FreshnessState) -> MonitorDataAvailability {
        switch state { case .fresh: .available; case .stale: .stale; case .unknown: .unknown }
    }

    private func monitorReason(for state: FreshnessState) -> MonitorUnavailabilityReason? {
        switch state { case .fresh: nil; case .stale: .sourceStale; case .unknown: .sourceUnavailable }
    }
}

private struct SourceState: Sendable {
    let availability: MonitorDataAvailability
    let observedAt: Date
    let reason: MonitorUnavailabilityReason?
}

private enum MonitorRuntimeSnapshotBuilder {
    static func account(_ account: AccountSnapshot?, source: MonitorSourceHealth) -> MonitorAccountViewModel {
        guard source.availability == .available, let account else {
            return MonitorAccountViewModel(availability: source.availability, accountKind: nil, plan: nil)
        }
        return MonitorAccountViewModel(availability: .available, accountKind: account.authMode, plan: account.planType)
    }

    static func waitingApprovalAvailability(for thread: ThreadRuntimeSnapshot) -> MonitorCapabilityAvailability {
        switch thread.approvalHealth {
        case .availableKnownNotWaiting, .availableWaiting: return MonitorCapabilityAvailability(availability: .available)
        case .unavailable: return MonitorCapabilityAvailability(availability: .unavailable, reason: .sourceUnavailable)
        case .stale: return MonitorCapabilityAvailability(availability: .stale, reason: .sourceStale)
        }
    }

    static func sessionTokenAvailability(for thread: ThreadRuntimeSnapshot) -> MonitorDataAvailability {
        guard thread.sessionTokenAvailable else { return .unavailable }
        guard thread.sourceFreshness.state == .fresh else {
            return thread.sourceFreshness.state == .stale ? .stale : .unavailable
        }
        return thread.sessionTokenCumulative == nil ? .unknown : .available
    }

    static func capabilities(runtime: GlobalRuntimeSnapshot, current: MonitorThreadViewModel?, desktop: MonitorSourceHealth, approval: MonitorSourceHealth, account: AccountSnapshot?, accountSource: MonitorSourceHealth, accountCapabilities: MonitorAccountCapabilityConfiguration) -> [MonitorRuntimeCapability: MonitorCapabilityAvailability] {
        let stateAvailability = availability(from: desktop)
        let attribution = current == nil ? MonitorCapabilityAvailability(availability: .unknown, reason: .noCurrentThread) : stateAvailability
        let waiting = availability(from: approval)
        let token: MonitorCapabilityAvailability
        if let current {
            token = MonitorCapabilityAvailability(availability: current.sessionTokenAvailability, reason: current.sessionTokenAvailability == .available ? nil : .noObservedValue)
        } else {
            token = MonitorCapabilityAvailability(availability: .unknown, reason: .noCurrentThread)
        }
        return [
            .currentState: stateAvailability,
            .sessionThreadAttribution: attribution,
            .waitingApproval: waiting,
            // Frozen V3-2 contract: this remains unavailable until Desktop
            // exposes a reliable resolution source in a future phase.
            .approvalResolution: MonitorCapabilityAvailability(availability: .unavailable, reason: .externalCodexDesktopCapability),
            .sessionToken: token,
            .usage: fieldAvailability(account, source: accountSource, capability: accountCapabilities.usage),
            .quota: combined(fieldAvailability(account, source: accountSource, capability: accountCapabilities.primaryQuota), fieldAvailability(account, source: accountSource, capability: accountCapabilities.secondaryQuota)),
            .resetInformation: combined(fieldAvailability(account, source: accountSource, capability: accountCapabilities.resetCount), fieldAvailability(account, source: accountSource, capability: accountCapabilities.resetDetails))
        ]
    }

    static func usage(_ account: AccountSnapshot?, source: MonitorSourceHealth, capability: CapabilityState) -> MonitorUsageViewModel {
        let availability = valueAvailability(account?.usage, source: source, capability: capability)
        return MonitorUsageViewModel(availability: availability, usage: availability == .available ? account?.usage : nil)
    }

    static func quota(_ account: AccountSnapshot?, source: MonitorSourceHealth, primaryCapability: CapabilityState, secondaryCapability: CapabilityState) -> MonitorQuotaViewModel {
        let primary = valueAvailability(account?.primaryRateLimit, source: source, capability: primaryCapability)
        let secondary = valueAvailability(account?.secondaryRateLimit, source: source, capability: secondaryCapability)
        return MonitorQuotaViewModel(primaryAvailability: primary, primary: primary == .available ? account?.primaryRateLimit : nil, secondaryAvailability: secondary, secondary: secondary == .available ? account?.secondaryRateLimit : nil)
    }

    static func reset(_ account: AccountSnapshot?, source: MonitorSourceHealth, countCapability: CapabilityState, detailsCapability: CapabilityState) -> MonitorResetInformationViewModel {
        let count = valueAvailability(account?.resetCreditCount, source: source, capability: countCapability)
        let details = valueAvailability(account?.resetCreditDetails, source: source, capability: detailsCapability)
        return MonitorResetInformationViewModel(countAvailability: count, count: count == .available ? account?.resetCreditCount : nil, detailsAvailability: details, details: details == .available ? account?.resetCreditDetails : nil)
    }

    private static func availability(from health: MonitorSourceHealth) -> MonitorCapabilityAvailability {
        MonitorCapabilityAvailability(availability: health.availability, reason: health.reason)
    }

    private static func fieldAvailability(_ account: AccountSnapshot?, source: MonitorSourceHealth, capability: CapabilityState) -> MonitorCapabilityAvailability {
        guard isReadable(capability) else { return MonitorCapabilityAvailability(availability: .unavailable, reason: capability == .unsupported ? .capabilityUnsupported : .capabilityUnvalidated) }
        guard source.availability == .available else { return MonitorCapabilityAvailability(availability: source.availability, reason: source.reason) }
        return account == nil ? MonitorCapabilityAvailability(availability: .unknown, reason: .noObservedValue) : MonitorCapabilityAvailability(availability: .available)
    }

    private static func valueAvailability<T>(_ value: T?, source: MonitorSourceHealth, capability: CapabilityState) -> MonitorDataAvailability {
        guard isReadable(capability) else { return .unavailable }
        guard source.availability == .available else { return source.availability }
        return value == nil ? .unavailable : .available
    }

    private static func isReadable(_ capability: CapabilityState) -> Bool {
        capability == .snapshot || capability == .liveAuthoritative || capability == .mutationValidated
    }

    private static func combined(_ lhs: MonitorCapabilityAvailability, _ rhs: MonitorCapabilityAvailability) -> MonitorCapabilityAvailability {
        if lhs.availability == .available || rhs.availability == .available { return MonitorCapabilityAvailability(availability: .available) }
        if lhs.availability == .stale || rhs.availability == .stale { return MonitorCapabilityAvailability(availability: .stale, reason: .sourceStale) }
        if lhs.availability == .unknown || rhs.availability == .unknown { return MonitorCapabilityAvailability(availability: .unknown, reason: .noObservedValue) }
        return MonitorCapabilityAvailability(availability: .unavailable, reason: lhs.reason ?? rhs.reason)
    }
}
