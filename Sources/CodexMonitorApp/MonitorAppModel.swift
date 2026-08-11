import SwiftUI
import CodexMonitorContracts

/// Main-actor presentation bridge. It has no knowledge of local files, SQLite,
/// logs, RPC, or adapters: the runtime snapshot is its only input.
@MainActor
public final class MonitorAppModel: ObservableObject {
    @Published public private(set) var snapshot: MonitorRuntimeSnapshot?
    public private(set) var acceptedSnapshotCount = 0
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

    /// Snapshot reads are actor hops, never source I/O on the main actor. The
    /// store itself is passive; this small UI observation cadence does not
    /// create parser/database polling and duplicate presentations are ignored.
    public func startObserving(_ runtime: MonitorRuntimeStore, interval: Duration = .seconds(1)) {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                let next = await runtime.snapshot()
                guard !Task.isCancelled else { return }
                self?.apply(next)
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    deinit { observationTask?.cancel() }
}
