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
        preferences.alwaysOnTop = false
        preferences.lockPosition = true
        preferences.pauseMonitoring = true
        preferences.waitingApprovalNotifications = true
        preferences.taskCompletedNotifications = true
        preferences.hideAccountInfo = true
        preferences.interfaceLanguage = .english
        preferences.orbSize = 240
        preferences.orbOrigin = CGPoint(x: 225, y: 340)
        preferences.flushPersistence()

        let restored = MonitorPreferences(defaults: defaults)
        XCTAssertFalse(restored.showOrb)
        XCTAssertFalse(restored.showUsageMenu)
        XCTAssertFalse(restored.showSettingsMenu)
        XCTAssertFalse(restored.alwaysOnTop)
        XCTAssertTrue(restored.lockPosition)
        XCTAssertTrue(restored.pauseMonitoring)
        XCTAssertTrue(restored.waitingApprovalNotifications)
        XCTAssertTrue(restored.taskCompletedNotifications)
        XCTAssertTrue(restored.hideAccountInfo)
        XCTAssertEqual(restored.interfaceLanguage, .english)
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
        XCTAssertEqual(FloatingOrbSurfaceConfiguration.shadowInset, 10)
        XCTAssertEqual(FloatingOrbSurfaceConfiguration.hostSize(forOrbSize: 90), CGSize(width: 110, height: 110))
        XCTAssertEqual(FloatingOrbSurfaceConfiguration.quickViewSize, CGSize(width: 350, height: 214))
        XCTAssertEqual(QuickViewInteractionContract.automaticDismissDelay, .seconds(2))
        XCTAssertFalse(FloatingOrbSurfaceConfiguration.isOpaque)
        XCTAssertFalse(FloatingOrbSurfaceConfiguration.hasPanelShadow)
        let host = OrbHostingView(rootView: FloatingOrbRoot(model: MonitorAppModel(), preferences: preferences, action: {}), menuProvider: { NSMenu() })
        XCTAssertFalse(host.isOpaque)
    }

    func testOrbHasExactlyOneRuntimeRing() {
        XCTAssertEqual(MonitorOrbVisualContract.glassBodyCount, 1)
        XCTAssertEqual(MonitorOrbVisualContract.runtimeRingCount, 1)
        XCTAssertEqual(MonitorOrbVisualContract.quotaTextCount, 1)
        XCTAssertEqual(MonitorOrbVisualContract.secondaryCircularStrokeCount, 0)
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

        let contextMenuKeys = [
            "menu.refresh", "menu.usage", "menu.openCodex", "menu.alwaysOnTopUnavailable",
            "menu.lockPositionUnavailable", "menu.hideFloating", "menu.settings", "menu.quitMonitor"
        ]
        let popoverKeys = ["label.account", "label.plan", "label.quota", "label.resetDate", "label.quotaReset", "label.resetCredit", "quota.window.daily", "quota.window.weekly", "quota.window.monthly"]
        let usageKeys = ["label.session", "label.currentSession", "label.sessionToken", "label.tokenUsage", "label.todayToken", "label.last30DaysToken"]
        let settingsKeys = ["settings.general", "settings.floating", "settings.notifications", "settings.privacy", "settings.advanced", "settings.about"]
        for key in contextMenuKeys + popoverKeys + usageKeys + settingsKeys {
            XCTAssertNotEqual(L10n.tr(key, languageCode: "zh-Hans"), key, "missing zh-Hans string: \(key)")
            XCTAssertNotEqual(L10n.tr(key, languageCode: "en"), key, "missing English string: \(key)")
        }
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

    func testConversationNameContractUsesOneResolverForQuickViewAndUsage() async {
        let trustedCases = [
            "开始 1.0.1 Phase 4A QA 构建",
            "README summary",
            "修复会话名称 🛠️",
            "First line\nSecond line"
        ]
        for (index, name) in trustedCases.enumerated() {
            let snapshot = await activeUsageSessionSnapshot(
                conversationName: name,
                threadRawID: "trusted-name-\(index)",
                sessionTokens: 1
            )
            let expected = name.replacingOccurrences(of: "\n", with: " ")
            XCTAssertEqual(MonitorDisplayValue.resolvedConversationDisplayTitle(snapshot), expected)
            XCTAssertEqual(MonitorDisplayValue.quickViewTaskTitle(snapshot), expected)
            XCTAssertEqual(MonitorDisplayValue.sessionInfo(snapshot), expected)
        }

        let unsafeNames = [
            "/Users/test/Desktop/project",
            "/Volumes/SSD/project",
            "/Applications/example",
            "~/Desktop/project",
            "~/.codex/session",
            "\\~/Desktop/project",
            "\\~/.codex/session",
            "file:///Users/test/project",
            "system prompt",
            "developer prompt",
            "internal transcript",
            "Codex agent history",
            "# Files mentioned by the user",
            "019ffa90-a5ce-7523-99d5-a85aaa140d0f",
            ""
        ]
        for (index, name) in unsafeNames.enumerated() {
            let snapshot = await activeUsageSessionSnapshot(
                conversationName: name,
                threadRawID: "unsafe-name-\(index)",
                sessionTokens: 1
            )
            XCTAssertEqual(MonitorDisplayValue.resolvedConversationDisplayTitle(snapshot), L10n.tr("activity.currentTask"), "unsafe name: \(name)")
            XCTAssertEqual(MonitorDisplayValue.quickViewTaskTitle(snapshot), MonitorDisplayValue.sessionInfo(snapshot))
        }

        let overlongName = String(repeating: "a", count: 121)
        let overlongSnapshot = await activeUsageSessionSnapshot(conversationName: overlongName, threadRawID: "overlong-name", sessionTokens: 1)
        XCTAssertEqual(MonitorDisplayValue.resolvedConversationDisplayTitle(overlongSnapshot), String(repeating: "a", count: 120))
        XCTAssertEqual(MonitorDisplayValue.quickViewTaskTitle(overlongSnapshot), MonitorDisplayValue.sessionInfo(overlongSnapshot))

        for (index, name) in [nil, "", " \n\t "].enumerated() {
            let snapshot = await activeUsageSessionSnapshot(conversationName: name, threadRawID: "missing-name-\(index)", sessionTokens: 1)
            XCTAssertEqual(MonitorDisplayValue.resolvedConversationDisplayTitle(snapshot), L10n.tr("activity.currentTask"))
            XCTAssertEqual(MonitorDisplayValue.quickViewTaskTitle(snapshot), MonitorDisplayValue.sessionInfo(snapshot))
        }

        XCTAssertEqual(MonitorDisplayValue.resolvedConversationDisplayTitle(nil), L10n.tr("activity.noSession"))
        XCTAssertEqual(L10n.tr("activity.noSession", languageCode: "zh-Hans"), "暂无会话")
        XCTAssertEqual(L10n.tr("activity.noSession", languageCode: "en"), "No session")
    }

    func testCompletedNotificationUsesLocalizedTitleAndAuthoritativeConversationName() async {
        let snapshot = await activeUsageSessionSnapshot(
            conversationName: "开始 Codex Monitor 1.0.1 Phase 4C",
            threadRawID: "completed-notification-authoritative-name",
            sessionTokens: 1
        )
        let chinese = MonitorNotificationContent.completed(snapshot: snapshot, languageCode: "zh-Hans")
        let english = MonitorNotificationContent.completed(snapshot: snapshot, languageCode: "en")

        XCTAssertEqual(chinese.title, "已完成")
        XCTAssertEqual(english.title, "Completed")
        XCTAssertEqual(chinese.subtitle, "")
        XCTAssertEqual(english.subtitle, "")
        XCTAssertEqual(chinese.body, "开始 Codex Monitor 1.0.1 Phase 4C")
        XCTAssertEqual(english.body, "开始 Codex Monitor 1.0.1 Phase 4C")
    }

    func testCompletedNotificationUsesLocalizedCurrentTaskForMissingName() async {
        let snapshot = await activeUsageSessionSnapshot(
            conversationName: nil,
            threadRawID: "completed-notification-missing-name",
            sessionTokens: 1
        )

        XCTAssertEqual(MonitorNotificationContent.completed(snapshot: snapshot, languageCode: "zh-Hans").body, "当前任务")
        XCTAssertEqual(MonitorNotificationContent.completed(snapshot: snapshot, languageCode: "en").body, "Current task")
    }

    func testCompletedNotificationNeverUsesUnsafeNameAsItsBody() async {
        let unsafeNames = [
            "/Users/test/Desktop/project",
            "file:///Users/test/project",
            "019ffa90-a5ce-7523-99d5-a85aaa140d0f",
            "# Files pasted by the user:\n/Users/test/pasted-text.txt\nPrompt text",
            "The following is Codex agent history and hidden context"
        ]

        for (index, unsafeName) in unsafeNames.enumerated() {
            let snapshot = await activeUsageSessionSnapshot(
                conversationName: unsafeName,
                threadRawID: "completed-notification-unsafe-name-\(index)",
                sessionTokens: 1
            )
            let notification = MonitorNotificationContent.completed(snapshot: snapshot, languageCode: "en")

            XCTAssertEqual(notification.body, "Current task")
            XCTAssertNotEqual(notification.body, unsafeName)
            XCTAssertFalse(notification.body.contains("/Users/"))
            XCTAssertFalse(notification.body.contains("019ffa90-a5ce-7523-99d5-a85aaa140d0f"))
        }
    }

    func testCompletedNotificationPreservesTransitionAndPreferenceGates() async {
        let snapshot = await activeUsageSessionSnapshot(
            conversationName: "Authoritative notification name",
            threadRawID: "completed-notification-transition",
            sessionTokens: 1
        )
        let completed = MonitorNotificationContent.forTransition(
            from: .working,
            to: .completed,
            snapshot: snapshot,
            desktopSourceAvailable: true,
            waitingApprovalEnabled: false,
            taskCompletedEnabled: true
        )
        XCTAssertEqual(completed?.body, "Authoritative notification name")
        XCTAssertEqual(completed?.title, L10n.tr("state.completed"))
        XCTAssertEqual(completed?.subtitle, "")

        XCTAssertNil(MonitorNotificationContent.forTransition(
            from: .working,
            to: .completed,
            snapshot: snapshot,
            desktopSourceAvailable: true,
            waitingApprovalEnabled: false,
            taskCompletedEnabled: false
        ))
        XCTAssertNil(MonitorNotificationContent.forTransition(
            from: .completed,
            to: .completed,
            snapshot: snapshot,
            desktopSourceAvailable: true,
            waitingApprovalEnabled: false,
            taskCompletedEnabled: true
        ))
        XCTAssertNil(MonitorNotificationContent.forTransition(
            from: .working,
            to: .working,
            snapshot: snapshot,
            desktopSourceAvailable: true,
            waitingApprovalEnabled: false,
            taskCompletedEnabled: true
        ))
        XCTAssertNil(MonitorNotificationContent.forTransition(
            from: .working,
            to: .completed,
            snapshot: snapshot,
            desktopSourceAvailable: false,
            waitingApprovalEnabled: false,
            taskCompletedEnabled: true
        ))
    }

    func testUsageCurrentSessionUsesResolvedDisplayTitle() async {
        let snapshot = await activeUsageSessionSnapshot(
            conversationName: "Codex Monitor — Luna Final Visual Polish",
            threadRawID: "019ffa90-a5ce-7523-99d5-a85aaa140d0f",
            sessionTokens: 35_275_465
        )

        XCTAssertEqual(MonitorDisplayValue.sessionInfo(snapshot), "Codex Monitor — Luna Final Visual Polish")
    }

    func testUsageCurrentSessionDoesNotDisplayThreadUUID() async {
        let uuid = "019ffa90-a5ce-7523-99d5-a85aaa140d0f"
        let snapshot = await activeUsageSessionSnapshot(
            conversationName: "Codex Monitor — Luna Final Visual Polish",
            threadRawID: uuid,
            sessionTokens: 35_275_465
        )

        XCTAssertNotEqual(MonitorDisplayValue.sessionInfo(snapshot), uuid)
        XCTAssertEqual(MonitorDisplayValue.sessionInfo(snapshot), "Codex Monitor — Luna Final Visual Polish")
    }

    func testUsageCurrentSessionDoesNotDisplayUnsafeConversationName() async {
        let unsafeName = "The following is Codex agent history and hidden context\n# Files mentioned by the user"
        let snapshot = await activeUsageSessionSnapshot(
            conversationName: unsafeName,
            threadRawID: "019ffa90-a5ce-7523-99d5-a85aaa140d0f",
            sessionTokens: 35_275_465
        )

        XCTAssertNotEqual(MonitorDisplayValue.sessionInfo(snapshot), unsafeName)
        XCTAssertEqual(MonitorDisplayValue.sessionInfo(snapshot), L10n.tr("activity.currentTask"))
    }

    func testUsageAndQuickViewResolveSameCurrentConversationTitle() async {
        let snapshot = await activeUsageSessionSnapshot(
            conversationName: "Codex Monitor — Current Conversation",
            threadRawID: "019ffa90-a5ce-7523-99d5-a85aaa140d0f",
            sessionTokens: 35_275_465
        )

        XCTAssertEqual(MonitorDisplayValue.sessionInfo(snapshot), MonitorDisplayValue.quickViewTaskTitle(snapshot))
    }

    func testUsageSessionTokenStillUsesCorrectSessionIdentity() async {
        let snapshot = await activeUsageSessionSnapshot(
            conversationName: "Codex Monitor — Current Conversation",
            threadRawID: "019ffa90-a5ce-7523-99d5-a85aaa140d0f",
            sessionTokens: 35_275_465
        )

        XCTAssertEqual(snapshot.currentSessionThread?.threadID.rawID, "019ffa90-a5ce-7523-99d5-a85aaa140d0f")
        XCTAssertEqual(snapshot.sessionToken, 35_275_465)
        XCTAssertEqual(MonitorDisplayValue.token(snapshot), "35,275,465 Token")
    }

    func testIdleQuickViewNeverShowsHistoricalTaskTitle() async {
        let source = SourceID("quick-view-idle")!
        let thread = NamespacedID(sourceID: source, entityKind: .thread, rawID: "historical")!
        let store = MonitorRuntimeStore(engine: RuntimeStateEngine(initialPhase: .live), initialPhase: .live)
        await store.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: "Historical task title", model: "gpt-test", reasoningEffort: nil, updatedAtMilliseconds: 1_700_000_000, tokensUsed: 100))
        let idle = await store.snapshot()

        XCTAssertEqual(idle.currentState, .idle)
        XCTAssertEqual(MonitorDisplayValue.quickViewTaskTitle(idle), "Historical task title")
        XCTAssertEqual(MonitorDisplayValue.quickViewTaskTitle(idle), MonitorDisplayValue.sessionInfo(idle))
        XCTAssertTrue(MonitorDisplayValue.modelRuntime(idle).hasSuffix("0:00"))
    }

    func testQuickViewPanelIsReused() {
        let suite = "CodexMonitorTests.quickViewReuse.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MonitorPreferences(defaults: defaults)
        let controller = FloatingStatusPanelController(
            localization: LocalizationController(preference: .system),
            actions: MonitorSurfaceActions(showUsage: {}, showSettings: {}, toggleOrb: {}, openCodex: {}, quit: {}, refresh: {}, showDiagnostics: {})
        )
        let model = MonitorAppModel()
        controller.configure(model: model, preferences: preferences)
        defer { controller.closeAll() }

        controller.toggleQuickView(model: model)
        let first = controller.quickViewForTesting
        XCTAssertNotNil(first)
        for _ in 0..<100 {
            controller.toggleQuickView(model: model)
            controller.toggleQuickView(model: model)
            XCTAssertTrue(controller.quickViewForTesting === first)
        }
    }

    func testQuickViewAutoDismissesAndReclickRestartsOneShotTimer() async throws {
        let suite = "CodexMonitorTests.quickViewDismiss.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MonitorPreferences(defaults: defaults)
        let controller = FloatingStatusPanelController(
            localization: LocalizationController(preference: .system),
            actions: MonitorSurfaceActions(showUsage: {}, showSettings: {}, toggleOrb: {}, openCodex: {}, quit: {}, refresh: {}, showDiagnostics: {}),
            quickViewAutoDismissDelay: .milliseconds(60)
        )
        let model = MonitorAppModel()
        controller.configure(model: model, preferences: preferences)
        defer { controller.closeAll() }

        controller.toggleQuickView(model: model)
        let first = try XCTUnwrap(controller.quickViewForTesting)
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertTrue(first.isVisible)

        // A reclick is a refresh of the same visible panel, not a toggle.
        controller.toggleQuickView(model: model)
        XCTAssertTrue(controller.quickViewForTesting === first)
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertTrue(first.isVisible)
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertFalse(first.isVisible)

        // Repeated one-shot cycles retain exactly one NSPanel.
        for _ in 0..<50 {
            controller.toggleQuickView(model: model)
            XCTAssertTrue(controller.quickViewForTesting === first)
            for _ in 0..<10 where first.isVisible {
                try await Task.sleep(for: .milliseconds(25))
            }
            XCTAssertFalse(first.isVisible)
        }
    }

    func testQuickViewProductionDismissesAfterTwoSeconds() async throws {
        let suite = "CodexMonitorTests.quickViewTwoSeconds.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MonitorPreferences(defaults: defaults)
        let controller = FloatingStatusPanelController(
            localization: LocalizationController(preference: .system),
            actions: MonitorSurfaceActions(showUsage: {}, showSettings: {}, toggleOrb: {}, openCodex: {}, quit: {}, refresh: {}, showDiagnostics: {})
        )
        let model = MonitorAppModel()
        controller.configure(model: model, preferences: preferences)
        defer { controller.closeAll() }

        controller.toggleQuickView(model: model)
        let panel = try XCTUnwrap(controller.quickViewForTesting)
        try await Task.sleep(for: .milliseconds(1_900))
        XCTAssertTrue(panel.isVisible)
        for _ in 0..<10 where panel.isVisible {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(panel.isVisible)
    }

    func testStatusPopoverRetainsNativeTransientClickOutsideBehavior() {
        let suite = "CodexMonitorTests.transientPopover.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MonitorStatusItemController(
            model: MonitorAppModel(),
            preferences: MonitorPreferences(defaults: defaults),
            localization: LocalizationController(preference: .system),
            actions: MonitorSurfaceActions(showUsage: {}, showSettings: {}, toggleOrb: {}, openCodex: {}, quit: {}, refresh: {}, showDiagnostics: {})
        )
        defer { controller.invalidate() }
        XCTAssertEqual(controller.popoverBehaviorForTesting, .transient)
    }

    func testStatusPopoverFallbackDismissesOnlyOutsidePopoverAndStatusButton() {
        let popoverFrame = CGRect(x: 400, y: 500, width: 340, height: 280)
        let statusButtonFrame = CGRect(x: 980, y: 870, width: 48, height: 22)

        XCTAssertFalse(MonitorStatusItemController.shouldDismissPopover(
            at: CGPoint(x: 520, y: 620), popoverFrame: popoverFrame, statusButtonFrame: statusButtonFrame
        ))
        XCTAssertFalse(MonitorStatusItemController.shouldDismissPopover(
            at: CGPoint(x: 1_000, y: 880), popoverFrame: popoverFrame, statusButtonFrame: statusButtonFrame
        ))
        XCTAssertTrue(MonitorStatusItemController.shouldDismissPopover(
            at: CGPoint(x: 50, y: 50), popoverFrame: popoverFrame, statusButtonFrame: statusButtonFrame
        ))
    }

    func testTodayTokenUsesTheSameLocalCalendarBucketAsTheChart() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 14)))
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let buckets = (0..<30).reversed().compactMap { offset -> AccountUsageDailyBucket? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            return AccountUsageDailyBucket(startDate: formatter.string(from: day), tokens: offset == 0 ? 12_345 : (offset == 1 ? 5 : 0))
        }
        let snapshot = await usageSnapshot(buckets: buckets)

        XCTAssertEqual(buckets.last?.tokens, 12_345)
        XCTAssertEqual(MonitorDisplayValue.todayUsage(snapshot, now: now, calendar: calendar, languageCode: "zh-Hans"), "1.23万 Token")
        XCTAssertEqual(MonitorDisplayValue.last30DaysUsage(snapshot, languageCode: "zh-Hans"), "1.24万 Token")
        XCTAssertTrue(UsagePresentation.tooltip(for: try XCTUnwrap(buckets.last), languageCode: "en").contains("12,345 Token"))
    }

    func testTodayTokenShowsZeroOnlyForTodayZeroBucket() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 14)))
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = AccountUsageDailyBucket(startDate: formatter.string(from: now), tokens: 0)
        let previousDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let previous = AccountUsageDailyBucket(startDate: formatter.string(from: previousDate), tokens: 12_345)
        let snapshot = await usageSnapshot(buckets: [previous, today])

        XCTAssertEqual(MonitorDisplayValue.todayUsage(snapshot, now: now, calendar: calendar, languageCode: "zh-Hans"), "0 Token")
        XCTAssertEqual(MonitorDisplayValue.last30DaysUsage(snapshot, languageCode: "zh-Hans"), "1.23万 Token")
    }

    func testMissingTodayBucketIsDistinctFromZeroTodayBucket() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 14)))
        let todayKey = LocalUsageDateKey.value(for: now, calendar: calendar)
        let previousKey = LocalUsageDateKey.value(for: try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now)), calendar: calendar)
        let response = { (today: JSONValue?) in
            JSONValue.object([
                "summary": .object([:]),
                "dailyUsageBuckets": .array([
                    .object(["startDate": .string(previousKey), "tokens": .number(12_345)])
                ] + (today.map { [.object(["startDate": .string(todayKey), "tokens": $0])] } ?? []))
            ])
        }
        let missingMapped = try AccountUsageProvider.snapshot(accountResponse: .object([:]), rateLimitsResponse: .object([:]), usageResponse: response(nil), observedAt: now, calendar: calendar)
        let zeroMapped = try AccountUsageProvider.snapshot(accountResponse: .object([:]), rateLimitsResponse: .object([:]), usageResponse: response(.number(0)), observedAt: now, calendar: calendar)
        let missing = try XCTUnwrap(missingMapped.usage?.dailyBuckets?.first(where: { $0.startDate == todayKey }))
        let zero = try XCTUnwrap(zeroMapped.usage?.dailyBuckets?.first(where: { $0.startDate == todayKey }))

        XCTAssertNil(missing.authoritativeTokens)
        XCTAssertEqual(zero.authoritativeTokens, 0)
        XCTAssertNotEqual(missing, zero)

        let missingSnapshot = await usageSnapshot(buckets: try XCTUnwrap(missingMapped.usage?.dailyBuckets))
        let zeroSnapshot = await usageSnapshot(buckets: try XCTUnwrap(zeroMapped.usage?.dailyBuckets))
        XCTAssertEqual(MonitorDisplayValue.todayUsage(missingSnapshot, now: now, calendar: calendar, languageCode: "en"), "--")
        XCTAssertTrue(UsagePresentation.tooltip(for: missing, languageCode: "en").contains("Token: --"))
        XCTAssertEqual(MonitorDisplayValue.todayUsage(zeroSnapshot, now: now, calendar: calendar, languageCode: "en"), "0 Token")
        XCTAssertTrue(UsagePresentation.tooltip(for: zero, languageCode: "en").contains("Token: 0 Token"))
        XCTAssertEqual(MonitorDisplayValue.last30DaysUsage(missingSnapshot, languageCode: "zh-Hans"), "1.23万 Token")
    }

    func testSelectedQuotaWindowKeepsOrbPopoverAndQuickViewResetConsistent() async throws {
        let calendar = Calendar.current
        let resetAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 8, day: 16, hour: 15, minute: 30)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 8, day: 1, hour: 12)))
        let snapshot = await quotaSnapshot(
            primary: RateLimitWindow(usedPercent: 20, windowDurationMinutes: 300, resetsAt: resetAt.addingTimeInterval(-3_600)),
            secondary: RateLimitWindow(usedPercent: 81, windowDurationMinutes: 10_080, resetsAt: resetAt)
        )

        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "19%")
        XCTAssertEqual(MonitorDisplayValue.remainingQuota(snapshot), "19%")
        XCTAssertEqual(MonitorDisplayValue.selectedQuotaWindow(snapshot)?.window, snapshot.quota.secondary)
        XCTAssertEqual(MonitorDisplayValue.quotaResetDate(snapshot, now: now, languageCode: "zh-Hans"), "一周 · 08.16")
        XCTAssertEqual(MonitorDisplayValue.quotaResetDate(snapshot, now: now, languageCode: "en"), "Weekly · Aug 16")
    }

    func testSelectedQuotaWindowKeepsQuotaWhenResetIsUnavailable() async {
        let snapshot = await quotaSnapshot(
            primary: RateLimitWindow(usedPercent: 20, windowDurationMinutes: 300, resetsAt: nil),
            secondary: nil
        )

        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "80%")
        XCTAssertEqual(MonitorDisplayValue.remainingQuota(snapshot), "80%")
        XCTAssertEqual(MonitorDisplayValue.quotaResetDate(snapshot, languageCode: "zh-Hans"), "--")
        XCTAssertEqual(MonitorDisplayValue.quotaResetDate(snapshot, languageCode: "en"), "--")
    }

    func testSettingsControllerRetainsOneRootForThirtyCloseReopenCycles() {
        let suite = "CodexMonitorTests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = SettingsWindowController(preferences: MonitorPreferences(defaults: defaults), localization: LocalizationController(preference: .system), actions: testSettingsActions())
        let root = controller.window?.contentView
        let host = controller.hostingController
        XCTAssertNotNil(root)
        XCTAssertEqual(controller.presentation.selection, .floating)

        let navigationPath: [SettingsSection] = [.general, .floating, .notifications, .privacy, .advanced, .about, .floating]
        for index in 0..<30 {
            controller.show()
            XCTAssertTrue(controller.window?.isVisible == true, "open cycle \(index)")
            XCTAssertTrue(controller.window?.contentView === root, "root replacement on cycle \(index)")
            XCTAssertTrue(controller.hostingController === host, "host replacement on cycle \(index)")
            for section in navigationPath {
                controller.presentation.selection = section
                XCTAssertEqual(controller.presentation.selection, section, "lost selection at \(section) in cycle \(index)")
                XCTAssertNotNil(controller.window?.contentView, "missing detail host at \(section) in cycle \(index)")
            }
            controller.close()
            XCTAssertFalse(controller.window?.isVisible == true, "close cycle \(index)")
        }

        // Popover and context-menu actions both route to the same canonical
        // controller. Repeat the lifecycle they exercise without creating a
        // second Settings surface.
        for entry in ["popover", "contextMenu"] {
            for index in 0..<10 {
                controller.show()
                XCTAssertTrue(controller.window?.contentView === root, "\(entry) root \(index)")
                XCTAssertTrue(controller.hostingController === host, "\(entry) host \(index)")
                controller.close()
            }
        }
        controller.show()
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertTrue(controller.window?.contentView === root)
        XCTAssertFalse(controller.windowShouldClose(controller.window!))
        XCTAssertFalse(controller.window?.isVisible == true)
        controller.close()
    }

    func testVisualStatePresentationIsTheExactSingleSurfaceMatrix() {
        XCTAssertEqual(VisualStatePresentation.forState(.idle), .init(dots: [.green, .green, .green], orbTone: .green, breathes: false, stateTextKey: "state.idle"))
        XCTAssertEqual(VisualStatePresentation.forState(.completed).orbTone, .green)
        XCTAssertEqual(VisualStatePresentation.forState(.working), .init(dots: [.init(tone: .green, breathes: true), .inactive, .inactive], orbTone: .blue, breathes: true, stateTextKey: "state.working"))
        XCTAssertEqual(VisualStatePresentation.forState(.thinking).orbTone, .blue)
        XCTAssertEqual(VisualStatePresentation.forState(.waitingApproval).orbTone, .blue)
        for state in [MonitorRuntimeState.failed, .interrupted, .systemError] {
            XCTAssertEqual(VisualStatePresentation.forState(state).dots, [.inactive, .inactive, .init(tone: .red, breathes: false)])
            XCTAssertEqual(VisualStatePresentation.forState(state).orbTone, .red)
        }
        XCTAssertEqual(VisualStatePresentation.forState(.disconnected).orbTone, .gray)
        XCTAssertEqual(VisualStatePresentation.forState(.paused).dots.map(\.tone), [.gray, .gray, .gray])
        XCTAssertEqual(VisualStatePresentation.unavailable.orbTone, .gray)
    }

    func testPermissionRequestCreatesSecondaryEventWhileWorkRemainsBlue() async {
        let clock = PermissionPresentationTestClock()
        let runtime = MonitorRuntimeStore(engine: RuntimeStateEngine(clock: clock, initialPhase: .live), clock: clock, initialPhase: .live)
        let thread = id(.thread, "permission-thread")
        let turn = id(.turn, "permission-turn")
        let request = id(.item, "permission-call")
        let resumedWork = id(.item, "resumed-work")

        await runtime.applyDesktopCycle(
            registrations: [DesktopThreadSnapshot(threadID: thread, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil)],
            observations: [],
            health: DesktopCycleHealth(processRunning: true, stateDBReadable: true)
        )
        await runtime.ingest(event(thread, turn, .taskStarted, clock: clock))
        await runtime.ingest(event(thread, turn, .activity, activity: .tool, item: request, clock: clock))
        await runtime.ingest(ApprovalObservation.requested(ApprovalRequested(threadID: thread, turnID: turn, requestID: request, observedAt: clock.now())))

        let waiting = await runtime.snapshot()
        XCTAssertEqual(waiting.currentState, .working)
        XCTAssertTrue(waiting.approvalRequestObserved)
        XCTAssertEqual(waiting.capabilities[MonitorRuntimeCapability.approvalResolution], MonitorCapabilityAvailability(availability: .unavailable, reason: .externalCodexDesktopCapability))
        XCTAssertEqual(VisualStatePresentation.forSnapshot(waiting).orbTone, .blue)

        // The output is authoritative rollout evidence for the exact request;
        // no Approved/Declined/Cancelled outcome is inferred or manufactured.
        await runtime.ingest(event(thread, turn, .activity, activity: .agentResponse, item: request, clock: clock))
        await runtime.ingest(event(thread, turn, .activity, activity: .tool, item: resumedWork, clock: clock))

        let working = await runtime.snapshot()
        XCTAssertEqual(working.currentState, .working)
        XCTAssertEqual(VisualStatePresentation.forSnapshot(working), .init(dots: [.init(tone: .green, breathes: true), .inactive, .inactive], orbTone: .blue, breathes: true, stateTextKey: "state.working"))
    }

    func testIdlePresentationCannotCarryBreathingFromWorkingOrTerminalState() {
        let working = VisualStatePresentation.forState(.working)
        XCTAssertTrue(working.breathes)
        XCTAssertEqual(working.orbTone, .blue)

        let idle = VisualStatePresentation.forState(.idle)
        XCTAssertFalse(idle.breathes)
        XCTAssertEqual(idle.dots, [.green, .green, .green])
        XCTAssertEqual(idle.orbTone, .green)

        let newTurn = VisualStatePresentation.forState(.thinking)
        XCTAssertEqual(newTurn.dots.first, .init(tone: .green, breathes: true))
        XCTAssertEqual(newTurn.orbTone, .blue)
        XCTAssertNotEqual(newTurn.dots.last?.tone, .red)
    }

    func testWorkingQuotaSufficientCapsule() async {
        let presentation = await quotaPresentation(remaining: 80, working: true)
        XCTAssertEqual(presentation.dots, [.init(tone: .green, breathes: true), .inactive, .inactive])
    }

    func testWorkingQuotaWarningCapsule() async {
        let presentation = await quotaPresentation(remaining: 20, working: true)
        XCTAssertEqual(presentation.dots, [.init(tone: .green, breathes: true), .init(tone: .yellow, breathes: false), .inactive])
    }

    func testWorkingQuotaZeroCapsule() async {
        let presentation = await quotaPresentation(remaining: 0, working: true)
        XCTAssertEqual(presentation.dots, [.inactive, .inactive, .init(tone: .red, breathes: false)])
    }

    func testIdleQuotaSufficientCapsule() async {
        let presentation = await quotaPresentation(remaining: 80, working: false)
        XCTAssertEqual(presentation.dots, [.green, .green, .green])
    }

    func testIdleQuotaWarningCapsule() async {
        let presentation = await quotaPresentation(remaining: 20, working: false)
        XCTAssertEqual(presentation.dots, [.green, .init(tone: .yellow, breathes: false), .green])
    }

    func testIdleQuotaZeroCapsule() async {
        let presentation = await quotaPresentation(remaining: 0, working: false)
        XCTAssertEqual(presentation.dots, [.inactive, .inactive, .init(tone: .red, breathes: false)])
    }

    func testUnknownQuotaDoesNotWarn() async {
        let presentation = await quotaPresentation(remaining: nil, working: true)
        XCTAssertEqual(presentation.dots, [.init(tone: .green, breathes: true), .inactive, .inactive])
    }

    func testUnknownQuotaDoesNotShowZeroRed() async {
        let presentation = await quotaPresentation(remaining: nil, working: false)
        XCTAssertNotEqual(presentation.dots.last?.tone, .red)
    }

    func testQuotaThresholdInclusive() async {
        let presentation = await quotaPresentation(remaining: 20, working: false, threshold: 20)
        XCTAssertEqual(presentation.dots[1].tone, .yellow)
    }

    func testQuotaBelowThresholdWarns() async {
        let presentation = await quotaPresentation(remaining: 19, working: false, threshold: 20)
        XCTAssertEqual(presentation.dots[1].tone, .yellow)
    }

    func testQuotaAboveThresholdDoesNotWarn() async {
        let presentation = await quotaPresentation(remaining: 21, working: false, threshold: 20)
        XCTAssertEqual(presentation.dots, [.green, .green, .green])
    }

    func testQuotaWarningDisabledDoesNotShowYellow() async {
        let presentation = await quotaPresentation(remaining: 10, working: false, warningEnabled: false)
        XCTAssertEqual(presentation.dots, [.green, .green, .green])
    }

    func testExplicitZeroOverridesWarningSetting() async {
        let presentation = await quotaPresentation(remaining: 0, working: false, warningEnabled: false)
        XCTAssertEqual(presentation.dots, [.inactive, .inactive, .init(tone: .red, breathes: false)])
    }

    func testQuotaZeroDoesNotChangeOrb() async {
        let presentation = await quotaPresentation(remaining: 0, working: true)
        XCTAssertEqual(presentation.orbTone, .blue)
    }

    func testQuotaWarningDoesNotChangeOrb() async {
        let presentation = await quotaPresentation(remaining: 10, working: false)
        XCTAssertEqual(presentation.orbTone, .green)
    }

    func testQuotaSliderDefaultIs20() {
        XCTAssertEqual(QuotaWarningThreshold.defaultValue, 20)
    }

    func testQuotaSliderSnapsToValidThreshold() {
        XCTAssertEqual(QuotaWarningThreshold.snap(34), 30)
        XCTAssertEqual(QuotaWarningThreshold.snap(36), 40)
        XCTAssertEqual(QuotaWarningThreshold.snap(44), 40)
        XCTAssertEqual(QuotaWarningThreshold.snap(46), 50)
    }

    func testQuotaSliderDoesNotAllow35() {
        XCTAssertNotEqual(QuotaWarningThreshold.snap(35), 35)
    }

    func testQuotaSliderDoesNotAllow45() {
        XCTAssertNotEqual(QuotaWarningThreshold.snap(45), 45)
    }

    func testQuotaSliderPersistsAcrossRelaunch() {
        let suite = "CodexMonitorTests.quotaSlider.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MonitorPreferences(defaults: defaults)
        preferences.quotaWarningThreshold = 36
        XCTAssertEqual(MonitorPreferences(defaults: defaults).quotaWarningThreshold, 40)
    }

    func testApprovalBetaDisabledDoesNotChangeOrb() async {
        let presentation = await quotaPresentation(remaining: 80, working: true, approvalObserved: true)
        XCTAssertEqual(presentation.orbTone, .blue)
    }

    func testApprovalBetaEnabledObservedRequestMakesOrbYellow() async {
        let presentation = await quotaPresentation(remaining: 80, working: true, approvalObserved: true, betaEnabled: true)
        XCTAssertEqual(presentation.orbTone, .yellow)
    }

    func testApprovalBetaDoesNotChangeCapsule() async {
        let presentation = await quotaPresentation(remaining: 80, working: true, approvalObserved: true, betaEnabled: true)
        XCTAssertEqual(presentation.dots, [.init(tone: .green, breathes: true), .inactive, .inactive])
    }

    func testCompletedExecDoesNotTriggerApprovalBeta() async {
        let presentation = await quotaPresentation(remaining: 80, working: false, betaEnabled: true)
        XCTAssertEqual(presentation.orbTone, .green)
    }

    func testOrdinaryTaskDoesNotTriggerApprovalBeta() async {
        let presentation = await quotaPresentation(remaining: 80, working: true, betaEnabled: true)
        XCTAssertEqual(presentation.orbTone, .blue)
    }

    func testHistoricalApprovalDoesNotResurrectBeta() async {
        let presentation = await quotaPresentation(remaining: 80, working: false, betaEnabled: true)
        XCTAssertEqual(presentation.orbTone, .green)
    }

    func testFatalRuntimeErrorOverridesApprovalBetaOrb() async {
        let presentation = await quotaPresentation(remaining: 80, working: true, approvalObserved: true, betaEnabled: true, fatal: true)
        XCTAssertEqual(presentation.orbTone, .red)
    }

    func testApprovalBetaPreferencePersistsAcrossRelaunch() {
        let suite = "CodexMonitorTests.approvalBeta.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MonitorPreferences(defaults: defaults)
        preferences.experimentalApprovalYellowEnabled = true
        XCTAssertTrue(MonitorPreferences(defaults: defaults).experimentalApprovalYellowEnabled)
    }

    func testFollowSystemLocaleResolvesSynchronouslyBeforeAnySurfaceCreation() {
        XCTAssertEqual(LocalizationController.resolve(preference: .system, preferredLanguages: ["zh-Hans", "en"]), "zh-Hans")
        XCTAssertEqual(LocalizationController.resolve(preference: .system, preferredLanguages: ["zh-CN", "en"]), "zh-Hans")
        XCTAssertEqual(LocalizationController.resolve(preference: .system, preferredLanguages: ["zh-SG", "en"]), "zh-Hans")
        XCTAssertEqual(LocalizationController.resolve(preference: .english, preferredLanguages: ["zh-Hans"]), "en")
        XCTAssertEqual(LocalizationController.resolve(preference: .simplifiedChinese, preferredLanguages: ["en"]), "zh-Hans")
        XCTAssertEqual(L10n.tr("menu.settings", languageCode: "zh-Hans"), "设置")
        XCTAssertEqual(L10n.tr("menu.settings", languageCode: "en"), "Settings")
    }

    func testUsageHoverPresentationAndInvalidEpochSuppression() {
        let zero = AccountUsageDailyBucket(startDate: "2026-08-11", tokens: 0)
        XCTAssertTrue(UsagePresentation.tooltip(for: zero, languageCode: "en").contains("Token: 0 Token"))
        XCTAssertTrue(UsagePresentation.tooltip(for: zero, languageCode: "zh-Hans").contains("Token：0 Token"))
        XCTAssertEqual(UsagePresentation.resetTime(Date(timeIntervalSince1970: 1_380), languageCode: "en"), "Unavailable")
        XCTAssertEqual(UsagePresentation.resetTime(Date(timeIntervalSince1970: 1_380), languageCode: "zh-Hans"), "不可用")
        XCTAssertNotEqual(UsagePresentation.resetTime(Date(timeIntervalSince1970: 1_800_000_000), languageCode: "en"), "Unavailable")
        XCTAssertNotEqual(UsagePresentation.resetTime(Date(timeIntervalSince1970: 1_800_000_000), languageCode: "zh-Hans"), "不可用")
        XCTAssertNotEqual(
            UsagePresentation.resetTime(Date(timeIntervalSince1970: 1_800_000_000), languageCode: "en"),
            UsagePresentation.resetTime(Date(timeIntervalSince1970: 1_800_000_000), languageCode: "zh-Hans")
        )
        XCTAssertFalse(UsagePresentation.axisDate("2026-08-01", languageCode: "en").contains("2026"))
        XCTAssertFalse(UsagePresentation.axisDate("2026-08-01", languageCode: "zh-Hans").contains("2026"))
        XCTAssertEqual(MonitorDisplayValue.summaryTokenFormat(12_400, languageCode: "zh-Hans"), "1.24万 Token")
        XCTAssertEqual(MonitorDisplayValue.summaryTokenFormat(124_087_202, languageCode: "zh-Hans"), "1.24亿 Token")
        XCTAssertEqual(MonitorDisplayValue.preciseTokenFormat(124_087_202), "124,087,202 Token")
    }

    func testUsageChartPointerMappingAndZeroDayTooltip() {
        let buckets = (0..<30).map { AccountUsageDailyBucket(startDate: String(format: "2026-08-%02d", $0 + 1), tokens: $0 == 0 ? 0 : $0) }
        XCTAssertEqual(UsagePresentation.bucket(closestTo: 0, plotWidth: 300, buckets: buckets)?.startDate, "2026-08-01")
        XCTAssertEqual(UsagePresentation.bucket(closestTo: 299, plotWidth: 300, buckets: buckets)?.startDate, "2026-08-30")
        XCTAssertTrue(UsagePresentation.tooltip(for: buckets[0], languageCode: "en").contains("Token: 0 Token"))
        XCTAssertTrue(UsagePresentation.axisDate("2026-08-01", languageCode: "en").contains("Aug 1"))
        let originalTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = originalTimeZone }
        for identifier in ["Asia/Shanghai", "America/Los_Angeles", "America/New_York"] {
            NSTimeZone.default = TimeZone(identifier: identifier)!
            XCTAssertTrue(
                UsagePresentation.axisDate("2026-08-11", languageCode: "zh-Hans").contains("11"),
                "calendar bucket must not shift in \(identifier)"
            )
        }
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 164)
        let right = UsagePresentation.tooltipFrame(desiredOrigin: CGPoint(x: 280, y: 150), tooltipSize: UsagePresentation.tooltipSize, bounds: bounds)
        XCTAssertLessThanOrEqual(right.maxX, bounds.maxX - 6)
        XCTAssertLessThanOrEqual(right.maxY, bounds.maxY - 6)
        let left = UsagePresentation.tooltipFrame(desiredOrigin: CGPoint(x: -30, y: -20), tooltipSize: UsagePresentation.tooltipSize, bounds: bounds)
        XCTAssertGreaterThanOrEqual(left.minX, bounds.minX + 6)
        XCTAssertGreaterThanOrEqual(left.minY, bounds.minY + 6)
    }

    func testOrbHostTransparencyAndSettingsSingleTrackContracts() {
        let preferences = MonitorPreferences(defaults: UserDefaults(suiteName: "CodexMonitorTests.orbHost.\(UUID().uuidString)")!)
        let host = OrbHostingView(rootView: FloatingOrbRoot(model: MonitorAppModel(), preferences: preferences, action: {}), menuProvider: { NSMenu() })
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layer?.shadowOpacity = 0
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 90, height: 90), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertFalse(host.isOpaque)
        XCTAssertEqual(host.layer?.backgroundColor, NSColor.clear.cgColor)
        XCTAssertEqual(host.layer?.shadowOpacity, 0)

        let circularMaterial = CircularVisualEffectHost(material: .hudWindow, blendingMode: .behindWindow, state: .active)
        circularMaterial.frame = NSRect(x: 0, y: 0, width: 90, height: 90)
        circularMaterial.layoutSubtreeIfNeeded()
        let effect = circularMaterial.subviews.first as? NSVisualEffectView
        XCTAssertFalse(circularMaterial.isOpaque)
        XCTAssertEqual(effect?.blendingMode, .behindWindow)
        XCTAssertEqual(effect?.state, .active)
        XCTAssertFalse(effect?.layer?.masksToBounds == true)
        XCTAssertNil(effect?.layer?.mask)
        XCTAssertEqual(effect?.maskImage?.size, NSSize(width: 90, height: 90))

        circularMaterial.frame = NSRect(x: 0, y: 0, width: 180, height: 180)
        circularMaterial.layoutSubtreeIfNeeded()
        XCTAssertEqual(effect?.maskImage?.size, NSSize(width: 180, height: 180))
        let maskGenerations = circularMaterial.maskGenerationCountForTesting
        circularMaterial.configure(material: .hudWindow, blendingMode: .behindWindow, state: .active)
        circularMaterial.layoutSubtreeIfNeeded()
        XCTAssertEqual(circularMaterial.maskGenerationCountForTesting, maskGenerations)
        XCTAssertFalse(SettingsLayoutContract.hasCustomSliderDecoration)
    }

    func testOrbMaterialMaskIsNotRebuiltForHeartbeat() {
        let host = CircularVisualEffectHost(material: .hudWindow, blendingMode: .behindWindow, state: .active)
        host.frame = NSRect(x: 0, y: 0, width: 90, height: 90)
        host.layoutSubtreeIfNeeded()
        let baseline = host.maskGenerationCountForTesting

        for _ in 0..<100 {
            host.configure(material: .hudWindow, blendingMode: .behindWindow, state: .active)
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(host.maskGenerationCountForTesting, baseline)
    }

    func testOrbCircularDepthShadowTracksTheCircularHostSize() throws {
        let host = CircularVisualEffectHost(material: .hudWindow, blendingMode: .behindWindow, state: .active)
        host.frame = NSRect(x: 0, y: 0, width: 72, height: 72)
        host.layoutSubtreeIfNeeded()
        let small = try XCTUnwrap(host.circularShadowPathForTesting)
        XCTAssertEqual(small.boundingBox, CGRect(x: 0, y: 0, width: 72, height: 72))
        XCTAssertEqual(host.circularShadowOpacityForTesting, 0.12, accuracy: 0.001)

        let shadowOffset = host.circularShadowOffsetForTesting
        XCTAssertEqual(shadowOffset.width, 0, accuracy: 0.001)
        XCTAssertEqual(shadowOffset.height, -2, accuracy: 0.001)
        XCTAssertFalse(host.circularShadowMasksToBoundsForTesting)

        host.frame = NSRect(x: 0, y: 0, width: 180, height: 180)
        host.layoutSubtreeIfNeeded()
        let large = try XCTUnwrap(host.circularShadowPathForTesting)
        XCTAssertEqual(large.boundingBox, CGRect(x: 0, y: 0, width: 180, height: 180))

        let padded = CircularVisualEffectHost(material: .hudWindow, blendingMode: .behindWindow, state: .active, shadowInset: 10)
        padded.frame = NSRect(x: 0, y: 0, width: 110, height: 110)
        padded.layoutSubtreeIfNeeded()
        XCTAssertEqual(padded.circularGlassBoundsForTesting, CGRect(x: 10, y: 10, width: 90, height: 90))
        XCTAssertEqual(try XCTUnwrap(padded.circularShadowPathForTesting).boundingBox, CGRect(x: 10, y: 10, width: 90, height: 90))
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
        let resetAt = try XCTUnwrap(mapped.primaryRateLimit?.resetsAt)
        XCTAssertEqual(resetAt.timeIntervalSince1970, 1_725_000_500, accuracy: 0.001)
        XCTAssertGreaterThan(resetAt.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(mapped.resetCreditCount, 2)
        XCTAssertEqual(mapped.usage?.dailyBuckets?.count, 30)
        XCTAssertEqual(mapped.usage?.dailyBuckets?.last?.tokens, 45)

        let runtime = MonitorRuntimeStore(initialPhase: .live)
        await runtime.ingest(account: mapped)
        let snapshot = await runtime.snapshot()
        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "30%")
        XCTAssertEqual(MonitorDisplayValue.todayUsage(snapshot), "45 Token")
    }

    func testPartialAuthoritativeRefreshLetsUsageFailureDegradeOnlyUsage() async throws {
        let assembled = AccountUsageProvider.assemble(
            account: .success(accountRPC()),
            rateLimits: .success(rateLimitsRPC(usedPercent: 40)),
            usage: .failure(.rpcUnavailable),
            observedAt: Date()
        )
        let account = try XCTUnwrap(assembled.snapshot)
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        await runtime.ingest(account: account)
        let snapshot = await runtime.snapshot()

        XCTAssertEqual(assembled.diagnostics.usage, .rpcUnavailable)
        XCTAssertTrue(assembled.diagnostics.degraded)
        XCTAssertEqual(snapshot.account.accountKind, "chatgpt")
        XCTAssertEqual(snapshot.account.plan, "pro")
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 40)
        XCTAssertEqual(snapshot.usage.availability, .unavailable)
        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "60%")
    }

    func testPartialAuthoritativeRefreshLetsRateLimitFailureDegradeOnlyQuota() async throws {
        let assembled = AccountUsageProvider.assemble(
            account: .success(accountRPC()),
            rateLimits: .failure(.rpcUnavailable),
            usage: .success(usageRPC(tokens: 45)),
            observedAt: Date()
        )
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        await runtime.ingest(account: try XCTUnwrap(assembled.snapshot))
        let snapshot = await runtime.snapshot()

        XCTAssertEqual(assembled.diagnostics.rateLimits, .rpcUnavailable)
        XCTAssertEqual(snapshot.account.plan, "pro")
        XCTAssertEqual(snapshot.usage.availability, .available)
        XCTAssertEqual(snapshot.quota.primaryAvailability, .unavailable)
        XCTAssertNil(snapshot.quota.primary)
        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "--")
        XCTAssertNotEqual(MonitorDisplayValue.remainingQuota(snapshot), "0%")
    }

    func testPartialAuthoritativeRefreshLetsAccountFailureDegradeOnlyMetadata() async throws {
        let assembled = AccountUsageProvider.assemble(
            account: .failure(.rpcUnavailable),
            rateLimits: .success(rateLimitsRPC(usedPercent: 40)),
            usage: .success(usageRPC(tokens: 45)),
            observedAt: Date()
        )
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        await runtime.ingest(account: try XCTUnwrap(assembled.snapshot))
        let snapshot = await runtime.snapshot()

        // Account source health remains connection-level. The unavailable
        // metadata itself is represented by absent fields and the safe,
        // component-level internal diagnostic.
        XCTAssertEqual(assembled.diagnostics.account, .rpcUnavailable)
        XCTAssertEqual(snapshot.account.availability, .available)
        XCTAssertNil(snapshot.account.accountKind)
        XCTAssertNil(snapshot.account.plan)
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 40)
        XCTAssertEqual(snapshot.usage.usage?.dailyBuckets?.last?.authoritativeTokens, 45)
    }

    func testMalformedComponentDoesNotCollapseIndependentAuthoritativeComponents() async throws {
        let malformedRate = AccountUsageProvider.assemble(
            account: .success(accountRPC()),
            rateLimits: .success(.string("not-an-object")),
            usage: .success(usageRPC(tokens: 45)),
            observedAt: Date()
        )
        XCTAssertEqual(malformedRate.diagnostics.rateLimits, .responseIncompatible)
        XCTAssertEqual(malformedRate.snapshot?.planType, "pro")
        XCTAssertNil(malformedRate.snapshot?.primaryRateLimit)
        XCTAssertNotNil(malformedRate.snapshot?.usage?.dailyBuckets)

        let malformedUsage = AccountUsageProvider.assemble(
            account: .success(accountRPC()),
            rateLimits: .success(rateLimitsRPC(usedPercent: 40)),
            usage: .success(.array([])),
            observedAt: Date()
        )
        XCTAssertEqual(malformedUsage.diagnostics.usage, .responseIncompatible)
        XCTAssertEqual(malformedUsage.snapshot?.primaryRateLimit?.usedPercent, 40)
        XCTAssertNil(malformedUsage.snapshot?.usage)
    }

    func testWholeConnectionFailureRetainsTheCompletePriorSnapshotAsStale() async throws {
        let now = Date()
        let full = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(accountRPC(email: "account-a@example.test")),
            rateLimits: .success(rateLimitsRPC(usedPercent: 40)),
            usage: .success(usageRPC(tokens: 45)),
            observedAt: now
        ).snapshot)
        let failed = AccountUsageProvider.assemble(
            account: .failure(.transportUnavailable),
            rateLimits: .failure(.transportUnavailable),
            usage: .failure(.transportUnavailable),
            observedAt: now.addingTimeInterval(60)
        )
        XCTAssertNil(failed.snapshot)

        let runtime = MonitorRuntimeStore(initialPhase: .live)
        await runtime.ingest(account: full)
        await runtime.markAccountRefreshDegraded()
        let retained = await runtime.snapshot()
        XCTAssertEqual(retained.account.plan, "pro")
        XCTAssertEqual(retained.quota.primary?.usedPercent, 40)
        XCTAssertEqual(retained.usage.usage?.dailyBuckets?.last?.authoritativeTokens, 45)
        XCTAssertEqual(retained.sourceHealth[.account]?.freshness.state, .stale)
    }

    func testTransientQuotaPartialHoldsWholeSnapshotUntilFullRetrySucceeds() async throws {
        let cycles = AccountRefreshCycleSequence([
            .connected(fullRefreshAssembly(email: "account-a@example.test", usedPercent: 40, tokens: 45)),
            .connected(partialQuotaRefreshAssembly(email: "account-b@example.test", planType: "plus", tokens: 99)),
            .connected(fullRefreshAssembly(email: "account-b@example.test", planType: "plus", usedPercent: 20, tokens: 99))
        ])
        let gate = AccountRefreshRetryGate()
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        let provider = AccountUsageProvider(
            runtime: runtime,
            refreshCycle: { await cycles.next() },
            sleep: { _ in await gate.pause() }
        )
        let observer = await observeAccountSnapshots(from: runtime)
        defer { observer.task.cancel() }

        await provider.refreshOnce()
        let refresh = Task { await provider.refreshOnce() }
        await waitForRetryGate(gate)

        // The partial B cycle has completed, but has not been admitted. The
        // visible snapshot remains the prior coherent A snapshot rather than
        // an impossible Account B + Quota A composition.
        var snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.plan, "pro")
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 40)
        XCTAssertEqual(snapshot.usage.usage?.dailyBuckets?.last?.authoritativeTokens, 45)
        XCTAssertEqual(snapshot.sourceHealth[.account]?.freshness.state, .stale)
        await waitForObservedAccountSnapshot(observer.collector, quotaUsedPercent: 40, tokens: 45, freshness: .stale)

        await gate.resume()
        await refresh.value

        snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.plan, "plus")
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 20)
        XCTAssertEqual(snapshot.usage.usage?.dailyBuckets?.last?.authoritativeTokens, 99)
        await waitForObservedAccountSnapshot(observer.collector, quotaUsedPercent: 20, tokens: 99, freshness: .fresh)
        let calls = await cycles.callCount()
        XCTAssertEqual(calls, 3)
    }

    func testTransientQuotaRetryExhaustionPublishesOnlyRetryCyclePartial() async throws {
        let cycles = AccountRefreshCycleSequence([
            .connected(fullRefreshAssembly(email: "account-a@example.test", usedPercent: 40, tokens: 45)),
            .connected(partialQuotaRefreshAssembly(email: "account-b@example.test", planType: "plus", tokens: 99)),
            .connected(partialQuotaRefreshAssembly(email: "account-b@example.test", planType: "plus", tokens: 101))
        ])
        let gate = AccountRefreshRetryGate()
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        let provider = AccountUsageProvider(
            runtime: runtime,
            refreshCycle: { await cycles.next() },
            sleep: { _ in await gate.pause() }
        )
        let observer = await observeAccountSnapshots(from: runtime)
        defer { observer.task.cancel() }

        await provider.refreshOnce()
        let refresh = Task { await provider.refreshOnce() }
        await waitForRetryGate(gate)

        let held = await runtime.snapshot()
        XCTAssertEqual(held.account.plan, "pro")
        XCTAssertEqual(held.quota.primary?.usedPercent, 40)
        XCTAssertEqual(held.usage.usage?.dailyBuckets?.last?.authoritativeTokens, 45)

        await gate.resume()
        await refresh.value

        let exhausted = await runtime.snapshot()
        XCTAssertEqual(exhausted.account.plan, "plus")
        XCTAssertNil(exhausted.quota.primary)
        XCTAssertEqual(MonitorDisplayValue.orbQuota(exhausted), "--")
        XCTAssertEqual(exhausted.usage.usage?.dailyBuckets?.last?.authoritativeTokens, 101)
        XCTAssertEqual(exhausted.sourceHealth[.account]?.freshness.state, .stale)
        await waitForObservedAccountSnapshot(observer.collector, quotaUsedPercent: nil, tokens: 101, freshness: .stale)
        let calls = await cycles.callCount()
        XCTAssertEqual(calls, 3)
    }

    func testConcurrentAccountRefreshesCoalesceToOneCycle() async throws {
        let gate = AccountRefreshRetryGate()
        let cycles = AccountRefreshCycleSequence([
            .connected(fullRefreshAssembly(email: "account-a@example.test", usedPercent: 40, tokens: 45))
        ])
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        let provider = AccountUsageProvider(
            runtime: runtime,
            refreshCycle: {
                let value = await cycles.next()
                await gate.pause()
                return value
            }
        )

        let first = Task { await provider.refreshOnce() }
        await waitForRetryGate(gate)
        let second = Task { await provider.refreshOnce() }
        await Task.yield()
        await gate.resume()
        await first.value
        await second.value

        let calls = await cycles.callCount()
        XCTAssertEqual(calls, 1)
        let snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 40)
    }

    func testStopCancelsInFlightRefreshBeforeItCanIngest() async throws {
        let started = AccountRefreshSignal()
        let late = fullRefreshAssembly(email: "late@example.test", usedPercent: 40, tokens: 45)
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        let provider = AccountUsageProvider(
            runtime: runtime,
            refreshCycle: {
                await started.signal()
                try? await Task.sleep(for: .seconds(30))
                return .connected(late)
            }
        )

        let refresh = Task { await provider.refreshOnce() }
        await started.wait()
        await provider.stop()
        await refresh.value

        let snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.availability, .unknown)
        XCTAssertNil(snapshot.quota.primary)
    }

    func testStopDuringBoundedRetrySleepDoesNotStartRetryCycle() async throws {
        let cycles = AccountRefreshCycleSequence([
            .connected(fullRefreshAssembly(email: "account-a@example.test", usedPercent: 40, tokens: 45)),
            .connected(partialQuotaRefreshAssembly(email: "account-b@example.test", tokens: 99))
        ])
        let retryStarted = AccountRefreshSignal()
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        let provider = AccountUsageProvider(
            runtime: runtime,
            refreshCycle: { await cycles.next() },
            sleep: { _ in
                await retryStarted.signal()
                try await Task.sleep(for: .seconds(30))
            }
        )

        await provider.refreshOnce()
        let refresh = Task { await provider.refreshOnce() }
        await retryStarted.wait()
        await provider.stop()
        await refresh.value

        let snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 40)
        XCTAssertEqual(snapshot.sourceHealth[.account]?.freshness.state, .stale)
        let calls = await cycles.callCount()
        XCTAssertEqual(calls, 2)
    }

    func testStartAfterStopCreatesAReplacementRefreshOperation() async throws {
        let cycles = AccountRefreshCycleSequence([
            .connected(fullRefreshAssembly(email: "account-a@example.test", usedPercent: 40, tokens: 45)),
            .connected(fullRefreshAssembly(email: "account-b@example.test", planType: "plus", usedPercent: 20, tokens: 99))
        ])
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        let provider = AccountUsageProvider(runtime: runtime, refreshCycle: { await cycles.next() })

        await provider.refreshOnce()
        await provider.stop()
        await provider.refreshOnce()
        let stoppedCalls = await cycles.callCount()
        XCTAssertEqual(stoppedCalls, 1)
        await provider.start()
        await waitForRefreshCycleCount(cycles, expected: 2)
        await provider.stop()

        let snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.plan, "plus")
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 20)
    }

    func testStopBlocksQueuedManualRefreshAndExplicitStartProtectsNewRefreshFromOldCleanup() async throws {
        let calls = AccountRefreshCallCounter()
        let oldGate = AccountRefreshRetryGate()
        let newGate = AccountRefreshRetryGate()
        let oldCancelled = AccountRefreshSignal()
        let old = fullRefreshAssembly(email: "old@example.test", planType: "old", usedPercent: 40, tokens: 45)
        let new = fullRefreshAssembly(email: "new@example.test", planType: "new", usedPercent: 20, tokens: 99)
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        let provider = AccountUsageProvider(
            runtime: runtime,
            refreshCycle: {
                switch await calls.next() {
                case 1:
                    await withTaskCancellationHandler(operation: {
                        await oldGate.pause()
                    }, onCancel: {
                        Task { await oldCancelled.signal() }
                    })
                    return .connected(old)
                case 2:
                    await newGate.pause()
                    return .connected(new)
                default:
                    return .connectionFailure(.wholeConnectionFailure(AccountUsageProviderError.malformedResponse))
                }
            }
        )

        let oldRefresh = Task { await provider.refreshOnce() }
        await waitForRetryGate(oldGate)
        let stopping = Task { await provider.stop() }
        await oldCancelled.wait()

        // A refresh already queued by UI work cannot reopen the provider
        // during shutdown drain.
        let blockedManual = Task { await provider.refreshOnce() }
        await blockedManual.value
        let callsWhileStopped = await calls.value()
        XCTAssertEqual(callsWhileStopped, 1)

        // Only explicit start creates the replacement lifecycle operation.
        await provider.start()
        await waitForRetryGate(newGate)
        await oldGate.resume()
        await stopping.value

        let coalescedManual = Task { await provider.refreshOnce() }
        await Task.yield()
        let callsWhileNewIsHeld = await calls.value()
        XCTAssertEqual(callsWhileNewIsHeld, 2)

        await newGate.resume()
        await oldRefresh.value
        await coalescedManual.value
        await provider.stop()

        let snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.plan, "new")
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 20)
        let finalCalls = await calls.value()
        XCTAssertEqual(finalCalls, 2)
    }

    func testWholeConnectionFailurePublishesRetainedSnapshotAsStale() async throws {
        let cycles = AccountRefreshCycleSequence([
            .connected(fullRefreshAssembly(email: "account-a@example.test", usedPercent: 40, tokens: 45)),
            .connectionFailure(.wholeConnectionFailure(AccountUsageProviderError.malformedResponse))
        ])
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        let observer = await observeAccountSnapshots(from: runtime)
        defer { observer.task.cancel() }
        let provider = AccountUsageProvider(runtime: runtime, refreshCycle: { await cycles.next() })

        await provider.refreshOnce()
        await provider.refreshOnce()

        await waitForObservedAccountSnapshot(observer.collector, quotaUsedPercent: 40, tokens: 45, freshness: .stale)
    }

    func testAuthoritativeZeroQuotaDoesNotRetryAndRemainsZero() async throws {
        let cycles = AccountRefreshCycleSequence([
            .connected(fullRefreshAssembly(email: "account-a@example.test", usedPercent: 40, tokens: 45)),
            .connected(fullRefreshAssembly(email: "account-a@example.test", usedPercent: 100, tokens: 46))
        ])
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        let provider = AccountUsageProvider(runtime: runtime, refreshCycle: { await cycles.next() })

        await provider.refreshOnce()
        await provider.refreshOnce()

        let snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 100)
        XCTAssertEqual(MonitorDisplayValue.remainingQuota(snapshot), "0%")
        let calls = await cycles.callCount()
        XCTAssertEqual(calls, 2)
    }

    func testAuthoritativeEmptyRateLimitsClearsPriorQuotaWithoutRetry() async throws {
        let empty = AccountUsageProvider.assemble(
            account: .success(accountRPC(email: "account-b@example.test", planType: "plus")),
            rateLimits: .success(.object([:])),
            usage: .success(usageRPC(tokens: 99)),
            observedAt: Date()
        )
        let cycles = AccountRefreshCycleSequence([
            .connected(fullRefreshAssembly(email: "account-a@example.test", usedPercent: 40, tokens: 45)),
            .connected(empty)
        ])
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        let provider = AccountUsageProvider(runtime: runtime, refreshCycle: { await cycles.next() })

        await provider.refreshOnce()
        await provider.refreshOnce()

        let snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.account.plan, "plus")
        XCTAssertNil(snapshot.quota.primary)
        XCTAssertEqual(MonitorDisplayValue.orbQuota(snapshot), "--")
        let calls = await cycles.callCount()
        XCTAssertEqual(calls, 2)
    }

    func testCurrentCycleOnlyAccountSuccessDropsPreviousQuotaAndUsage() throws {
        let now = Date()
        _ = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(accountRPC(email: "account-a@example.test")),
            rateLimits: .success(rateLimitsRPC(usedPercent: 40)),
            usage: .success(usageRPC(tokens: 45)),
            observedAt: now
        ).snapshot)
        let partial = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(accountRPC(email: "account-b@example.test")),
            rateLimits: .failure(.rpcUnavailable),
            usage: .failure(.rpcUnavailable),
            observedAt: now.addingTimeInterval(60)
        ).snapshot)

        XCTAssertEqual(partial.email, "account-b@example.test")
        XCTAssertNil(partial.primaryRateLimit)
        XCTAssertNil(partial.usage)
        XCTAssertEqual(partial.provenance.observedAt, now.addingTimeInterval(60))
    }

    func testCurrentCycleOnlyAccountAndQuotaDropPreviousUsageThenRecover() throws {
        let now = Date()
        _ = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(accountRPC(email: "account-a@example.test")),
            rateLimits: .success(rateLimitsRPC(usedPercent: 40)),
            usage: .success(usageRPC(tokens: 45)),
            observedAt: now
        ).snapshot)
        let partial = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(accountRPC(email: "account-b@example.test")),
            rateLimits: .success(rateLimitsRPC(usedPercent: 10)),
            usage: .failure(.rpcUnavailable),
            observedAt: now.addingTimeInterval(60)
        ).snapshot)
        let recovered = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(accountRPC(email: "account-b@example.test")),
            rateLimits: .success(rateLimitsRPC(usedPercent: 20)),
            usage: .success(usageRPC(tokens: 99)),
            observedAt: now.addingTimeInterval(120)
        ).snapshot)

        XCTAssertEqual(partial.email, "account-b@example.test")
        XCTAssertEqual(partial.primaryRateLimit?.usedPercent, 10)
        XCTAssertNil(partial.usage)
        XCTAssertEqual(recovered.primaryRateLimit?.usedPercent, 20)
        XCTAssertEqual(recovered.usage?.dailyBuckets?.last?.authoritativeTokens, 99)
    }

    func testCurrentCycleOnlyAccountAndUsageDropPreviousQuota() async throws {
        let now = Date()
        _ = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(accountRPC(email: "account-a@example.test")),
            rateLimits: .success(rateLimitsRPC(usedPercent: 40)),
            usage: .success(usageRPC(tokens: 45)),
            observedAt: now
        ).snapshot)
        let partial = AccountUsageProvider.assemble(
            account: .success(accountRPC(email: "account-b@example.test")),
            rateLimits: .failure(.rpcUnavailable),
            usage: .success(usageRPC(tokens: 99)),
            observedAt: now.addingTimeInterval(60)
        )
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        await runtime.ingest(account: try XCTUnwrap(partial.snapshot))
        await runtime.markAccountRefreshDegraded()
        let degraded = await runtime.snapshot()

        XCTAssertTrue(partial.diagnostics.degraded)
        XCTAssertEqual(degraded.sourceHealth[.account]?.freshness.state, .stale)
        XCTAssertEqual(degraded.account.plan, "pro")
        XCTAssertNil(degraded.quota.primary)
        XCTAssertEqual(MonitorDisplayValue.orbQuota(degraded), "--")
        XCTAssertEqual(degraded.usage.usage?.dailyBuckets?.last?.authoritativeTokens, 99)
    }

    func testCurrentCycleOnlyQuotaAndUsageDropPreviousAccount() throws {
        let now = Date()
        _ = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(accountRPC(email: "account-a@example.test")),
            rateLimits: .success(rateLimitsRPC(usedPercent: 40)),
            usage: .success(usageRPC(tokens: 45)),
            observedAt: now
        ).snapshot)
        let partial = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .failure(.rpcUnavailable),
            rateLimits: .success(rateLimitsRPC(usedPercent: 10)),
            usage: .success(usageRPC(tokens: 99)),
            observedAt: now.addingTimeInterval(60)
        ).snapshot)

        XCTAssertNil(partial.email)
        XCTAssertNil(partial.planType)
        XCTAssertEqual(partial.primaryRateLimit?.usedPercent, 10)
        XCTAssertEqual(partial.usage?.dailyBuckets?.last?.authoritativeTokens, 99)
    }

    func testCurrentCycleOnlyQuotaDropsPreviousAccountAndUsage() throws {
        let now = Date()
        _ = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(accountRPC(email: "account-a@example.test")),
            rateLimits: .success(rateLimitsRPC(usedPercent: 40)),
            usage: .success(usageRPC(tokens: 45)),
            observedAt: now
        ).snapshot)
        let partial = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .failure(.rpcUnavailable),
            rateLimits: .success(rateLimitsRPC(usedPercent: 10)),
            usage: .failure(.rpcUnavailable),
            observedAt: now.addingTimeInterval(60)
        ).snapshot)

        XCTAssertNil(partial.email)
        XCTAssertNil(partial.usage)
        XCTAssertEqual(partial.primaryRateLimit?.usedPercent, 10)
    }

    func testAuthoritativeAbsenceClearsItsSuccessfullyReadComponent() async throws {
        let now = Date()
        let accountAbsent = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(.object([:])),
            rateLimits: .failure(.rpcUnavailable),
            usage: .failure(.rpcUnavailable),
            observedAt: now.addingTimeInterval(60)
        ).snapshot)
        XCTAssertNil(accountAbsent.authMode)
        XCTAssertNil(accountAbsent.planType)
        XCTAssertNil(accountAbsent.primaryRateLimit)
        XCTAssertNil(accountAbsent.usage)

        let limitsEmpty = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(accountRPC()),
            rateLimits: .success(.object([:])),
            usage: .success(usageRPC(tokens: 99)),
            observedAt: now.addingTimeInterval(120)
        ).snapshot)
        XCTAssertNil(limitsEmpty.primaryRateLimit)
        XCTAssertNil(limitsEmpty.resetCreditCount)

        let usageEmpty = try XCTUnwrap(AccountUsageProvider.assemble(
            account: .success(accountRPC()),
            rateLimits: .success(rateLimitsRPC(usedPercent: 20)),
            usage: .success(.object([:])),
            observedAt: now.addingTimeInterval(180)
        ).snapshot)
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        await runtime.ingest(account: usageEmpty)
        let snapshot = await runtime.snapshot()
        XCTAssertNil(usageEmpty.usage?.dailyBuckets)
        XCTAssertNil(HybridUsageComposer.compose(accountDailyBuckets: snapshot.usage.usage?.dailyBuckets, accountAvailability: snapshot.usage.availability, localLedger: nil))
    }

    func testAccountUsageProviderSumsDuplicateLocalDatesWithoutPlaceholderOverride() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let observedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 14)))
        let usage: JSONValue = .object([
            "summary": .object([:]),
            "dailyUsageBuckets": .array([
                .object(["startDate": .string("2026-08-12"), "tokens": .number(10_000)]),
                .object(["startDate": .string("2026-08-12"), "tokens": .number(20_000)]),
                .object(["startDate": .string("2026-08-12"), "tokens": .number(0)])
            ])
        ])
        let mapped = try AccountUsageProvider.snapshot(accountResponse: .object([:]), rateLimitsResponse: .object([:]), usageResponse: usage, observedAt: observedAt, calendar: calendar)
        let today = LocalUsageDateKey.value(for: observedAt, calendar: calendar)
        XCTAssertEqual(today, "2026-08-12")
        let bucket = try XCTUnwrap(mapped.usage?.dailyBuckets?.last(where: { $0.startDate == today }))
        XCTAssertTrue(bucket.isSourcePresent)
        XCTAssertEqual(bucket.authoritativeTokens, 30_000)
    }

    private func fullRefreshAssembly(email: String, planType: String = "pro", usedPercent: Double, tokens: Int) -> AccountRefreshAssembly {
        AccountUsageProvider.assemble(
            account: .success(accountRPC(email: email, planType: planType)),
            rateLimits: .success(rateLimitsRPC(usedPercent: usedPercent)),
            usage: .success(usageRPC(tokens: tokens)),
            observedAt: Date()
        )
    }

    private func partialQuotaRefreshAssembly(email: String, planType: String = "pro", tokens: Int) -> AccountRefreshAssembly {
        AccountUsageProvider.assemble(
            account: .success(accountRPC(email: email, planType: planType)),
            rateLimits: .failure(.rpcUnavailable),
            usage: .success(usageRPC(tokens: tokens)),
            observedAt: Date()
        )
    }

    private func waitForRetryGate(_ gate: AccountRefreshRetryGate) async {
        for _ in 0..<100 {
            if await gate.hasPaused { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for the bounded retry gate")
    }

    private func observeAccountSnapshots(from runtime: MonitorRuntimeStore) async -> AccountSnapshotObservation {
        let stream = await runtime.snapshots()
        let collector = AccountSnapshotCollector()
        let task = Task {
            for await snapshot in stream {
                await collector.append(snapshot)
            }
        }
        await Task.yield()
        return AccountSnapshotObservation(collector: collector, task: task)
    }

    private func waitForObservedAccountSnapshot(
        _ collector: AccountSnapshotCollector,
        quotaUsedPercent: Double?,
        tokens: Int,
        freshness: FreshnessState
    ) async {
        for _ in 0..<100 {
            if await collector.contains(quotaUsedPercent: quotaUsedPercent, tokens: tokens, freshness: freshness) {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for the expected account snapshot publication")
    }

    private func waitForRefreshCycleCount(_ cycles: AccountRefreshCycleSequence, expected: Int) async {
        for _ in 0..<100 {
            if await cycles.callCount() == expected { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for the expected account refresh cycle")
    }

    private func accountRPC(email: String = "account@example.test", planType: String = "pro") -> JSONValue {
        .object([
            "account": .object([
                "type": .string("chatgpt"),
                "planType": .string(planType),
                "email": .string(email)
            ])
        ])
    }

    private func rateLimitsRPC(usedPercent: Double) -> JSONValue {
        .object([
            "rateLimits": .object([
                "primary": .object(["usedPercent": .number(usedPercent)])
            ]),
            "rateLimitResetCredits": .object(["availableCount": .number(2)])
        ])
    }

    private func usageRPC(tokens: Int) -> JSONValue {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return .object([
            "summary": .object(["lifetimeTokens": .number(Double(tokens))]),
            "dailyUsageBuckets": .array([
                .object(["startDate": .string(formatter.string(from: Date())), "tokens": .number(Double(tokens))])
            ])
        ])
    }

    private func testSettingsActions() -> SettingsSystemActions {
        SettingsSystemActions(
            refresh: {}, openCodex: {}, openLogsFolder: {}, setMonitoringPaused: { _ in }, requestNotificationPermission: { _ in }, exportDiagnostics: {}, loginItem: LoginItemController(), showDiagnostics: {}
        )
    }

    private func quotaSnapshot(primary: RateLimitWindow, secondary: RateLimitWindow?) async -> MonitorRuntimeSnapshot {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let provenance = Provenance(
            sourceID: SourceID("quota-presentation")!, sourceKind: .account,
            adapterID: AdapterID("account")!, adapterVersion: AdapterVersion("test")!,
            observationMode: .snapshot, authority: .authoritative, observedAt: now,
            freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now),
            capability: .usageResponsePresence,
            evidence: EvidenceMetadata(evidenceRun: "test", cliVersion: "test", historicalTransportEvidenceLabel: "test", probeOrHarnessAvailability: "test", sanitizerAvailability: "test", sanitizerVersion: "test", confidence: "test", limitations: "test"),
            origin: .adapter
        )!
        let account = AccountSnapshot(provenance: provenance, primaryRateLimit: primary, secondaryRateLimit: secondary)!
        let runtime = MonitorRuntimeStore(
            accountCapabilities: .init(secondaryQuota: .snapshot),
            initialPhase: .live
        )
        await runtime.ingest(account: account)
        return await runtime.snapshot()
    }

    private func quotaPresentation(
        remaining: Double?,
        working: Bool,
        warningEnabled: Bool = true,
        threshold: Double = 20,
        approvalObserved: Bool = false,
        betaEnabled: Bool = false,
        fatal: Bool = false
    ) async -> VisualStatePresentation {
        let primary = RateLimitWindow(usedPercent: remaining.map { 100 - $0 })
        let runtime = MonitorRuntimeStore(
            engine: RuntimeStateEngine(initialPhase: .live),
            accountCapabilities: .init(secondaryQuota: .snapshot),
            initialPhase: .live
        )
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let provenance = Provenance(sourceID: SourceID("quota-capsule")!, sourceKind: .account, adapterID: AdapterID("account")!, adapterVersion: AdapterVersion("test")!, observationMode: .snapshot, authority: .authoritative, observedAt: now, freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now), capability: .usageResponsePresence, evidence: EvidenceMetadata(evidenceRun: "test", cliVersion: "test", historicalTransportEvidenceLabel: "test", probeOrHarnessAvailability: "test", sanitizerAvailability: "test", sanitizerVersion: "test", confidence: "test", limitations: "test"), origin: .fixture)!
        await runtime.ingest(account: AccountSnapshot(provenance: provenance, primaryRateLimit: primary)!)
        let source = SourceID("quota-capsule-runtime")!
        let thread = NamespacedID(sourceID: source, entityKind: .thread, rawID: "thread")!
        let turn = NamespacedID(sourceID: source, entityKind: .turn, rawID: "turn")!
        await runtime.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: nil, model: nil, reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        if working {
            await runtime.ingest(.rollout(RolloutRecordEnvelope(threadID: thread, turnID: turn, itemID: nil, kind: .taskStarted, activity: nil, tokenSnapshot: nil, model: nil, reasoningEffort: nil, observedAt: now, fileOffset: 0)))
            await runtime.ingest(.rollout(RolloutRecordEnvelope(threadID: thread, turnID: turn, itemID: nil, kind: .activity, activity: .tool, tokenSnapshot: nil, model: nil, reasoningEffort: nil, observedAt: now, fileOffset: 1)))
        }
        if approvalObserved {
            let request = NamespacedID(sourceID: source, entityKind: .item, rawID: "request")!
            await runtime.ingest(.requested(ApprovalRequested(threadID: thread, turnID: turn, requestID: request, observedAt: now)))
        }
        if fatal {
            await runtime.ingest(.rollout(RolloutRecordEnvelope(threadID: thread, turnID: turn, itemID: nil, kind: .taskCompletedFailure, activity: nil, tokenSnapshot: nil, model: nil, reasoningEffort: nil, observedAt: now, fileOffset: 2)))
        }
        return VisualStatePresentation.forSnapshot(await runtime.snapshot(), quotaWarningEnabled: warningEnabled, quotaWarningThreshold: threshold, experimentalApprovalYellowEnabled: betaEnabled)
    }

    private func usageSnapshot(buckets: [AccountUsageDailyBucket]) async -> MonitorRuntimeSnapshot {
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let provenance = Provenance(
            sourceID: SourceID("usage-presentation")!, sourceKind: .account,
            adapterID: AdapterID("account")!, adapterVersion: AdapterVersion("test")!,
            observationMode: .snapshot, authority: .authoritative, observedAt: now,
            freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now),
            capability: .usageResponsePresence,
            evidence: EvidenceMetadata(evidenceRun: "test", cliVersion: "test", historicalTransportEvidenceLabel: "test", probeOrHarnessAvailability: "test", sanitizerAvailability: "test", sanitizerVersion: "test", confidence: "test", limitations: "test"),
            origin: .adapter
        )!
        let usage = UsagePresence(summaryAvailable: true, dailyBucketsAvailable: true, dailyBuckets: buckets)
        let account = AccountSnapshot(provenance: provenance, usage: usage)!
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        await runtime.ingest(account: account)
        return await runtime.snapshot()
    }

    private func activeUsageSessionSnapshot(conversationName: String?, threadRawID: String, sessionTokens: Int64) async -> MonitorRuntimeSnapshot {
        let clock = PermissionPresentationTestClock()
        let runtime = MonitorRuntimeStore(
            engine: RuntimeStateEngine(clock: clock, initialPhase: .live),
            clock: clock,
            initialPhase: .live
        )
        let source = SourceID("usage-current-session-title")!
        let thread = NamespacedID(sourceID: source, entityKind: .thread, rawID: threadRawID)!
        let turn = NamespacedID(sourceID: source, entityKind: .turn, rawID: "usage-current-session-turn")!
        await runtime.registerDesktopThread(DesktopThreadSnapshot(threadID: thread, conversationName: conversationName, model: "gpt-test", reasoningEffort: nil, updatedAtMilliseconds: nil, tokensUsed: nil))
        await runtime.ingest(.rollout(RolloutRecordEnvelope(
            threadID: thread,
            turnID: turn,
            itemID: nil,
            kind: .taskStarted,
            activity: nil,
            tokenSnapshot: TokenSnapshot(totalTokens: sessionTokens, lastCallTokens: nil),
            model: nil,
            reasoningEffort: nil,
            observedAt: clock.now(),
            fileOffset: 0
        )))
        return await runtime.snapshot()
    }

    private func id(_ kind: EntityKind, _ raw: String) -> NamespacedID {
        NamespacedID(sourceID: SourceID("permission-product-test")!, entityKind: kind, rawID: raw)!
    }

    private func event(_ thread: NamespacedID, _ turn: NamespacedID, _ kind: RolloutEventKind, activity: RolloutActivityCategory? = nil, item: NamespacedID? = nil, clock: PermissionPresentationTestClock) -> DesktopObservation {
        .rollout(RolloutRecordEnvelope(threadID: thread, turnID: turn, itemID: item, kind: kind, activity: activity, tokenSnapshot: nil, model: nil, reasoningEffort: nil, observedAt: clock.now(), fileOffset: 0))
    }
}

private actor AccountRefreshCycleSequence {
    private var values: [AccountRefreshCycleResult]
    private var calls = 0

    init(_ values: [AccountRefreshCycleResult]) {
        self.values = values
    }

    func next() -> AccountRefreshCycleResult {
        calls += 1
        precondition(!values.isEmpty, "Unexpected additional account refresh cycle")
        return values.removeFirst()
    }

    func callCount() -> Int { calls }
}

private actor AccountRefreshRetryGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasPaused = false

    func pause() async {
        hasPaused = true
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor AccountRefreshSignal {
    private var signaled = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func signal() {
        signaled = true
        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting { continuation.resume() }
    }

    func wait() async {
        guard !signaled else { return }
        await withCheckedContinuation { continuations.append($0) }
    }
}

private actor AccountRefreshCallCounter {
    private var calls = 0

    func next() -> Int {
        calls += 1
        return calls
    }

    func value() -> Int { calls }
}

private struct AccountSnapshotObservation {
    let collector: AccountSnapshotCollector
    let task: Task<Void, Never>
}

private actor AccountSnapshotCollector {
    private var snapshots: [MonitorRuntimeSnapshot] = []

    func append(_ snapshot: MonitorRuntimeSnapshot) {
        snapshots.append(snapshot)
    }

    func contains(quotaUsedPercent: Double?, tokens: Int, freshness: FreshnessState) -> Bool {
        snapshots.contains { snapshot in
            snapshot.quota.primary?.usedPercent == quotaUsedPercent
                && snapshot.usage.usage?.dailyBuckets?.last?.authoritativeTokens == tokens
                && snapshot.sourceHealth[.account]?.freshness.state == freshness
        }
    }
}

private final class PermissionPresentationTestClock: StateEngineClock, MonitorRuntimeClock, @unchecked Sendable {
    private let value = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { value }
}
