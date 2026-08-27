import Foundation
import UserNotifications
import XCTest
@testable import CodexMonitorApp
@testable import CodexMonitorContracts

final class UniversalCompatibilityTests: XCTestCase {
    func testTrustedCodexDiscoveryUsesOnlyTheResolvedCodexDesktopBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexMonitorBundle-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("Codex.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let executable = resources.appendingPathComponent("codex")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": TrustedCodexBundledExecutableResolver.bundleIdentifier]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolver = TrustedCodexBundledExecutableResolver(applicationURL: { app })
        XCTAssertEqual(try resolver.resolve(), executable.standardizedFileURL)
    }

    func testTrustedCodexDiscoveryRejectsNonBundleAndDoesNotUsePath() {
        let resolver = TrustedCodexBundledExecutableResolver(applicationURL: { URL(fileURLWithPath: "/bin/sh") })
        XCTAssertThrowsError(try resolver.resolve()) { error in
            XCTAssertEqual(error as? TrustedCodexStdioError, .untrustedBundle)
        }
    }

    func testSocketTransportFailureUsesOnlyTheTrustedStdioFallbackPath() {
        XCTAssertTrue(AccountUsageProvider.isFallbackEligible(JSONRPCTransportError.connectionClosed))
        XCTAssertFalse(AccountUsageProvider.isFallbackEligible(JSONRPCTransportError.malformedMessage(.malformedShape)))
        let unavailableBundle = TrustedCodexBundledExecutableResolver(applicationURL: { nil })
        XCTAssertThrowsError(try unavailableBundle.resolve()) { error in
            XCTAssertEqual(error as? TrustedCodexStdioError, .applicationNotFound)
        }
    }

    func testNotificationAuthorizationEnvironmentMapping() {
        XCTAssertEqual(notificationAuthorizationDisposition(for: .notDetermined), .requestThenEnable)
        XCTAssertEqual(notificationAuthorizationDisposition(for: .authorized), .enableImmediately)
        XCTAssertEqual(notificationAuthorizationDisposition(for: .denied), .doNotEnable)
    }
}
