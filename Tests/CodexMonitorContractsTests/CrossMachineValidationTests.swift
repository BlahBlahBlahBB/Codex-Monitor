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
                XCTAssertTrue(body.contains("Add :UIBuildRevision string $build_revision"))
                XCTAssertTrue(body.contains("git -C \"$project_root\" rev-parse HEAD"))
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

    func testApprovalObserverLifecycleIsIndependentOfNotificationDeliveryPreference() throws {
        let root = projectRoot
        let coordinator = try String(contentsOf: root.appendingPathComponent("Sources/CodexMonitorApp/MonitorSurfaceCoordinator.swift"), encoding: .utf8)
        let appDelegate = try String(contentsOf: root.appendingPathComponent("Sources/CodexMonitorApp/CodexMonitorApp.swift"), encoding: .utf8)

        XCTAssertTrue(coordinator.contains("activateApprovalObserver()"))
        XCTAssertFalse(coordinator.contains("approvalPreferenceObserver"))
        XCTAssertFalse(coordinator.contains("waitingApprovalNotifications"))
        XCTAssertTrue(appDelegate.contains("_ = await approvalIntegration.reconcile(enabled: true)"))
        XCTAssertFalse(appDelegate.contains("preferences.waitingApprovalNotifications = false"))
    }

    func testSparkleIsTheOnlyActiveInAppUpdaterAndPackagingPreservesItsTrustBoundary() throws {
        let root = projectRoot
        let appDelegate = try String(contentsOf: root.appendingPathComponent("Sources/CodexMonitorApp/CodexMonitorApp.swift"), encoding: .utf8)
        let updater = try String(contentsOf: root.appendingPathComponent("Sources/CodexMonitorApp/SparkleUpdateController.swift"), encoding: .utf8)
        let package = try String(contentsOf: root.appendingPathComponent("Tools/package_release.sh"), encoding: .utf8)
        let appcastTool = try String(contentsOf: root.appendingPathComponent("Tools/SparkleRelease/generate_appcast.sh"), encoding: .utf8)

        XCTAssertTrue(appDelegate.contains("sparkleUpdates.start(\n            language: localization.resolvedLanguage,"))
        XCTAssertTrue(appDelegate.contains("sparkleUpdates.checkForUpdates(language: localization.resolvedLanguage)"))
        XCTAssertTrue(appDelegate.contains("LocalizationController.systemPreferredLanguages"))
        XCTAssertFalse(appDelegate.contains("GitHubUpdateNotifier()"))
        XCTAssertFalse(appDelegate.contains("updateNotifier.scheduleStartupCheck()"))
        XCTAssertTrue(updater.contains("SPUStandardUpdaterController"))
        XCTAssertTrue(updater.contains("checkForUpdates(nil)"))

        XCTAssertTrue(package.contains("SPARKLE_PUBLIC_ED25519_KEY is required"))
        XCTAssertTrue(package.contains("SPARKLE_FEED_URL must use HTTPS"))
        XCTAssertTrue(package.contains("ditto \"$sparkle_framework\""))
        XCTAssertTrue(package.contains("-name '*.app'"))
        XCTAssertTrue(package.contains("--keepParent \"$app_path\" \"$update_zip_path\""))
        XCTAssertTrue(package.contains("SUAutomaticallyUpdate bool false"))
        XCTAssertTrue(package.contains("CFBundleLocalizations:1 string zh-Hans"))
        XCTAssertTrue(package.contains("CFBundleLocalizations:2 string zh_CN"))
        XCTAssertTrue(package.contains("CFBundleAllowMixedLocalizations bool true"))
        XCTAssertTrue(package.contains("AppBundleLocalizations"))
        XCTAssertFalse(package.contains("disable-library-validation"))
        XCTAssertTrue(package.contains("if [[ \"$signing_identity\" == \"-\" ]]; then\n    \"$codesign_tool\" --force --sign - \"$code_path\""))
        XCTAssertTrue(appcastTool.contains("SPARKLE_ALLOW_INSECURE_LOCALHOST"))
        XCTAssertTrue(appcastTool.contains("Update assets must use HTTPS"))
        XCTAssertTrue(appcastTool.contains("com.codexmonitor.sparkle.production.v1"))
        XCTAssertTrue(appcastTool.contains("SPARKLE_ED25519_KEY_SOURCE"))
        XCTAssertTrue(appcastTool.contains("Recovery-file mode requires SPARKLE_ED25519_RECOVERY_OR_CI_AUTHORIZATION=approved"))
        XCTAssertTrue(appcastTool.contains("Required Keychain signing identity is unavailable"))
        XCTAssertTrue(appcastTool.contains("SUPublicEDKey does not match the selected signing identity"))
        XCTAssertTrue(appcastTool.contains("Production enclosure URL prefix must be"))
        XCTAssertTrue(appcastTool.contains("No Ed25519 enclosure signature found"))
        XCTAssertTrue(appcastTool.contains("--verify \"${signing_args[@]}\""))
        XCTAssertTrue(appcastTool.contains("--maximum-deltas \"$maximum_deltas\""))
    }

    func testSparkleLanguageMappingKeepsSimplifiedChineseOnSparkleResourceIdentifier() {
        XCTAssertEqual(SparkleLocalization.driverLanguage(for: "zh-Hans"), "zh_CN")
        XCTAssertEqual(SparkleLocalization.driverLanguage(for: "zh_CN"), "zh_CN")
        XCTAssertEqual(SparkleLocalization.driverLanguage(for: "en"), "en")
        XCTAssertEqual(SparkleLocalization.driverLanguage(for: "fr"), "en")
    }

    func testSparkleLaunchLanguagePersistsForTheNextNativeFrameworkLoad() {
        let suite = "com.codexmonitor.tests.sparkle-localization.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // A Chinese app selection on an English system needs one controlled
        // restart the first time it is persisted. The next native framework
        // load sees the matching app-only AppleLanguages value.
        let chineseFirstLaunch = SparkleLocalization.prepareForLaunch(
            preference: .simplifiedChinese,
            defaults: defaults,
            persistentDomainName: suite,
            systemPreferredLanguages: ["en"]
        )
        XCTAssertEqual(chineseFirstLaunch.driverLanguage, "en")
        XCTAssertFalse(chineseFirstLaunch.nativeDriverMatchesSelection)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages")?.first, "zh_CN")

        let chineseRestart = SparkleLocalization.prepareForLaunch(
            preference: .simplifiedChinese,
            defaults: defaults,
            persistentDomainName: suite,
            systemPreferredLanguages: ["en"]
        )
        XCTAssertEqual(chineseRestart.driverLanguage, "zh_CN")
        XCTAssertTrue(chineseRestart.nativeDriverMatchesSelection)

        // The inverse case models an English app selection on a Chinese
        // system, without changing the real macOS language list.
        defaults.removeObject(forKey: "AppleLanguages")
        let englishFirstLaunch = SparkleLocalization.prepareForLaunch(
            preference: .english,
            defaults: defaults,
            persistentDomainName: suite,
            systemPreferredLanguages: ["zh-Hans"]
        )
        XCTAssertEqual(englishFirstLaunch.driverLanguage, "zh_CN")
        XCTAssertFalse(englishFirstLaunch.nativeDriverMatchesSelection)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages")?.first, "en")
    }

    func testCompileTimeQAIsolationPrecedesAllProductionIntegrations() throws {
        let root = projectRoot
        let isolation = try String(contentsOf: root.appendingPathComponent("Sources/CodexMonitorApp/QAIsolation.swift"), encoding: .utf8)
        let appDelegate = try String(contentsOf: root.appendingPathComponent("Sources/CodexMonitorApp/CodexMonitorApp.swift"), encoding: .utf8)
        let coordinator = try String(contentsOf: root.appendingPathComponent("Sources/CodexMonitorApp/MonitorSurfaceCoordinator.swift"), encoding: .utf8)
        let diagnostics = try String(contentsOf: root.appendingPathComponent("Sources/CodexMonitorApp/Diagnostics.swift"), encoding: .utf8)
        let package = try String(contentsOf: root.appendingPathComponent("Tools/package_release.sh"), encoding: .utf8)

        XCTAssertTrue(isolation.contains("#if CODEX_MONITOR_QA_ISOLATION"))
        XCTAssertTrue(isolation.contains("static let expectedBundleIdentifier: String? = \"com.codexmonitor.sparkle.productionqa\""))
        XCTAssertTrue(isolation.contains(".standard"))
        XCTAssertFalse(isolation.contains("UserDefaults(suiteName:"))
        XCTAssertTrue(isolation.contains("static func verifyPackaging()"))
        XCTAssertTrue(isolation.contains("CodexMonitorQAIsolation=true"))
        XCTAssertFalse(isolation.contains("ProcessInfo.processInfo.environment"))

        XCTAssertTrue(appDelegate.contains("QAIsolation.verifyPackaging()"))
        XCTAssertTrue(appDelegate.contains("guard !QAIsolation.enabled else { return }"))
        XCTAssertTrue(appDelegate.contains("if !QAIsolation.enabled {\n            Task { await driver.start() }"))
        XCTAssertTrue(appDelegate.contains("if !QAIsolation.enabled { model.startObserving(usageLedger) }"))
        XCTAssertTrue(appDelegate.contains("private lazy var approvalObserverPaths"))
        XCTAssertTrue(coordinator.contains("self.notifications = qaIsolationEnabled ? nil : MonitorNotificationController()"))
        XCTAssertTrue(coordinator.contains("LoginItemController(reconcileOnInit: !qaIsolationEnabled)"))
        XCTAssertTrue(coordinator.contains("guard !qaIsolationEnabled else { return }\n        guard let url = NSWorkspace.shared.urlForApplication"))
        XCTAssertTrue(diagnostics.contains("guard !QAIsolation.enabled else { return }"))

        XCTAssertTrue(package.contains("QA isolation requires a dedicated, non-production bundle identifier."))
        XCTAssertTrue(package.contains("QA isolation requires its explicit loopback-only Sparkle feed."))
        XCTAssertTrue(package.contains("QA isolation must use the disposable ad-hoc signing path"))
        XCTAssertTrue(package.contains("Production packaging requires BUNDLE_IDENTIFIER=com.codexmonitor.app."))
        XCTAssertTrue(package.contains("Production packaging forbids SPARKLE_ALLOW_INSECURE_LOCALHOST."))
        XCTAssertTrue(package.contains("CODEX_MONITOR_QA_ISOLATION"))
    }

#if CODEX_MONITOR_QA_ISOLATION
    func testQADelegateConstructionDoesNotStartRuntimeInfrastructure() {
        // Construction is intentionally weaker than application launch. It
        // exercises the QA-only property-initialization path without opening
        // Codex transports, touching Hooks, registering notifications, or
        // creating an NSApplication.
        _ = CodexMonitorAppDelegate()
    }
#endif

    func testFreshAccountAbsenceAndSourceRecoveryStaySafeWithoutRestart() async throws {
        let runtime = MonitorRuntimeStore(initialPhase: .live)

        var snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.availability, .unavailable)
        XCTAssertNil(snapshot.account.accountKind)
        XCTAssertEqual(snapshot.quota.primaryAvailability, .stale)
        XCTAssertNil(snapshot.quota.primary)
        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "--")
        XCTAssertNotEqual(MonitorDisplayValue.remainingQuota(snapshot), "0%")

        // This models the first account refresh when Codex is not yet ready.
        // It must not invent a zero quota or a placeholder account.
        await runtime.markAccountRefreshDegraded()
        snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.availability, .unavailable)
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
