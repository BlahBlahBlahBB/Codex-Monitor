import Foundation
import XCTest
@testable import CodexMonitorApp

final class BundledCodexStdioTransportTests: XCTestCase {
    func testResolverPrefersNewLayoutWhenBothCandidatesExist() throws {
        let fixture = try BundledExecutableFixture()
        defer { fixture.remove() }
        let new = try fixture.executable("codex-cli/bin/codex")
        _ = try fixture.executable("codex")

        XCTAssertEqual(try fixture.resolve(), new.standardizedFileURL)
    }

    func testResolverAcceptsNewLayoutOnly() throws {
        let fixture = try BundledExecutableFixture()
        defer { fixture.remove() }
        let executable = try fixture.executable("codex-cli/bin/codex")
        XCTAssertEqual(try fixture.resolve(), executable.standardizedFileURL)
    }

    func testResolverAcceptsLegacyLayoutOnly() throws {
        let fixture = try BundledExecutableFixture()
        defer { fixture.remove() }
        let executable = try fixture.executable("codex")
        XCTAssertEqual(try fixture.resolve(), executable.standardizedFileURL)
    }

    func testResolverRejectsAbsentCandidates() throws {
        let fixture = try BundledExecutableFixture()
        defer { fixture.remove() }
        XCTAssertThrowsError(try fixture.resolve()) { XCTAssertEqual($0 as? TrustedCodexStdioError, .executableMissing) }
    }

    func testResolverRejectsDirectoryAndNonExecutableCandidate() throws {
        let directoryFixture = try BundledExecutableFixture()
        defer { directoryFixture.remove() }
        try directoryFixture.directory("codex-cli/bin/codex")
        XCTAssertThrowsError(try directoryFixture.resolve()) { XCTAssertEqual($0 as? TrustedCodexStdioError, .executableRejected) }

        let fileFixture = try BundledExecutableFixture()
        defer { fileFixture.remove() }
        _ = try fileFixture.executable("codex-cli/bin/codex", executable: false)
        XCTAssertThrowsError(try fileFixture.resolve()) { XCTAssertEqual($0 as? TrustedCodexStdioError, .executableRejected) }
    }

    func testResolverRejectsSymlinkEscapingBundle() throws {
        let fixture = try BundledExecutableFixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside-codex")
        try Data("#!/bin/sh\n".utf8).write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outside.path)
        let link = fixture.resources.appendingPathComponent("codex-cli/bin/codex")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertThrowsError(try fixture.resolve()) { XCTAssertEqual($0 as? TrustedCodexStdioError, .bundleEscape) }
    }

    func testResolverRejectsFakeBundleIdentifier() throws {
        let fixture = try BundledExecutableFixture(identifier: "example.fake")
        defer { fixture.remove() }
        _ = try fixture.executable("codex-cli/bin/codex")
        XCTAssertThrowsError(try fixture.resolve()) { XCTAssertEqual($0 as? TrustedCodexStdioError, .untrustedBundle) }
    }

    func testPartialLineThenFinishCompletesPendingReadExactlyOnce() async throws {
        let pipe = Pipe()
        let reader = StdioLineReader(handle: pipe.fileHandleForReading)
        let receive = Task { await reader.nextLine() }

        try await waitForPendingRead(in: reader)
        reader.ingestForTesting(Data("{\"partial\":".utf8))
        XCTAssertEqual(reader.pendingReadCountForTesting, 1, "an incomplete line must not complete or discard its receiver")

        reader.finish()
        let result = await receive.value
        XCTAssertNil(result)
        reader.finish()
        XCTAssertEqual(reader.pendingReadCountForTesting, 0)
        pipe.fileHandleForWriting.closeFile()
    }

    func testCompleteLineWinsRaceWithLaterFinish() async throws {
        let pipe = Pipe()
        let reader = StdioLineReader(handle: pipe.fileHandleForReading)
        let receive = Task { await reader.nextLine() }

        try await waitForPendingRead(in: reader)
        reader.ingestForTesting(Data("{\"id\":1}\n".utf8))
        let result = await receive.value
        XCTAssertEqual(result, Data("{\"id\":1}".utf8))

        reader.finish()
        XCTAssertEqual(reader.pendingReadCountForTesting, 0)
        pipe.fileHandleForWriting.closeFile()
    }

    private func waitForPendingRead(in reader: StdioLineReader) async throws {
        for _ in 0..<10_000 {
            if reader.pendingReadCountForTesting == 1 { return }
            await Task.yield()
        }
        throw PendingReadError.notRegistered
    }
}

private final class BundledExecutableFixture {
    let root: URL
    let app: URL
    let resources: URL

    init(identifier: String = TrustedCodexBundledExecutableResolver.bundleIdentifier) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BundledCodexFixture-\(UUID().uuidString)", isDirectory: true)
        app = root.appendingPathComponent("Codex.app", isDirectory: true)
        resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL", "CFBundleName": "Codex"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
    }

    func executable(_ relativePath: String, executable: Bool = true) throws -> URL {
        let url = resources.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url.standardizedFileURL
    }

    func directory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(at: resources.appendingPathComponent(relativePath), withIntermediateDirectories: true)
    }

    func resolve() throws -> URL {
        let application = app
        return try TrustedCodexBundledExecutableResolver(applicationURL: { application }).resolve()
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private enum PendingReadError: Error {
    case notRegistered
}
