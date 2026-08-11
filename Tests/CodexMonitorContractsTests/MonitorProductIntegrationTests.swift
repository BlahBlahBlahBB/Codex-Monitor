import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import CodexMonitorApp
@testable import CodexMonitorContracts

@MainActor
final class MonitorProductIntegrationTests: XCTestCase {
    func testFloatingWindowPreferencesPersistAndClampSize() {
        let suite = "CodexMonitorTests.preferences.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Could not create isolated preferences")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = MonitorPreferences(defaults: defaults)
        preferences.showOrb = false
        preferences.showUsageMenu = false
        preferences.showSettingsMenu = false
        preferences.orbSize = 240
        preferences.orbOrigin = CGPoint(x: 225, y: 340)
        preferences.flushPersistence()

        let restored = MonitorPreferences(defaults: defaults)
        XCTAssertFalse(restored.showOrb)
        XCTAssertFalse(restored.showUsageMenu)
        XCTAssertFalse(restored.showSettingsMenu)
        XCTAssertEqual(restored.orbSize, 180)
        XCTAssertEqual(restored.orbOrigin, CGPoint(x: 225, y: 340))
    }

    func testFreshFloatingOrbDefaultAndTransparentHostContract() {
        let suite = "CodexMonitorTests.freshPreferences.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Could not create isolated preferences")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = MonitorPreferences(defaults: defaults)
        XCTAssertEqual(preferences.orbSize, 90)
        XCTAssertEqual(FloatingOrbSurfaceConfiguration.quickViewSize, CGSize(width: 350, height: 214))
        XCTAssertFalse(FloatingOrbSurfaceConfiguration.isOpaque)
        XCTAssertFalse(FloatingOrbSurfaceConfiguration.hasPanelShadow)
        let host = OrbHostingView(rootView: FloatingOrbRoot(model: MonitorAppModel(), preferences: preferences, action: {}), menuProvider: { NSMenu() })
        XCTAssertFalse(host.isOpaque)
    }

    func testNativeSurfaceOwnershipPreventsDuplicateControllers() {
        let ownership = MonitorSurfaceOwnership()
        XCTAssertTrue(ownership.acquire(.statusItem))
        XCTAssertFalse(ownership.acquire(.statusItem))
        XCTAssertTrue(ownership.acquire(.usage))
        XCTAssertFalse(ownership.acquire(.usage))
        XCTAssertTrue(ownership.owns(.usage))
        ownership.reset()
        XCTAssertFalse(ownership.owns(.usage))
    }

    func testSettingsAlwaysHasAStableDefaultDetailRoute() {
        XCTAssertEqual(SettingsSection.defaultSection, .floating)
        XCTAssertEqual(SettingsSection.allCases.count, 6)
        XCTAssertEqual(SettingsSection.defaultSection.title, L10n.tr("settings.floating"))
    }

    func testActionRowAndBilingualLocalizationContracts() {
        XCTAssertEqual(UIInteractionContract.minimumActionRowHeight, 36)
        XCTAssertEqual(UIInteractionContract.disabledOpacity, 0.42)
        XCTAssertEqual(L10n.tr("menu.refresh", languageCode: "en"), "Refresh")
        XCTAssertEqual(L10n.tr("menu.refresh", languageCode: "zh-Hans"), "刷新")
        XCTAssertEqual(L10n.tr("menu.alwaysOnTopUnavailable", languageCode: "zh-Hans"), "始终置顶（不可用）")
        XCTAssertEqual(PopoverActionFeedback.surfaceOpacity(for: .rest), 0)
        XCTAssertEqual(PopoverActionFeedback.surfaceOpacity(for: .hover), 0.09)
        XCTAssertEqual(PopoverActionFeedback.surfaceOpacity(for: .pressed), 0.16)
        XCTAssertEqual(PopoverActionFeedback.surfaceOpacity(for: .keyboardFocus), 0)
        XCTAssertEqual(PopoverActionFeedback.surfaceOpacity(for: .disabled), 0)
    }

    func testRestoredFloatingWindowOriginStaysInsideAnAvailableScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1_200, height: 900)]
        let origin = FloatingPanelLayout.clampedOrigin(
            CGPoint(x: -50, y: 1_100),
            size: CGSize(width: 120, height: 120),
            screens: screens
        )

        XCTAssertEqual(origin, CGPoint(x: 12, y: 768))
    }

    func testQuickViewIsPlacedBesideOrbAndNeverClipped() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let desired = CGSize(width: 300, height: 270)

        let left = FloatingPanelLayout.quickViewFrame(
            orbFrame: CGRect(x: 20, y: 20, width: 96, height: 96),
            desiredSize: desired,
            visibleFrame: visible
        )
        let right = FloatingPanelLayout.quickViewFrame(
            orbFrame: CGRect(x: 1_084, y: 680, width: 96, height: 96),
            desiredSize: desired,
            visibleFrame: visible
        )

        XCTAssertGreaterThanOrEqual(left.minX, 12)
        XCTAssertEqual(left.minX, 128)
        XCTAssertGreaterThanOrEqual(right.minX, 12)
        XCTAssertLessThanOrEqual(right.maxX, visible.maxX - 12)
        XCTAssertGreaterThanOrEqual(right.minY, 12)
        XCTAssertLessThanOrEqual(right.maxY, visible.maxY - 12)
    }

    func testOrbResizePreservesCentreBeforeApplyingEdgeClamp() {
        let screens = [CGRect(x: 0, y: 0, width: 1_200, height: 900)]
        let origin = FloatingPanelLayout.centerPreservingOrigin(
            center: CGPoint(x: 600, y: 450),
            size: CGSize(width: 180, height: 180),
            screens: screens
        )
        XCTAssertEqual(origin, CGPoint(x: 510, y: 360))
    }

    func testUnsafeTaskTitleIsReplacedByGenericPresentationCopy() {
        XCTAssertEqual(
            MonitorDisplayValue.taskTitleForPresentation("The following is Codex agent history and hidden context"),
            L10n.tr("activity.currentTask")
        )
        XCTAssertEqual(MonitorDisplayValue.taskTitleForPresentation("Implement the status view"), "Implement the status view")
    }

    func testSettingsControllerRetainsOneRootForThirtyCloseReopenCycles() {
        let suite = "CodexMonitorTests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(preferences: MonitorPreferences(defaults: defaults), showDiagnostics: {})
        let root = controller.window?.contentView
        XCTAssertNotNil(root)
        XCTAssertEqual(controller.presentation.selection, .floating)

        for index in 0..<30 {
            controller.show()
            XCTAssertTrue(controller.window?.isVisible == true, "open cycle \(index)")
            XCTAssertTrue(controller.window?.contentView === root, "root replacement on cycle \(index)")
            controller.presentation.selection = SettingsSection.allCases[index % SettingsSection.allCases.count]
            XCTAssertNotNil(controller.window?.contentView, "missing detail host on cycle \(index)")
            controller.close()
            XCTAssertFalse(controller.window?.isVisible == true, "close cycle \(index)")
        }
        controller.show()
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertTrue(controller.window?.contentView === root)
        controller.close()
    }

    func testAccountUsageProviderMapsAuthoritativeReadShapesAndQuotaRemaining() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let observedAt = Date()
        let account: JSONValue = .object(["account": .object(["type": .string("chatgpt"), "planType": .string("pro"), "email": .string("user@example.test")])])
        let limits: JSONValue = .object([
            "rateLimits": .object(["primary": .object(["usedPercent": .number(40), "windowDurationMins": .number(300), "resetsAt": .number(1_725_001_000)]), "secondary": .null]),
            "rateLimitsByLimitId": .object(["codex": .object(["primary": .object(["usedPercent": .number(70), "windowDurationMins": .number(60), "resetsAt": .number(1_725_000_500)]), "secondary": .null])]),
            "rateLimitResetCredits": .object(["availableCount": .number(2)])
        ])
        let date = DateFormatter()
        date.calendar = calendar; date.locale = Locale(identifier: "en_US_POSIX"); date.timeZone = calendar.timeZone; date.dateFormat = "yyyy-MM-dd"
        let today = date.string(from: observedAt)
        let usage: JSONValue = .object(["summary": .object(["lifetimeTokens": .number(900)]), "dailyUsageBuckets": .array([.object(["startDate": .string(today), "tokens": .number(45)])])])

        let mapped = try AccountUsageProvider.snapshot(accountResponse: account, rateLimitsResponse: limits, usageResponse: usage, observedAt: observedAt, calendar: calendar)
        XCTAssertEqual(mapped.authMode, "chatgpt")
        XCTAssertEqual(mapped.planType, "pro")
        XCTAssertEqual(mapped.primaryRateLimit?.usedPercent, 70)
        XCTAssertEqual(mapped.resetCreditCount, 2)
        XCTAssertEqual(mapped.usage?.dailyBuckets?.count, 30)
        XCTAssertEqual(mapped.usage?.dailyBuckets?.last?.tokens, 45)

        let runtime = MonitorRuntimeStore(initialPhase: .live)
        await runtime.ingest(account: mapped)
        let snapshot = await runtime.snapshot()
        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "30%")
        XCTAssertEqual(MonitorDisplayValue.todayUsage(snapshot), "45 Token")
    }
}
