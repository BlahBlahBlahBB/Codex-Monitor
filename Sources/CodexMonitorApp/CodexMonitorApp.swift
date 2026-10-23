import AppKit
import Combine
import CodexMonitorContracts

@main
@MainActor
final class CodexMonitorApplication: NSObject {
    /// AppKit owns the application lifecycle so there is no competing SwiftUI
    /// Settings scene. `CodexMonitorAppDelegate` is the sole owner of every
    /// native surface, including the canonical Settings controller.
    private static let applicationDelegate = CodexMonitorAppDelegate()
    fileprivate static var sparkleLaunchState = SparkleLocalization.LaunchState(
        driverLanguage: "en",
        nativeDriverMatchesSelection: true
    )

    static func main() {
        // Must precede NSApplication creation and every app-owned subsystem.
        QAIsolation.verifyPackaging()
        let launchPreferences = MonitorPreferences(defaults: QAIsolation.preferences)
        sparkleLaunchState = SparkleLocalization.prepareForLaunch(
            preference: launchPreferences.interfaceLanguage,
            defaults: QAIsolation.preferences,
            systemPreferredLanguages: LocalizationController.systemPreferredLanguages
        )
        let application = NSApplication.shared
        application.delegate = applicationDelegate
        application.run()
    }
}

@MainActor
final class CodexMonitorAppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = MonitorRuntimeStore(
        accountCapabilities: .init(secondaryQuota: .snapshot)
    )
    private lazy var usageLedger: LocalUsageLedgerProvider = {
        LocalUsageLedgerProvider()
    }()
    private lazy var approvalObserverPaths = AppOwnedApprovalObserverPaths.default
    private lazy var approvalJournalSource = AppManagedHookApprovalJournalSource(journalURL: approvalObserverPaths.journalURL)
    private lazy var approvalIdentityResolver = AppManagedHookApprovalIdentityResolver(identityKeyURL: approvalObserverPaths.identityKeyURL)
    private lazy var approvalIntegration: ApprovalObserverIntegration = {
        ApprovalObserverIntegration(
            paths: approvalObserverPaths,
            journalSource: approvalJournalSource,
            identityResolver: approvalIdentityResolver
        )
    }()
    private lazy var driver: CodexLocalMonitorDriver = {
        let source = approvalJournalSource
        return CodexLocalMonitorDriver(
            runtime: runtime,
            usageLedger: usageLedger,
            hookJournalSource: source,
            hookIdentityResolver: approvalIdentityResolver,
            hookApprovalSourceIsActive: { source.isActive },
            approvalNotificationDelivery: { [weak self] intent in
                guard let self else { return .retry }
                return await self.deliverApprovalNotificationOutboxIntent(intent)
            }
        )
    }()
    private lazy var accountProvider = AccountUsageProvider(runtime: runtime)
    private let model = MonitorAppModel()
    let preferences = MonitorPreferences(defaults: QAIsolation.preferences)
    private lazy var localization = LocalizationController(
        preference: preferences.interfaceLanguage,
        preferredLanguages: LocalizationController.launchPreferredLanguages
    )
    private var surfaces: MonitorSurfaceCoordinator?
    private var languageObserver: AnyCancellable?
    private let sparkleUpdates = SparkleUpdateController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        L10n.configure(localization)
        installApplicationMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UIBuildDiagnostics.logStartup()
        let surfaces = MonitorSurfaceCoordinator(
            model: model,
            preferences: preferences,
            localization: localization,
            refreshMonitoring: { [weak self] in self?.restartObservation() },
            setMonitoringPaused: { [weak self] in self?.setMonitoringPaused($0) },
            activateApprovalObserver: { [weak self] in self?.activateApprovalObserver() },
            checkForUpdates: { [weak self] in self?.checkForUpdates() },
            openManualUpdateDownload: { NSWorkspace.shared.open(GitHubUpdateNotifier.officialReleasesPage) },
            qaIsolationEnabled: QAIsolation.enabled
        )
        self.surfaces = surfaces
        model.startObserving(runtime)
        if !QAIsolation.enabled { model.startObserving(usageLedger) }
        surfaces.start()
        sparkleUpdates.start(
            language: localization.resolvedLanguage,
            nativeDriverMatchesSelection: CodexMonitorApplication.sparkleLaunchState.nativeDriverMatchesSelection
        )
        if !QAIsolation.enabled {
            Task { await driver.start() }
            Task { await accountProvider.start() }
            if preferences.pauseMonitoring { setMonitoringPaused(true) }
        }
        languageObserver = preferences.$interfaceLanguage.sink { [weak self] preference in
            guard let self else { return }
            localization.refresh(preference: preference, preferredLanguages: LocalizationController.systemPreferredLanguages)
            // Sparkle's standard driver cannot change its already-loaded
            // framework localization. Persist this app-only value now so the
            // next normal launch selects the same language as the UI.
            SparkleLocalization.persistForNextLaunch(preference: preference, defaults: QAIsolation.preferences)
            installApplicationMenu()
        }
        startSmokeExitIfRequested()
    }

    func applicationWillTerminate(_ notification: Notification) {
        preferences.flushPersistence()
        languageObserver?.cancel()
        model.stopObserving()
        surfaces?.stop()
        if !QAIsolation.enabled {
            Task { await driver.stop() }
            Task { await accountProvider.stop() }
        }
        sparkleUpdates.stop()
    }

    private func restartObservation() {
        guard !QAIsolation.enabled else { return }
        // This is a safe UI-level request to resume the existing snapshot
        // observation bridge; it does not touch local sources from UI.
        model.startObserving(runtime)
        Task { [weak self] in
            guard let self else { return }
            await driver.refreshOnce()
            await accountProvider.refreshOnce()
        }
    }

    private func checkForUpdates() {
        switch sparkleUpdates.checkForUpdates(language: localization.resolvedLanguage) {
        case .started:
            break
        case .restartRequiredForLanguage:
            let alert = NSAlert()
            alert.messageText = L10n.tr("update.languageRestartRequiredTitle")
            alert.informativeText = L10n.tr("update.languageRestartRequiredDescription")
            alert.addButton(withTitle: L10n.tr("update.ok"))
            alert.runModal()
        }
    }

    private func deliverApprovalNotificationOutboxIntent(_ intent: ApprovalNotificationOutboxIntent) async -> ApprovalNotificationDeliveryDisposition {
        guard let surfaces else { return .retry }
        return await surfaces.deliverApprovalOutboxIntent(intent)
    }

    private func setMonitoringPaused(_ paused: Bool) {
        guard !QAIsolation.enabled else { return }
        Task { [weak self] in
            guard let self else { return }
            await driver.setUserMonitoringPaused(paused)
            if !paused { await accountProvider.refreshOnce() }
        }
    }

    private func activateApprovalObserver() {
        guard !QAIsolation.enabled else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = await approvalIntegration.reconcile(enabled: true)
        }
    }

    func showDiagnostics() {
        surfaces?.showDiagnostics()
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        surfaces?.showSettings()
    }

    private func installApplicationMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Codex Monitor")

        applicationMenu.addItem(
            withTitle: L10n.tr("app.about"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())

        let settings = applicationMenu.addItem(
            withTitle: L10n.tr("menu.settings"),
            action: #selector(showSettingsWindow(_:)),
            keyEquivalent: ","
        )
        settings.target = self

        applicationMenu.addItem(.separator())
        let quit = applicationMenu.addItem(
            withTitle: L10n.tr("menu.quitMonitor"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp

        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        NSApp.mainMenu = mainMenu
    }

    private func startSmokeExitIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment["CODEX_MONITOR_SMOKE_EXIT_SECONDS"],
              let seconds = Double(raw), seconds > 0 else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            let snapshot = await runtime.snapshot()
            let desktop = snapshot.sourceHealth[.desktopLocal]?.availability.rawValue ?? "unknown"
            let uiState = model.snapshot?.currentState.rawValue ?? "missing"
            print("CODEX_MONITOR_SMOKE runtime=\(snapshot.currentState.rawValue) ui=\(uiState) activity=\(snapshot.currentActivity.rawValue) threads=\(snapshot.threads.count) desktop=\(desktop) token=\(snapshot.sessionToken.map(String.init) ?? "unknown") usage=\(snapshot.usage.availability.rawValue) quota=\(snapshot.quota.primaryAvailability.rawValue) reset=\(snapshot.resetInformation.countAvailability.rawValue) uiUpdates=\(model.acceptedSnapshotCount)")
            await driver.stop()
            NSApp.terminate(nil)
        }
    }
}
