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

    static func main() {
        let application = NSApplication.shared
        application.delegate = applicationDelegate
        application.run()
    }
}

@MainActor
final class CodexMonitorAppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = MonitorRuntimeStore()
    private lazy var driver = CodexLocalMonitorDriver(runtime: runtime)
    private lazy var accountProvider = AccountUsageProvider(runtime: runtime)
    private let model = MonitorAppModel()
    let preferences = MonitorPreferences()
    private lazy var localization = LocalizationController(
        preference: preferences.interfaceLanguage,
        preferredLanguages: LocalizationController.launchPreferredLanguages
    )
    private var surfaces: MonitorSurfaceCoordinator?
    private var languageObserver: AnyCancellable?

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
            setMonitoringPaused: { [weak self] in self?.setMonitoringPaused($0) }
        )
        self.surfaces = surfaces
        model.startObserving(runtime)
        surfaces.start()
        Task { await driver.start() }
        Task { await accountProvider.start() }
        if preferences.pauseMonitoring { setMonitoringPaused(true) }
        languageObserver = preferences.$interfaceLanguage.sink { [weak self] preference in
            guard let self else { return }
            localization.refresh(preference: preference, preferredLanguages: LocalizationController.launchPreferredLanguages)
            installApplicationMenu()
        }
        startSmokeExitIfRequested()
    }

    func applicationWillTerminate(_ notification: Notification) {
        preferences.flushPersistence()
        languageObserver?.cancel()
        model.stopObserving()
        surfaces?.stop()
        Task { await driver.stop() }
        Task { await accountProvider.stop() }
    }

    private func restartObservation() {
        // This is a safe UI-level request to resume the existing snapshot
        // observation bridge; it does not touch local sources from UI.
        model.startObserving(runtime)
        Task { [weak self] in
            guard let self else { return }
            await driver.refreshOnce()
            await accountProvider.refreshOnce()
        }
    }

    private func setMonitoringPaused(_ paused: Bool) {
        Task { [weak self] in
            guard let self else { return }
            await driver.setUserMonitoringPaused(paused)
            if !paused { await accountProvider.refreshOnce() }
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
