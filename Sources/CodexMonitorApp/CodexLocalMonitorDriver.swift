import AppKit
import Foundation
import CodexMonitorContracts

/// App-owned scheduling around the already-validated local adapters. This is
/// deliberately outside the UI boundary: views receive only runtime snapshots.
/// A single two-second task performs bounded discovery and incremental reads.
public actor CodexLocalMonitorDriver {
    private let runtime: MonitorRuntimeStore
    private let sourceID: DesktopLocalSourceID
    private let stateReader: StateDBReader
    private let sessionRoots: [URL]
    private var desktop: DesktopLocalAdapter
    private var trackedThreads = Set<NamespacedID>()
    private var loopTask: Task<Void, Never>?
    private var sleepObservers: [NSObjectProtocol] = []
    private var suspended = false
    private var needsBootstrap = true

    public init(runtime: MonitorRuntimeStore, codexRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)) {
        self.runtime = runtime
        sourceID = DesktopLocalSourceID("codex-desktop-local")!
        sessionRoots = [
            codexRoot.appendingPathComponent("sessions", isDirectory: true),
            codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
        ]
        let reader = StateDBReader(databaseURL: codexRoot.appendingPathComponent("state_5.sqlite"), sourceID: sourceID, schema: StateDBSchema(acceptedUserVersions: [0]))
        stateReader = reader
        desktop = DesktopLocalAdapter(sourceID: sourceID, validatedSessionRoots: sessionRoots, stateDB: reader)
    }

    public func start() {
        guard loopTask == nil else { return }
        installSleepObservers()
        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshOnce()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        for observer in sleepObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        sleepObservers.removeAll()
        desktop.shutdown()
        trackedThreads.removeAll()
    }

    public func handleSleep() async {
        suspended = true
        await runtime.setPaused(true)
    }

    public func handleWake() async {
        suspended = false
        await runtime.setPaused(false)
        needsBootstrap = true
    }

    /// User-controlled monitoring pause uses the existing runtime pause and
    /// reconciliation contract. No UI code reaches local sources directly.
    public func setUserMonitoringPaused(_ paused: Bool) async {
        suspended = paused
        await runtime.setPaused(paused)
        guard !paused else { return }
        needsBootstrap = true
        await refreshOnce()
    }

    public func refreshOnce() async {
        guard !suspended else { return }
        if needsBootstrap {
            await bootstrap()
        } else {
            await pollIncrementally()
        }
    }

    private func bootstrap() async {
        await runtime.beginReconciliation()
        do {
            let records = try stateReader.recentThreads()
            var rebuilt: [RuntimeReconciliationThread] = []
            var admitted = Set<NamespacedID>()
            for record in records {
                guard let snapshot = try? desktop.open(threadRawID: record.snapshot.threadID.rawID),
                      let poll = try? desktop.poll(threadID: snapshot.threadID),
                      poll.invalidation == nil else { continue }
                admitted.insert(snapshot.threadID)
                let hydration = poll.hydration ?? RolloutCheckpointHydration(activeTurnID: nil, turnStartedAt: nil, activeItemID: nil, activeItemCategory: nil, latestActiveState: nil, latestActiveStateAt: nil, terminal: nil, authoritativeTokenTotal: nil)
                rebuilt.append(LocalRuntimeReconciliationOwner.thread(snapshot: snapshot, hydration: hydration, approval: ApprovalLifecycleCheckpoint(cursor: nil, unresolved: []), approvalHealth: .unavailable, runtimeSourceAvailable: true, observedAt: Date()))
            }
            trackedThreads = admitted
            await runtime.installReconciliation(rebuilt)
            // This product integration intentionally does not make a new
            // approval-resolution claim. Waiting Approval remains supported by
            // snapshots injected from the existing runtime path; without a
            // configured current approval reader its source is explicit.
            await runtime.markSourceUnavailable(.approvalLocal)
            needsBootstrap = false
        } catch {
            trackedThreads.removeAll()
            await runtime.installReconciliation([])
            await runtime.markSourceUnavailable(.desktopLocal)
        }
    }

    private func pollIncrementally() async {
        do {
            let records = try stateReader.recentThreads()
            let current = Set(records.map { $0.snapshot.threadID })
            for record in records where !trackedThreads.contains(record.snapshot.threadID) {
                guard let snapshot = try? desktop.open(threadRawID: record.snapshot.threadID.rawID) else { continue }
                trackedThreads.insert(snapshot.threadID)
                await runtime.registerDesktopThread(snapshot)
                await ingestPoll(for: snapshot.threadID)
            }
            for threadID in trackedThreads.intersection(current) {
                await ingestPoll(for: threadID)
            }
        } catch {
            await runtime.markSourceUnavailable(.desktopLocal)
            needsBootstrap = true
        }
    }

    private func ingestPoll(for threadID: NamespacedID) async {
        guard let result = try? desktop.poll(threadID: threadID) else {
            await runtime.markSourceUnavailable(.desktopLocal)
            needsBootstrap = true
            return
        }
        for observation in result.observations { await runtime.ingest(observation) }
        if result.invalidation != nil { needsBootstrap = true }
    }

    private func installSleepObservers() {
        guard sleepObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
                Task { await self?.handleSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
                Task { await self?.handleWake() }
            }
        ]
    }
}
