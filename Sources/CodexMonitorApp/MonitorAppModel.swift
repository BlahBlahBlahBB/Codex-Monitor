import SwiftUI
import CodexMonitorContracts

/// Main-actor presentation bridge. It has no knowledge of local files, SQLite,
/// logs, RPC, or adapters: the runtime snapshot is its only input.
@MainActor
public final class MonitorAppModel: ObservableObject {
    @Published public private(set) var snapshot: MonitorRuntimeSnapshot?
    /// Local Usage V2 is an independent read-only capability lane. Keeping it
    /// outside the runtime-state snapshot prevents usage aggregation from
    /// influencing orb state, approval, account, or quota semantics.
    @Published public private(set) var localUsage: LocalUsageLedgerSnapshot?
    public private(set) var acceptedSnapshotCount = 0
    /// Every live state surface reads this one presentation projection. Views
    /// do not independently translate runtime state into colors or breathing.
    var presentation: VisualStatePresentation { VisualStatePresentation.forSnapshot(snapshot) }
    func presentation(using preferences: MonitorPreferences) -> VisualStatePresentation {
        VisualStatePresentation.forSnapshot(
            snapshot,
            quotaWarningEnabled: preferences.quotaWarningEnabled,
            quotaWarningThreshold: preferences.quotaWarningThreshold,
            experimentalApprovalYellowEnabled: preferences.experimentalApprovalYellowEnabled
        )
    }
    private var observationTask: Task<Void, Never>?
    private var usageObservationTask: Task<Void, Never>?

    public init() {}

    public func apply(_ next: MonitorRuntimeSnapshot) {
        let previous = snapshot
        let accepted = previous.map { !$0.isPresentationEquivalent(to: next) } ?? true
        let presentation = VisualStatePresentation.forSnapshot(next)
        DiagnosticEvent.record(.state, [
            "event": "runtimeSnapshotApply",
            "accepted": String(accepted),
            "changedFields": changedFields(from: previous, to: next, presentation: presentation).joined(separator: ","),
            "runtimeState": next.currentState.rawValue,
            "desktopAvailability": next.sourceHealth[.desktopLocal]?.availability.rawValue ?? "unknown",
            "quota": quotaValue(next),
            "account": accountValue(next),
            "threadID": diagnosticIdentifier(next.currentThread?.threadID.rawID),
            "presentationReason": presentation.stateTextKey
        ])
        guard accepted else { return }
        snapshot = next
        acceptedSnapshotCount += 1
        let previousState = previous?.currentState
        let newActiveTurnCancelsTerminal = (previousState == .failed || previousState == .interrupted || previousState == .systemError) && (next.currentState == .working || next.currentState == .thinking)
        DiagnosticEvent.record(.state, [
            "event": "runtimeSnapshot",
            "thread": diagnosticIdentifier(next.currentThread?.threadID.rawID),
            "turn": diagnosticIdentifier(next.currentThread?.activeTurnID?.rawID),
            "previousRuntimeState": previousState?.rawValue ?? "none",
            "nextRuntimeState": next.currentState.rawValue,
            "terminalRetention": newActiveTurnCancelsTerminal ? "cancelledByNewTurn" : "notRetainedInPresentation",
            "completedRetention": previousState == .completed && next.currentState != .completed ? "expiredOrSuperseded" : "unchanged"
        ])
        DiagnosticEvent.presentation(presentation, event: "snapshotApplied")
    }

    private func diagnosticIdentifier(_ raw: String?) -> String {
        guard let raw else { return "none" }
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in raw.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }

    private func changedFields(from previous: MonitorRuntimeSnapshot?, to next: MonitorRuntimeSnapshot, presentation: VisualStatePresentation) -> [String] {
        guard let previous else { return ["initialSnapshot"] }
        var fields: [String] = []
        if previous.currentState != next.currentState { fields.append("runtimeState") }
        if previous.sourceHealth[.desktopLocal]?.availability != next.sourceHealth[.desktopLocal]?.availability { fields.append("desktopAvailability") }
        if quotaValue(previous) != quotaValue(next) { fields.append("quota") }
        if accountValue(previous) != accountValue(next) { fields.append("account") }
        if previous.currentThread?.threadID != next.currentThread?.threadID { fields.append("threadID") }
        if VisualStatePresentation.forSnapshot(previous).stateTextKey != presentation.stateTextKey { fields.append("presentationReason") }
        if previous.currentThread?.activeTurnID != next.currentThread?.activeTurnID { fields.append("activeTurnID") }
        if previous.currentActivity != next.currentActivity { fields.append("activity") }
        if previous.waitingApprovalCount != next.waitingApprovalCount { fields.append("waitingApprovalCount") }
        if fields.isEmpty { fields.append("none") }
        return fields
    }

    private func quotaValue(_ snapshot: MonitorRuntimeSnapshot) -> String {
        let primary = snapshot.quota.primary?.usedPercent.map { String(format: "%.2f", $0) } ?? "nil"
        let secondary = snapshot.quota.secondary?.usedPercent.map { String(format: "%.2f", $0) } ?? "nil"
        return "primary=\(primary);secondary=\(secondary)"
    }

    private func accountValue(_ snapshot: MonitorRuntimeSnapshot) -> String {
        // Keep diagnostics sanitized: record presence and availability, not
        // the account's plan string or any other account identity value.
        "availability=\(snapshot.account.availability.rawValue);kindPresent=\(snapshot.account.accountKind != nil);planPresent=\(snapshot.account.plan != nil)"
    }

    /// Runtime delivery is event-driven. The store yields its current coherent
    /// snapshot on subscription and publishes only after a projection mutation.
    public func startObserving(_ runtime: MonitorRuntimeStore) {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            let updates = await runtime.snapshots()
            for await next in updates {
                guard !Task.isCancelled else { return }
                self?.apply(next)
            }
        }
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        usageObservationTask?.cancel()
        usageObservationTask = nil
    }

    public func startObserving(_ ledger: LocalUsageLedgerProvider) {
        usageObservationTask?.cancel()
        usageObservationTask = Task { [weak self] in
            let updates = await ledger.snapshots()
            for await next in updates {
                guard !Task.isCancelled else { return }
                self?.localUsage = next
            }
        }
    }

    deinit { observationTask?.cancel(); usageObservationTask?.cancel() }
}
