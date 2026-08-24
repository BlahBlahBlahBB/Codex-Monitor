import Foundation
import XCTest
@testable import CodexMonitorApp
@testable import CodexMonitorContracts

/// Cross-machine regression coverage intentionally audits only production
/// inputs and uses pure runtime values. It never changes HOME, opens a real
/// Codex socket, or reads an installed user's data.
@MainActor
final class CrossMachineValidationTests: XCTestCase {
    func testProductionInputsContainNoDeveloperMachineBindingOrRuntimeArtifactCopy() throws {
        let root = projectRoot
        let productionInputs = try productionInputURLs(at: root)
        let developerName = "shou" + "chen.nsc"
        let developerBindings = [
            "/Users/" + developerName,
            "Desktop/Blah"
        ]
        let runtimeArtifactNames = [
            "state_5.sqlite",
            "logs_2.sqlite"
        ]

        for url in productionInputs {
            let body = try String(contentsOf: url, encoding: .utf8)
            if url.lastPathComponent == "package_release.sh" {
                XCTAssertTrue(body.contains("project_root=\"$(cd \"$(dirname \"$0\")/..\" && pwd)\""))
                XCTAssertTrue(body.contains("cp \"$executable\""))
                XCTAssertTrue(body.contains("ditto \"$resource_bundle\""))
            }
            for value in developerBindings {
                XCTAssertFalse(body.contains(value), "production input must not contain \(value): \(url.lastPathComponent)")
            }
            if url.lastPathComponent == "package_release.sh" {
                for value in runtimeArtifactNames {
                    XCTAssertFalse(body.contains(value), "release packaging must not copy runtime state: \(value)")
                }
            }
        }
    }

    func testDynamicUserPathCompositionSupportsDistinctHomesSpacesAndUnicode() throws {
        let roots = ["/Users/alice", "/Users/bob", "/Users/Alice Smith", "/Users/测试用户"]
        for root in roots {
            let home = URL(fileURLWithPath: root, isDirectory: true)
            XCTAssertEqual(
                home.appendingPathComponent(".codex/app-server-control/app-server-control.sock").path,
                root + "/.codex/app-server-control/app-server-control.sock"
            )
            XCTAssertEqual(home.appendingPathComponent(".codex/sessions", isDirectory: true).path, root + "/.codex/sessions")
            XCTAssertEqual(home.appendingPathComponent(".codex/state_5.sqlite").path, root + "/.codex/state_5.sqlite")
        }

        let root = projectRoot
        let transport = try String(contentsOf: root.appendingPathComponent("Sources/CodexMonitorContracts/Transport.swift"), encoding: .utf8)
        let desktopDriver = try String(contentsOf: root.appendingPathComponent("Sources/CodexMonitorApp/CodexLocalMonitorDriver.swift"), encoding: .utf8)
        XCTAssertTrue(transport.contains("FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertTrue(desktopDriver.contains("FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(transport.contains("ProcessInfo.processInfo.environment[\"HOME\"]"))
        XCTAssertFalse(desktopDriver.contains("ProcessInfo.processInfo.environment[\"HOME\"]"))
    }

    func testFreshAccountAbsenceAndSourceRecoveryStaySafeWithoutRestart() async throws {
        let runtime = MonitorRuntimeStore(initialPhase: .live)

        var snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.availability, .unknown)
        XCTAssertNil(snapshot.account.accountKind)
        XCTAssertEqual(snapshot.quota.primaryAvailability, .unknown)
        XCTAssertNil(snapshot.quota.primary)
        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "--")
        XCTAssertNotEqual(MonitorDisplayValue.remainingQuota(snapshot), "0%")

        // This models the first account refresh when Codex is not yet ready.
        // It must not invent a zero quota or a placeholder account.
        await runtime.markAccountRefreshDegraded()
        snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.availability, .unknown)
        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "--")

        await runtime.ingest(account: try accountSnapshot(email: "alice@example.test", usedPercent: 40, tokens: 45))
        snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.availability, .available)
        XCTAssertEqual(snapshot.account.plan, "pro")
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 40)
        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "60%")

        // A source disappearance clears values only while it is unavailable;
        // a subsequent successful cycle restores them without a Monitor restart.
        await runtime.markSourceUnavailable(.account)
        snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.availability, .unavailable)
        XCTAssertNil(snapshot.quota.primary)
        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "--")

        await runtime.ingest(account: try accountSnapshot(email: "bob@example.test", usedPercent: 20, tokens: 99))
        snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.availability, .available)
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 20)
        XCTAssertEqual(snapshot.usage.usage?.totalTokens, 99)
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func productionInputURLs(at root: URL) throws -> [URL] {
        let fixed = [
            root.appendingPathComponent("Package.swift"),
            root.appendingPathComponent("Tools/package_release.sh")
        ]
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: [.isRegularFileKey]))
        let sourceFiles = enumerator.compactMap { $0 as? URL }.filter { url in
            ["swift", "strings"].contains(url.pathExtension)
        }
        return fixed + sourceFiles
    }

    private func accountSnapshot(email: String, usedPercent: Double, tokens: Int) throws -> AccountSnapshot {
        let account: JSONValue = .object([
            "account": .object([
                "email": .string(email),
                "planType": .string("pro"),
                "type": .string("chatgpt")
            ])
        ])
        let limits: JSONValue = .object([
            "rateLimits": .object([
                "primary": .object(["usedPercent": .number(usedPercent)])
            ])
        ])
        let usage: JSONValue = .object([
            "summary": .object(["lifetimeTokens": .number(Double(tokens))])
        ])
        return try AccountUsageProvider.snapshot(
            accountResponse: account,
            rateLimitsResponse: limits,
            usageResponse: usage,
            observedAt: Date()
        )
    }
}
