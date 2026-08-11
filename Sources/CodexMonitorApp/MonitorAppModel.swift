import SwiftUI
import CodexMonitorContracts

/// Main-actor presentation bridge. It has no knowledge of local files, SQLite,
/// logs, RPC, or adapters: the runtime snapshot is its only input.
@MainActor
public final class MonitorAppModel: ObservableObject {
    @Published public private(set) var snapshot: MonitorRuntimeSnapshot?
    public private(set) var acceptedSnapshotCount = 0
    /// Every live state surface reads this one presentation projection. Views
    /// do not independently translate runtime state into colors or breathing.
    var presentation: VisualStatePresentation { VisualStatePresentation.forSnapshot(snapshot) }
    private var observationTask: Task<Void, Never>?

    public init() {}

    public func apply(_ next: MonitorRuntimeSnapshot) {
        guard snapshot.map({ !$0.isPresentationEquivalent(to: next) }) ?? true else { return }
        let previous = snapshot
        snapshot = next
        acceptedSnapshotCount += 1
        let presentation = VisualStatePresentation.forSnapshot(next)
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
    }

    deinit { observationTask?.cancel() }
}
