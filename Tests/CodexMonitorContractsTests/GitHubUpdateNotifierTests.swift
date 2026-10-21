import Foundation
import XCTest
@testable import CodexMonitorApp

final class GitHubUpdateNotifierTests: XCTestCase {
    private func version(_ marketing: String, build: String? = nil) -> GitHubUpdateVersion {
        try! XCTUnwrap(GitHubUpdateVersion(marketing: marketing, build: build))
    }

    private func release(_ tag: String, prerelease: Bool = false, draft: Bool = false) -> GitHubReleaseRecord {
        GitHubReleaseRecord(tagName: tag, prerelease: prerelease, draft: draft)
    }

    func testFixedOfficialEndpointAndRequestHeaders() async throws {
        let client = GitHubReleaseAPIClient { request in
            XCTAssertEqual(request.url, GitHubReleaseAPIClient.latestEndpoint)
            XCTAssertEqual(request.timeoutInterval, 12)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
            return GitHubReleaseHTTPResponse(
                data: Data(#"{"tag_name":"v9.1.0","prerelease":false,"draft":false}"#.utf8),
                statusCode: 200
            )
        }
        let received = try await client.latestRelease()
        XCTAssertEqual(received, release("v9.1.0"))
        XCTAssertEqual(GitHubReleaseAPIClient.repository, "BlahBlahBlahBB/Codex-Monitor")
    }

    func testNon200InvalidJSONMissingFieldsAndTimeoutAreRejected() async {
        let non200 = GitHubReleaseAPIClient { _ in GitHubReleaseHTTPResponse(data: Data(), statusCode: 503) }
        await XCTAssertThrowsErrorAsync(try await non200.latestRelease())

        let invalidJSON = GitHubReleaseAPIClient { _ in GitHubReleaseHTTPResponse(data: Data("not json".utf8), statusCode: 200) }
        await XCTAssertThrowsErrorAsync(try await invalidJSON.latestRelease())

        let missingFields = GitHubReleaseAPIClient { _ in GitHubReleaseHTTPResponse(data: Data(#"{"tag_name":"v1.0.13"}"#.utf8), statusCode: 200) }
        await XCTAssertThrowsErrorAsync(try await missingFields.latestRelease())

        let timedOut = GitHubReleaseAPIClient { _ in throw URLError(.timedOut) }
        await XCTAssertThrowsErrorAsync(try await timedOut.latestRelease())
    }

    func testOldAndCurrentReleasesDoNotNotify() {
        let current = version("1.0.12", build: "115")
        XCTAssertEqual(GitHubUpdateEvaluation.evaluate(release: release("v1.0.11"), current: current), .notNewer)
        XCTAssertEqual(GitHubUpdateEvaluation.evaluate(release: release("v1.0.12"), current: current), .notNewer)
    }

    func testHigherSemanticVersionNotifiesAndMissingBuildIsNotGuessed() {
        let current = version("1.0.12", build: "115")
        XCTAssertEqual(GitHubUpdateEvaluation.evaluate(release: release("v1.0.13"), current: current), .update(release("v1.0.13")))
        XCTAssertEqual(GitHubUpdateEvaluation.evaluate(release: release("v1.0.12"), current: current), .notNewer)
        XCTAssertEqual(GitHubUpdateEvaluation.evaluate(release: release("v1.0.12+116"), current: current), .update(release("v1.0.12+116")))
    }

    func testInvalidPrereleaseAndDraftReleasesAreIgnored() {
        let current = version("1.0.12", build: "115")
        XCTAssertEqual(GitHubUpdateEvaluation.evaluate(release: release("release/1.0.13"), current: current), .ignored)
        XCTAssertEqual(GitHubUpdateEvaluation.evaluate(release: release("v1.0.13-beta"), current: current), .ignored)
        XCTAssertEqual(GitHubUpdateEvaluation.evaluate(release: release("v1.0.13", prerelease: true), current: current), .ignored)
        XCTAssertEqual(GitHubUpdateEvaluation.evaluate(release: release("v1.0.13", draft: true), current: current), .ignored)
    }

    func testReleasePageIsFixedToOfficialRepositoryAndRejectsInjectedTag() throws {
        let page = try XCTUnwrap(GitHubUpdateNotifier.officialReleasePage(for: "v1.0.13"))
        XCTAssertEqual(page.absoluteString, "https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/v1.0.13")
        XCTAssertNil(GitHubUpdateNotifier.officialReleasePage(for: "v1.0.13?redirect=https://example.invalid"))
        XCTAssertNil(GitHubUpdateNotifier.officialReleasePage(for: "v1.0.13/../../evil"))
    }

    func testReminderDedupesSameVersionButPermitsNewerVersionAndExpiry() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let interval = GitHubUpdateNotifier.automaticInterval
        XCTAssertFalse(GitHubUpdateReminderPolicy.shouldPrompt(lastTag: "v1.0.13", lastPrompt: now.addingTimeInterval(-60), candidateTag: "v1.0.13", now: now, interval: interval))
        XCTAssertTrue(GitHubUpdateReminderPolicy.shouldPrompt(lastTag: "v1.0.13", lastPrompt: now.addingTimeInterval(-60), candidateTag: "v1.0.14", now: now, interval: interval))
        XCTAssertTrue(GitHubUpdateReminderPolicy.shouldPrompt(lastTag: "v1.0.13", lastPrompt: now.addingTimeInterval(-interval), candidateTag: "v1.0.13", now: now, interval: interval))
    }

    func testCheckGateCoalescesAndCancellationPreventsLateCompletion() async {
        let gate = GitHubUpdateCheckGate()
        let first = await gate.begin()
        XCTAssertNotNil(first)
        let concurrent = await gate.begin()
        XCTAssertNil(concurrent)
        await gate.cancel()
        let firstFinish = await gate.finish(try! XCTUnwrap(first))
        XCTAssertFalse(firstFinish)
        let second = await gate.begin()
        XCTAssertNotNil(second)
        let secondFinish = await gate.finish(try! XCTUnwrap(second))
        XCTAssertTrue(secondFinish)
    }

    func testAutomaticCadenceIsTwentyFourHoursAndStartupDelayIsConfigured() {
        XCTAssertEqual(GitHubUpdateNotifier.automaticInterval, 24 * 60 * 60)
        XCTAssertEqual(GitHubUpdateNotifier.startupDelay, .seconds(8))
    }

    func testUpdateLocalizationHasEnglishAndSimplifiedChineseCopy() {
        for key in ["update.check", "update.checking", "update.upToDate", "update.available", "update.currentVersion", "update.releaseNotes", "update.downloadGitHub", "update.remindLater", "update.unavailable"] {
            XCTAssertNotEqual(L10n.tr(key, languageCode: "en"), key)
            XCTAssertNotEqual(L10n.tr(key, languageCode: "zh-Hans"), key)
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
