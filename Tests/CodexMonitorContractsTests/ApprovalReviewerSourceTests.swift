import XCTest
import Darwin
@testable import CodexMonitorContracts

final class ApprovalReviewerSourceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("reviewer-source-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testExactUserAndAutoReviewer() throws {
        for reviewer in ["user", "auto_review"] {
            let url = try transcript(context("turn", reviewer))
            XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: url.path, turnID: "turn").rawValue, reviewer)
        }
    }

    func testPreviousUserCurrentAutoAndNewestExactContextWins() throws {
        let url = try transcript(context("old", "user") + context("current", "user") + context("current", "auto_review") + context("other", "user"))
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: url.path, turnID: "current"), .autoReview)
    }

    func testDifferentTranscriptsWithSameTurnNeverShareReviewer() throws {
        let a = try transcript(context("same", "user"), name: "a.jsonl")
        let b = try transcript(context("same", "auto_review"), name: "b.jsonl")
        for _ in 0..<2 {
            XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: a.path, turnID: "same"), .user)
            XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: b.path, turnID: "same"), .autoReview)
        }
    }

    func testMissingTranscriptIsUnknown() {
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: nil, turnID: "turn"), .unknown)
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: root.appendingPathComponent("missing.jsonl").path, turnID: "turn"), .unknown)
    }

    func testMalformedTranscriptIsUnknown() throws {
        let url = try transcript(context("turn", "auto_review") + "{broken}\n")
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: url.path, turnID: "turn"), .unknown)
    }

    func testAbsentTurnAndUnsupportedOrMissingReviewerAreUnknown() throws {
        let url = try transcript(context("old", "auto_review") + context("current", "future-reviewer"))
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: url.path, turnID: "absent"), .unknown)
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: url.path, turnID: "current"), .unknown)
        let missing = try transcript("{\"type\":\"turn_context\",\"payload\":{\"turn_id\":\"current\"}}\n")
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: missing.path, turnID: "current"), .unknown)
    }

    func testOnlyBoundedTailIsReadAndCutFirstLineIsDiscarded() throws {
        let padding = "{\"padding\":\"" + String(repeating: "x", count: ApprovalObserverHookRunner.maximumTranscriptBytes + 100) + "\"}\n"
        let url = try transcript(context("old", "auto_review") + padding + context("current", "user"))
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: url.path, turnID: "old"), .unknown)
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: url.path, turnID: "current"), .user)
    }

    func testIncompleteFinalRecordDoesNotSuppressHumanAttention() throws {
        let url = try transcript(context("turn", "auto_review") + String(context("turn", "user").dropLast()))
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: url.path, turnID: "turn"), .unknown)
    }

    func testNonJSONLDirectorySymlinkAndFIFOReturnUnknown() throws {
        let wrongExtension = try transcript(context("turn", "auto_review"), name: "data.json")
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: wrongExtension.path, turnID: "turn"), .unknown)
        let directory = root.appendingPathComponent("directory.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: directory.path, turnID: "turn"), .unknown)
        let target = try transcript(context("turn", "auto_review"))
        let link = root.appendingPathComponent("link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: link.path, turnID: "turn"), .unknown)
        let fifo = root.appendingPathComponent("pipe.jsonl")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: fifo.path, turnID: "turn"), .unknown)
    }

    func testUnreadableTranscriptIsUnknown() throws {
        let url = try transcript(context("turn", "auto_review"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        XCTAssertEqual(ApprovalObserverHookRunner.transcriptReviewer(path: url.path, turnID: "turn"), .unknown)
    }

    func testHelperJournalsOnlyEnumAndFailureStillJournalsUnknown() throws {
        let transcript = try transcript(context("turn-secret", "auto_review"))
        let paths = AppOwnedApprovalObserverPaths(rootURL: root.appendingPathComponent("observer"))
        for (index, path) in [transcript.path, root.appendingPathComponent("missing.jsonl").path].enumerated() {
            let input = try JSONSerialization.data(withJSONObject: [
                "hook_event_name": "PermissionRequest", "session_id": "session-secret",
                "turn_id": "turn-secret", "transcript_path": path, "tool_input": ["command": "private-command"]
            ])
            XCTAssertTrue(ApprovalObserverHookRunner.run(input: input, paths: paths, keyMaterial: Data("test-key".utf8)))
            let data = try Data(contentsOf: paths.journalURL)
            let lines = data.split(separator: 0x0A)
            let record = try JSONDecoder().decode(HookApprovalJournalRecord.self, from: Data(lines[index]))
            XCTAssertEqual(record.reviewer, index == 0 ? .autoReview : .unknown)
            let serialized = String(decoding: data, as: UTF8.self)
            for secret in [path, "transcript_path", "turn-secret", "session-secret", "private-command", "tool_input"] {
                XCTAssertFalse(serialized.contains(secret))
            }
        }
    }

    func testLegacyJournalAndCheckpointRemainConservativeAndAutoSurvivesRoundTrip() throws {
        let deriver = KeyedHookApprovalIdentityDeriver(keyMaterial: Data("key".utf8))!
        let owner = deriver.owner(sourceRawID: "source", sessionRawID: "session", turnRawID: "turn")!
        for reviewer in [nil, ApprovalReviewer.user, .autoReview, .unknown] {
            let record = HookApprovalJournalRecord(journalEventID: .init(1)!, kind: .permissionRequest, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: 1, reviewer: reviewer)!
            let result = HookApprovalJournalReader().ingest([try JSONEncoder().encode(record)])
            guard case .permissionRequest(let event) = result.events.first else { return XCTFail("Missing event") }
            XCTAssertEqual(event.reviewer, reviewer ?? .unknown)
            let checkpoint = try JSONDecoder().decode(HookApprovalJournalCheckpoint.self, from: JSONEncoder().encode(result.checkpoint))
            XCTAssertEqual(checkpoint.unresolved.first?.reviewer, reviewer ?? .unknown)
        }
        let legacy = HookApprovalPendingEvidence(journalEventID: .init(1)!, owner: owner, observedAt: Date())
        let restored = try JSONDecoder().decode(HookApprovalPendingEvidence.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(restored.reviewer)
    }

    func testJournalRejectsRawReviewerAndReviewerOnResolution() throws {
        let owner = KeyedHookApprovalIdentityDeriver(keyMaterial: Data("key".utf8))!.owner(sourceRawID: "s", sessionRawID: "s", turnRawID: "t")!
        let record = HookApprovalJournalRecord(journalEventID: .init(1)!, kind: .permissionRequest, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: 1, reviewer: .user)!
        let data = try JSONEncoder().encode(record)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["reviewer"] = "private-content"
        XCTAssertThrowsError(try JSONDecoder().decode(HookApprovalJournalRecord.self, from: JSONSerialization.data(withJSONObject: object)))
        object["reviewer"] = "auto_review"
        object["kind"] = "stop"
        XCTAssertThrowsError(try JSONDecoder().decode(HookApprovalJournalRecord.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    private func context(_ turn: String, _ reviewer: String) -> String {
        "{\"type\":\"turn_context\",\"payload\":{\"turn_id\":\"\(turn)\",\"approvals_reviewer\":\"\(reviewer)\"}}\n"
    }
    private func transcript(_ text: String, name: String = "transcript.jsonl") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }
}
