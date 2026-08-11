import XCTest
@testable import CodexMonitorContracts

/// Opt-in read-only validation against an installed Codex source.  It carries
/// no body text or production identifiers into test output or assertions.
final class ProductionPathValidationTests: XCTestCase {
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
        var lastCursor: ApprovalLogCursor?
        var sawUnavailable = false
        var recoveredAfterUnavailable = false
        for _ in 0..<128 {
            let result = try adapter.poll()
            if result.health.state == .unavailable { sawUnavailable = true }
            if sawUnavailable && result.health.state == .available { recoveredAfterUnavailable = true }
            for value in result.observations {
                switch value {
                case .requested: requests += 1
                case .resolved: break
                case .sourceHealth, .sourceUnavailable: break
                }
            }
            guard result.cursor != lastCursor else { break }
            lastCursor = result.cursor
        }
        XCTAssertGreaterThan(requests, 0, "must admit at least one installed request")
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
}
