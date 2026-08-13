import AppKit
import Foundation
import CodexMonitorContracts

enum CodexProcessLiveness {
    static let bundleIdentifier = "com.openai.codex"

    struct Observation: Sendable, Equatable {
        let bundleIdentifier: String
        let localizedName: String
        let bundleURL: String
        let isTerminated: Bool
    }

    static func currentObservation() -> Observation? {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else { return nil }
        return Observation(
            bundleIdentifier: application.bundleIdentifier ?? bundleIdentifier,
            localizedName: application.localizedName ?? "",
            bundleURL: application.bundleURL?.lastPathComponent ?? "",
            isTerminated: application.isTerminated
        )
    }

    static func isRunning() -> Bool {
        currentObservation().map { !$0.isTerminated } ?? false
    }

    static func isCodexApplication(_ notification: Notification) -> Bool {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return false }
        return application.bundleIdentifier == bundleIdentifier
    }
}

/// A short SQLite lock or an exact transient WAL-sidecar disappearance is a
/// failed *attempt*, not proof that Codex's primary local source disappeared.
/// The driver retries on its normal two-second cadence with a fresh read-only
/// connection. Schema/open/query failures still remain fail-closed.
enum DesktopPrimarySourceReadDisposition: Equatable {
    case retainLastKnownHealthy
    case fatal

    init(error: Error, hasSuccessfulStateDBRead: Bool) {
        if hasSuccessfulStateDBRead,
           let stateDBError = error as? StateDBError,
           [.busyExhausted, .transientWALUnavailable].contains(stateDBError) {
            self = .retainLastKnownHealthy
        } else {
            self = .fatal
        }
    }
}

/// App-owned scheduling around the already-validated local adapters. This is
/// deliberately outside the UI boundary: views receive only runtime snapshots.
/// A single two-second task performs bounded discovery and incremental reads.
public actor CodexLocalMonitorDriver {
    private let runtime: MonitorRuntimeStore
    private let sourceID: DesktopLocalSourceID
    private let stateReader: StateDBReader
    private let approvalReader: ApprovalLocalAdapter
    private let usageLedger: LocalUsageLedgerProvider?
    private let sessionRoots: [URL]
    private var desktop: DesktopLocalAdapter
    private var trackedThreads = Set<NamespacedID>()
    private var loopTask: Task<Void, Never>?
    private var sleepObservers: [NSObjectProtocol] = []
    private var livenessObservers: [NSObjectProtocol] = []
    private var didRecordProcessObservation = false
    private var suspended = false
    private var needsBootstrap = true
    /// This becomes true only after the same production reader has completed
    /// an exact `recentThreads()` read. It prevents a first-launch lock from
    /// being reported as a healthy desktop source.
    private var hasSuccessfulStateDBRead = false
    private var didUsageBackfill = false
    /// A first cumulative value is admitted only if this process saw the
    /// exact rollout/session begin live before any token record for it.
    private var ledgerLiveObservationStartedAt: Date?
    private var knownLedgerSessionKeys = Set<String>()
    private var verifiedLiveSessionStartKeys = Set<String>()

    public init(runtime: MonitorRuntimeStore, usageLedger: LocalUsageLedgerProvider? = nil, codexRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)) {
        self.runtime = runtime
        self.usageLedger = usageLedger
        sourceID = DesktopLocalSourceID("codex-desktop-local")!
        sessionRoots = [
            codexRoot.appendingPathComponent("sessions", isDirectory: true),
            codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
        ]
        let reader = StateDBReader(databaseURL: codexRoot.appendingPathComponent("state_5.sqlite"), sourceID: sourceID, schema: StateDBSchema(acceptedUserVersions: [0]))
        stateReader = reader
        // This is the already-validated, read-only request-evidence source.
        // Its source identity deliberately matches the desktop source so a
        // request can only affect the exact desktop thread/turn it names.
        approvalReader = ApprovalLocalAdapter(
            databaseURL: codexRoot.appendingPathComponent("logs_2.sqlite"),
            sourceID: ApprovalLocalSourceID(sourceID.value.rawValue)!,
            schema: ApprovalLogSchema(acceptedUserVersions: [0]),
            retryPolicy: ApprovalDBRetryPolicy(maximumRowsPerPoll: 2_048)
        )
        desktop = DesktopLocalAdapter(sourceID: sourceID, validatedSessionRoots: sessionRoots, stateDB: reader)
    }

    public func start() {
        guard loopTask == nil else { return }
        ledgerLiveObservationStartedAt = Date()
        if let usageLedger { Task { await usageLedger.start() } }
        installSleepObservers()
        installProcessLivenessObservers()
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
        for observer in livenessObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        livenessObservers.removeAll()
        desktop.shutdown()
        approvalReader.shutdown()
        trackedThreads.removeAll()
        ledgerLiveObservationStartedAt = nil
        knownLedgerSessionKeys.removeAll()
        verifiedLiveSessionStartKeys.removeAll()
        if let usageLedger { Task { await usageLedger.stop() } }
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
        recordProcessObservationIfNeeded()
        if needsBootstrap {
            await bootstrap()
        } else {
            await pollIncrementally()
        }
    }

    private func bootstrap() async {
        // Reconciliation is an internal staging step. The completed desktop
        // cycle publishes exactly one reduced semantic snapshot below.
        await runtime.beginReconciliation(publish: false)
        guard CodexProcessLiveness.isRunning() else {
            let health = DesktopCycleHealth(processRunning: false, stateDBReadable: false, removedThreadIDs: Array(trackedThreads))
            for threadID in trackedThreads { desktop.forget(threadID: threadID) }
            trackedThreads.removeAll()
            hasSuccessfulStateDBRead = false
            await installReconciliation([], health: health, caller: "bootstrap.codexProcessNotRunning")
            await runtime.markSourceUnavailable(.approvalLocal)
            needsBootstrap = false
            return
        }
        do {
            let records = try stateReader.recentThreads()
            hasSuccessfulStateDBRead = true
            let approval = try? Self.catchUpApproval(approvalReader).result
            let approvalCheckpoint = approvalReader.lifecycleCheckpoint()
            let approvalHealth = approvalHealth(for: approval)
            var rebuilt: [RuntimeReconciliationThread] = []
            var usageObservations: [DesktopObservation] = []
            var admitted = Set<NamespacedID>()
            for record in records {
                guard let snapshot = try? desktop.open(threadRawID: record.snapshot.threadID.rawID),
                      let poll = try? desktop.poll(threadID: snapshot.threadID),
                      poll.invalidation == nil else { continue }
                admitted.insert(snapshot.threadID)
                usageObservations.append(contentsOf: poll.observations)
                let hydration = poll.hydration ?? RolloutCheckpointHydration(activeTurnID: nil, turnStartedAt: nil, activeItemID: nil, activeItemCategory: nil, latestActiveState: nil, latestActiveStateAt: nil, terminal: nil, authoritativeTokenTotal: nil)
                rebuilt.append(LocalRuntimeReconciliationOwner.thread(snapshot: snapshot, hydration: hydration, approval: approvalCheckpoint, approvalHealth: approvalHealth, runtimeSourceAvailable: true, observedAt: Date()))
            }
            trackedThreads = admitted
            await installReconciliation(rebuilt, health: DesktopCycleHealth(processRunning: true, stateDBReadable: true), caller: "bootstrap.stateDBRead")
            await usageLedger?.ingest(registrations: records.map(\.snapshot), observations: usageObservations)
            await backfillUsageIfNeeded()
            await applyApprovalPoll(approval)
            needsBootstrap = false
        } catch {
            trackedThreads.removeAll()
            let disposition = DesktopPrimarySourceReadDisposition(error: error, hasSuccessfulStateDBRead: hasSuccessfulStateDBRead)
            recordStateDBReadFailure(error, disposition: disposition, caller: "bootstrap.stateDBRead")
            let health = DesktopCycleHealth(processRunning: true, stateDBReadable: disposition == .retainLastKnownHealthy)
            await installReconciliation([], health: health, caller: "bootstrap.stateDBReadFailure")
            await applyApprovalPoll(pollApproval())
            needsBootstrap = disposition == .fatal
        }
    }

    private func pollIncrementally() async {
        guard CodexProcessLiveness.isRunning() else {
            let removed = Array(trackedThreads)
            for threadID in trackedThreads { desktop.forget(threadID: threadID) }
            trackedThreads.removeAll()
            hasSuccessfulStateDBRead = false
            await applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: false, stateDBReadable: false, removedThreadIDs: removed), caller: "pollIncrementally.codexProcessNotRunning")
            return
        }
        do {
            let records = try stateReader.recentThreads()
            hasSuccessfulStateDBRead = true
            let approval = pollApproval()
            let current = Set(records.map { $0.snapshot.threadID })
            let archived = trackedThreads.subtracting(current)
            for threadID in archived { desktop.forget(threadID: threadID) }
            trackedThreads.subtract(archived)
            var registrations = Dictionary(uniqueKeysWithValues: records
                .filter { trackedThreads.contains($0.snapshot.threadID) }
                .map { ($0.snapshot.threadID, $0.snapshot) })
            for record in records where !trackedThreads.contains(record.snapshot.threadID) {
                guard let snapshot = try? desktop.open(threadRawID: record.snapshot.threadID.rawID) else { continue }
                trackedThreads.insert(snapshot.threadID)
                registrations[snapshot.threadID] = snapshot
            }
            var observations: [DesktopObservation] = []
            var failed = Set<NamespacedID>()
            for threadID in trackedThreads.intersection(current).sorted(by: { $0.rawID < $1.rawID }) {
                guard let result = try? desktop.poll(threadID: threadID) else {
                    failed.insert(threadID)
                    continue
                }
                guard result.invalidation == nil else {
                    failed.insert(threadID)
                    continue
                }
                observations.append(contentsOf: result.observations)
            }
            for threadID in failed { desktop.forget(threadID: threadID) }
            trackedThreads.subtract(failed)
            let completeFromSessionStart = completeFromSessionStartSessions(in: observations)
            await applyDesktopCycle(registrations: registrations.values.sorted(by: { $0.threadID.rawID < $1.threadID.rawID }), observations: observations, health: DesktopCycleHealth(processRunning: true, stateDBReadable: true, failedThreadIDs: Array(failed), removedThreadIDs: Array(archived)), caller: "pollIncrementally.stateDBRead", completeFromSessionStartSessions: completeFromSessionStart)
            await applyApprovalPoll(approval)
        } catch {
            let disposition = DesktopPrimarySourceReadDisposition(error: error, hasSuccessfulStateDBRead: hasSuccessfulStateDBRead)
            recordStateDBReadFailure(error, disposition: disposition, caller: "pollIncrementally.stateDBRead")
            await applyDesktopCycle(registrations: [], observations: [], health: DesktopCycleHealth(processRunning: true, stateDBReadable: disposition == .retainLastKnownHealthy), caller: "pollIncrementally.stateDBReadFailure")
            await applyApprovalPoll(pollApproval())
            needsBootstrap = disposition == .fatal
        }
    }

    /// A cumulative counter may start at zero only after this Monitor process
    /// has seen the first record of the exact rollout/session live, and that
    /// record is an authoritative task start. Bootstrap and backfill never
    /// call this path, so historical attachment remains a baseline.
    private func completeFromSessionStartSessions(in observations: [DesktopObservation]) -> Set<String> {
        guard let liveStartedAt = ledgerLiveObservationStartedAt else { return [] }
        var firstRecordInBatch = Set<String>()
        var admittedForFirstToken = Set<String>()

        for observation in observations {
            guard case let .rollout(record) = observation,
                  let sourceKey = LocalUsageLedgerProvider.cursorSourceKey(for: record) else { continue }

            let isFirstEverObserved = !knownLedgerSessionKeys.contains(sourceKey) && !firstRecordInBatch.contains(sourceKey)
            if isFirstEverObserved,
               record.kind == .taskStarted,
               let eventAt = record.authoritativeEventAt,
               eventAt >= liveStartedAt {
                verifiedLiveSessionStartKeys.insert(sourceKey)
            }
            firstRecordInBatch.insert(sourceKey)

            if record.kind == .tokenCount, verifiedLiveSessionStartKeys.contains(sourceKey) {
                admittedForFirstToken.insert(sourceKey)
            }
        }

        knownLedgerSessionKeys.formUnion(firstRecordInBatch)
        verifiedLiveSessionStartKeys.subtract(admittedForFirstToken)
        return admittedForFirstToken
    }

    /// Only request evidence is admitted by MonitorRuntimeStore. Any resolver
    /// record remains intentionally ignored there under the frozen V3-2
    /// capability contract; a following authoritative rollout is what moves
    /// a waiting thread back to its real semantic state.
    private func pollApproval() -> ApprovalPollResult? {
        try? approvalReader.poll()
    }

    /// A fresh app has no durable approval cursor. Before publishing its
    /// reconstructed state, catch the bounded reader up to a stable source
    /// cursor so recent permission evidence is not delayed behind historical
    /// stream rows. This remains read-only and uses the existing finite
    /// approval catch-up policy.
    static func catchUpApproval(_ reader: ApprovalLocalAdapter, policy: ApprovalCatchUpPolicy = .init()) throws -> DriverApprovalCatchUpResult {
        var previousCursor: ApprovalLogCursor?
        var unchangedAvailablePolls = 0
        var lastResult: ApprovalPollResult?

        for pollNumber in 1...policy.maximumPolls {
            let result = try reader.poll()
            lastResult = result
            if result.health.state == .unavailable {
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
                return DriverApprovalCatchUpResult(result: result, polls: pollNumber)
            }
        }
        if let lastResult, lastResult.health.state == .unavailable {
            throw ApprovalCatchUpError.sourceUnavailable(lastResult.health.reason)
        }
        throw ApprovalCatchUpError.safetyBoundReached
    }

    private func approvalHealth(for result: ApprovalPollResult?) -> ApprovalCapabilityHealth {
        guard let result, result.health.state == .available else { return .unavailable }
        return .availableKnownNotWaiting
    }

    private func applyApprovalPoll(_ result: ApprovalPollResult?) async {
        guard let result else {
            await runtime.markSourceUnavailable(.approvalLocal)
            return
        }
        await runtime.ingestApprovalPoll(result)
    }

    private func installReconciliation(_ values: [RuntimeReconciliationThread], health: DesktopCycleHealth, caller: String) async {
        let previous = await runtime.snapshot()
        await runtime.installReconciliation(values, desktopHealth: health)
        await recordDesktopUnavailableTransition(from: previous, to: runtime.snapshot(), health: health, caller: caller)
    }

    private func applyDesktopCycle(registrations: [DesktopThreadSnapshot], observations: [DesktopObservation], health: DesktopCycleHealth, caller: String, completeFromSessionStartSessions: Set<String> = []) async {
        let previous = await runtime.snapshot()
        await runtime.applyDesktopCycle(registrations: registrations, observations: observations, health: health)
        await usageLedger?.ingest(registrations: registrations, observations: observations, completeFromSessionStartSessions: completeFromSessionStartSessions)
        await recordDesktopUnavailableTransition(from: previous, to: runtime.snapshot(), health: health, caller: caller)
    }

    /// One bounded, read-only pass establishes 30-day ledger history from the
    /// same state-DB-correlated active/archived rollout paths as live runtime
    /// monitoring. The temporary adapter is deliberately separate from the
    /// live reader cache, so historical replay cannot affect product state.
    private func backfillUsageIfNeeded() async {
        guard !didUsageBackfill, let usageLedger else { return }
        guard let records = try? stateReader.recentThreads(limit: 64) else { return }
        let historical = DesktopLocalAdapter(sourceID: sourceID, validatedSessionRoots: sessionRoots, stateDB: stateReader)
        var observations: [DesktopObservation] = []
        var registrations: [DesktopThreadSnapshot] = []
        for record in records {
            guard let snapshot = try? historical.open(threadRawID: record.snapshot.threadID.rawID, historicalTailBytes: 16 * 1_024 * 1_024),
                  let poll = try? historical.poll(threadID: snapshot.threadID),
                  poll.invalidation == nil else { continue }
            registrations.append(snapshot)
            observations.append(contentsOf: poll.observations)
        }
        historical.shutdown()
        await usageLedger.ingest(registrations: registrations, observations: observations)
        didUsageBackfill = true
    }

    /// The driver is the only production owner that writes desktop cycle
    /// health. Every visible AVAILABLE -> UNAVAILABLE transition is captured
    /// here with enough metadata to identify a real source failure without
    /// recording private rollout content or paths.
    private func recordDesktopUnavailableTransition(from previous: MonitorRuntimeSnapshot, to next: MonitorRuntimeSnapshot, health: DesktopCycleHealth, caller: String) async {
        guard previous.sourceHealth[.desktopLocal]?.availability == .available,
              next.sourceHealth[.desktopLocal]?.availability == .unavailable else { return }
        let current = next.currentThread ?? previous.currentThread
        let now = Date()
        let activeThreadFailed = current.map { health.failedThreadIDs.contains($0.threadID) } ?? false
        let processTerminated = !health.processRunning
        let stateDBFatalReadFailure = !health.stateDBReadable
        let primarySourceFatalError = activeThreadFailed
        let legal = processTerminated || stateDBFatalReadFailure || primarySourceFatalError
        let event = legal ? "UNAVAILABLE_TRANSITION" : "ILLEGAL_DESKTOP_UNAVAILABLE_TRANSITION"
        let stateSince = current?.stateSince
        let observedAt = next.sourceHealth[.desktopLocal]?.freshness.observedAt
        let assessedAt = next.sourceHealth[.desktopLocal]?.freshness.assessedAt
        recordTrace([
            "event": event,
            "timestamp": ISO8601DateFormatter().string(from: now),
            "previousState": previous.currentState.rawValue,
            "nextState": next.currentState.rawValue,
            "source": MonitorRuntimeSource.desktopLocal.rawValue,
            "reason": next.sourceHealth[.desktopLocal]?.reason?.rawValue ?? "none",
            "caller": caller,
            "threadID": current.map { stableDiagnosticID($0.threadID.rawID) } ?? "none",
            "processRunning": String(health.processRunning),
            "stateDBReadable": String(health.stateDBReadable),
            "processTerminated": String(processTerminated),
            "stateDBFatalReadFailure": String(stateDBFatalReadFailure),
            "primarySourceFatalError": String(primarySourceFatalError),
            "lastMeaningfulActivityAt": stateSince.map { ISO8601DateFormatter().string(from: $0) } ?? "none",
            "runtimeObservedAt": current.map { ISO8601DateFormatter().string(from: $0.freshness.observedAt) } ?? "none",
            "observedAt": observedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none",
            "assessedAt": assessedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none",
            "ageSeconds": stateSince.map { String(format: "%.3f", max(0, now.timeIntervalSince($0))) } ?? "none",
            "thresholdSeconds": "none"
        ])
    }

    private func recordStateDBReadFailure(_ error: Error, disposition: DesktopPrimarySourceReadDisposition, caller: String) {
        if let error = error as? StateDBError, error == .transientWALUnavailable {
            recordTrace([
                "event": "STATE_DB_TRANSIENT_WAL_MISSING",
                "caller": caller,
                "action": "preserveLastConfirmedHealth",
                "retry": "true",
                "freshConnection": "true"
            ])
        }
        recordTrace([
            "event": "STATE_DB_READ_FAILURE",
            "caller": caller,
            "error": String(describing: error),
            "hasSuccessfulStateDBRead": String(hasSuccessfulStateDBRead),
            "disposition": disposition == .retainLastKnownHealthy ? "retainLastKnownHealthy" : "fatal"
        ])
    }

    /// The normal app keeps traces in Diagnostics. QA can opt in to the exact
    /// same sanitized JSON line on stdout, making a cold-start/source-lock
    /// transition observable without a 30-minute manual wait.
    private func recordTrace(_ fields: [String: String]) {
        DiagnosticEvent.record(.state, fields)
        guard ProcessInfo.processInfo.environment["CODEX_MONITOR_TRACE_STDERR"] == "1",
              JSONSerialization.isValidJSONObject(fields),
              let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
    }

    private func stableDiagnosticID(_ raw: String) -> String {
        let hash = raw.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return String(hash, radix: 16)
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

    private func installProcessLivenessObservers() {
        guard livenessObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        livenessObservers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil) { [weak self] notification in
                guard CodexProcessLiveness.isCodexApplication(notification) else { return }
                Task { await self?.processLivenessDidChange() }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { [weak self] notification in
                guard CodexProcessLiveness.isCodexApplication(notification) else { return }
                Task { await self?.processLivenessDidChange() }
            }
        ]
    }

    private func processLivenessDidChange() async {
        needsBootstrap = true
        await refreshOnce()
    }

    private func recordProcessObservationIfNeeded() {
        guard !didRecordProcessObservation else { return }
        guard let observation = CodexProcessLiveness.currentObservation() else { return }
        didRecordProcessObservation = true
        DiagnosticEvent.record(.state, [
            "event": "codexProcessObservation",
            "bundleIdentifier": observation.bundleIdentifier,
            "localizedName": observation.localizedName,
            // The QA diagnostic keeps the bundle URL's final component only;
            // it is enough to verify the installed app without leaking a home
            // directory path.
            "bundleURL": observation.bundleURL,
            "isTerminated": String(observation.isTerminated)
        ])
    }
}

struct DriverApprovalCatchUpResult: Sendable, Equatable {
    let result: ApprovalPollResult
    let polls: Int
}
