import XCTest
@testable import CodexMonitorContracts

/// Opt-in read-only validation against an installed Codex source.  It carries
/// no body text or production identifiers into test output or assertions.
final class ProductionPathValidationTests: XCTestCase {
    func testInstalledApprovalRowAtExactLogIDMapsToRequest() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEX_MONITOR_REAL_APPROVAL_DB"],
              let rawLogID = ProcessInfo.processInfo.environment["CODEX_MONITOR_REAL_APPROVAL_LOG_ID"],
              let logID = Int64(rawLogID) else {
            throw XCTSkip("Set CODEX_MONITOR_REAL_APPROVAL_DB and CODEX_MONITOR_REAL_APPROVAL_LOG_ID to run the exact local probe")
        }
        let database = URL(fileURLWithPath: path)
        let identity = try XCTUnwrap(FileIdentity.readOnlyIdentity(of: database))
        let adapter = ApprovalLocalAdapter(
            databaseURL: database,
            sourceID: ApprovalLocalSourceID("production-exact-row-probe")!,
            schema: .init(acceptedUserVersions: [0]),
            checkpoint: ApprovalLogCursor(fileIdentity: identity, lastLogID: logID - 1),
            retryPolicy: .init(maximumRowsPerPoll: 1)
        )

        let result = try adapter.poll()
        XCTAssertEqual(result.cursor?.lastLogID, logID)
        let request = try XCTUnwrap(result.observations.compactMap { observation -> ApprovalRequested? in
            guard case .requested(let request) = observation else { return nil }
            return request
        }.first)
        XCTAssertTrue(ApprovalRequestCorrelation.isTurnScoped(request.requestID, for: request.turnID))
    }

    func testInstalledApprovalDatabaseAdmitsLifecycleEvidence() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEX_MONITOR_REAL_APPROVAL_DB"] else {
            throw XCTSkip("Set CODEX_MONITOR_REAL_APPROVAL_DB to run the local read-only probe")
        }
        let adapter = ApprovalLocalAdapter(
            databaseURL: URL(fileURLWithPath: path),
            sourceID: ApprovalLocalSourceID("production-path-probe")!,
            schema: .init(acceptedUserVersions: [0]),
            retryPolicy: .init(maximumRowsPerPoll: 2_048)
        )

        var requests = 0
        var resolutions = 0
        var reducerResolutionTransitions = 0
        var lastCursor: ApprovalLogCursor?
        var sawUnavailable = false
        var recoveredAfterUnavailable = false
        let engine = RuntimeStateEngine(initialPhase: .live)
        for _ in 0..<128 {
            let result = try adapter.poll()
            if result.health.state == .unavailable { sawUnavailable = true }
            if sawUnavailable && result.health.state == .available { recoveredAfterUnavailable = true }
            for value in result.observations {
                switch value {
                case .requested(let request):
                    requests += 1
                    // The approval log is the sole source under test.  This
                    // envelope only establishes the reducer's exact active
                    // turn context; no prompt, body, or identifier leaves the
                    // typed boundary.
                    engine.ingest(RolloutRecordEnvelope(threadID: request.threadID, turnID: request.turnID, itemID: nil, kind: .taskStarted, activity: nil, tokenSnapshot: nil, model: nil, reasoningEffort: nil, eventID: nil, authoritativeEventAt: request.observedAt, observedAt: request.observedAt, fileOffset: 0))
                    engine.ingest(value)
                    XCTAssertTrue(engine.snapshot().threads.first { $0.threadID == request.threadID }?.approvalRequestObserved == true)
                case .resolved(let resolution):
                    resolutions += 1
                    let before = engine.snapshot().threads.first { $0.threadID == resolution.threadID }?.state
                    engine.ingest(value)
                    let after = engine.snapshot().threads.first { $0.threadID == resolution.threadID }?.state
                    if before != after { reducerResolutionTransitions += 1 }
                    XCTAssertFalse(adapter.lifecycleCheckpoint().unresolved.contains { $0.threadID == resolution.threadID && $0.turnID == resolution.turnID && $0.requestID == resolution.requestID })
                case .sourceHealth, .sourceUnavailable: break
                }
            }
            guard result.cursor != lastCursor else { break }
            lastCursor = result.cursor
        }
        XCTAssertGreaterThan(requests, 0, "must admit at least one installed request")
        XCTAssertGreaterThan(resolutions, 0, "must admit at least one installed exact resolution")
        XCTAssertEqual(reducerResolutionTransitions, 0, "V1 does not project backend resolution into the main approval lifecycle")
        XCTAssertTrue(recoveredAfterUnavailable, "a malformed historical row must not leave the source permanently unavailable")
        XCTAssertNotNil(lastCursor, "read-only source must advance a cursor")
    }

    func testInstalledRolloutOutputCompletionAndTerminalProvenance() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEX_MONITOR_REAL_ROLLOUT"] else {
            throw XCTSkip("Set CODEX_MONITOR_REAL_ROLLOUT to run the local read-only probe")
        }
        let header = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)).read(upToCount: 65_536) ?? Data()
        let session = try XCTUnwrap(header.split(separator: 0x0A).compactMap { line -> String? in
            guard let value = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  value["type"] as? String == "session_meta",
                  let payload = value["payload"] as? [String: Any] else { return nil }
            return payload["id"] as? String
        }.first)
        let source = DesktopLocalSourceID("production-path-probe")!
        let binding = try XCTUnwrap(ThreadRolloutBinding(sourceID: source, threadRawID: session, rolloutURL: URL(fileURLWithPath: path), sessionID: session))
        // This is an opt-in historical validation probe, so its bounded tail
        // covers the selected local fixture; production remains on its small
        // incremental tail and checkpoint hydration path.
        let result = RolloutIncrementalReader(binding: binding, maxTailBytes: 8_000_000).poll()
        let records = result.observations.compactMap { observation -> RolloutRecordEnvelope? in
            if case .rollout(let record) = observation { return record }
            return nil
        }
        XCTAssertTrue(records.contains { $0.activity == .agentResponse && $0.itemID != nil }, "real function/custom-tool output must use reducer completion mapping")
        let terminal = try XCTUnwrap(records.first { [.taskCompletedSuccess, .taskCompletedFailure, .turnAbortedInterrupted].contains($0.kind) })
        XCTAssertNotNil(terminal.eventID)
        XCTAssertNotNil(terminal.authoritativeEventAt)
        XCTAssertNotEqual(terminal.authoritativeEventAt, terminal.observedAt)
    }

    func testInstalledApprovalInstallerCatchesUpBeforeLive() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEX_MONITOR_REAL_APPROVAL_DB"] else {
            throw XCTSkip("Set CODEX_MONITOR_REAL_APPROVAL_DB to run the local read-only probe")
        }
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("codex-monitor-installed-approval-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ApprovalLifecycleCheckpointStore(url: root.appendingPathComponent("checkpoint.json"))
        let approvals = try ApprovalLifecycleRuntimeOwner(databaseURL: URL(fileURLWithPath: path), sourceID: ApprovalLocalSourceID("production-installer-probe")!, schema: .init(acceptedUserVersions: [0]), store: store)
        let desktopSource = DesktopLocalSourceID("production-installer-probe")!
        let desktop = DesktopLocalAdapter(sourceID: desktopSource, validatedSessionRoots: [], stateDB: StateDBReader(databaseURL: root.appendingPathComponent("unused-state.sqlite"), sourceID: desktopSource, schema: .init(acceptedUserVersions: [0])))
        let engine = RuntimeStateEngine()
        let installer = LocalRuntimeReconciliationInstaller(desktop: desktop, approvals: approvals, engine: engine)

        XCTAssertTrue(try installer.install(threadCheckpoints: []).isEmpty)
        XCTAssertGreaterThan(try XCTUnwrap(installer.lastApprovalCatchUp).polls, 1, "a fresh installed source must not become live after one approval poll")
        XCTAssertNotEqual(engine.snapshot().state, .paused)
    }
}
