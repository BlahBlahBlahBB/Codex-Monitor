import AppKit
import SwiftUI
import CodexMonitorContracts

@main
struct CodexMonitorApp: App {
    @NSApplicationDelegateAdaptor(CodexMonitorAppDelegate.self) private var appDelegate

    // All user-facing windows are explicitly owned by native window controllers.
    // This inert settings scene keeps SwiftUI's app lifecycle valid without
    // recreating the rejected main dashboard WindowGroup.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class CodexMonitorAppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = MonitorRuntimeStore()
    private lazy var driver = CodexLocalMonitorDriver(runtime: runtime)
    private let model = MonitorAppModel()
    private let preferences = MonitorPreferences()
    private var surfaces: MonitorSurfaceCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let surfaces = MonitorSurfaceCoordinator(
            model: model,
            preferences: preferences,
            refreshMonitoring: { [weak self] in self?.restartObservation() }
        )
        self.surfaces = surfaces
        model.startObserving(runtime)
        surfaces.start()
        Task { await driver.start() }
        startSmokeExitIfRequested()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopObserving()
        surfaces?.stop()
        Task { await driver.stop() }
    }

    private func restartObservation() {
        // This is a safe UI-level request to resume the existing snapshot
        // observation bridge; it does not touch local sources from UI.
        model.startObserving(runtime)
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
