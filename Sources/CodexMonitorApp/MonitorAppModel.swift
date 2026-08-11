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
        snapshot = next
        acceptedSnapshotCount += 1
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
