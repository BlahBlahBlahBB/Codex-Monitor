import AppKit
import SwiftUI
import CodexMonitorContracts

@main
struct CodexMonitorApp: App {
    @StateObject private var model: MonitorAppModel
    @StateObject private var preferences: MonitorPreferences
    @StateObject private var panelController = FloatingStatusPanelController()
    private let runtime: MonitorRuntimeStore
    private let driver: CodexLocalMonitorDriver

    init() {
        let runtime = MonitorRuntimeStore()
        self.runtime = runtime; driver = CodexLocalMonitorDriver(runtime: runtime)
        _model = StateObject(wrappedValue: MonitorAppModel())
        _preferences = StateObject(wrappedValue: MonitorPreferences())
    }

    var body: some Scene {
        WindowGroup("Codex Monitor") {
            MonitorMainView(model: model)
                .onAppear { start() }
                .onChange(of: preferences.showOrb) { _ in panelController.configure(model: model, preferences: preferences) }
                .onChange(of: preferences.orbSize) { _ in panelController.configure(model: model, preferences: preferences) }
        }
        Settings { MonitorSettingsView(preferences: preferences) }
        MenuBarExtra("Codex Monitor", systemImage: "circle.fill") {
            if preferences.showUsageMenu {
                Button { activateMainWindow() } label: {
                    Label("Usage", systemImage: "chart.bar")
                }
            }
            if preferences.showSettingsMenu {
                Button { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            Divider()
            Button {
                preferences.showOrb.toggle()
                panelController.configure(model: model, preferences: preferences)
            } label: {
                Label(
                    preferences.showOrb ? "Hide Floating Window" : "Show Floating Window",
                    systemImage: preferences.showOrb ? "eye.slash" : "eye"
                )
            }
            Button { openCodex() } label: {
                Label("Open Codex", systemImage: "arrow.up.right.square")
            }
            Divider()
            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
            }
        }
    }

    private func start() {
        model.startObserving(runtime)
        panelController.configure(model: model, preferences: preferences)
        Task { await driver.start() }
        startSmokeExitIfRequested()
    }

    private func activateMainWindow() { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.title == "Codex Monitor" }?.makeKeyAndOrderFront(nil) }
    private func openCodex() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func startSmokeExitIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment["CODEX_MONITOR_SMOKE_EXIT_SECONDS"], let seconds = Double(raw), seconds > 0 else { return }
        Task {
            try? await Task.sleep(for: .seconds(seconds)); let snapshot = await runtime.snapshot()
            let desktop = snapshot.sourceHealth[.desktopLocal]?.availability.rawValue ?? "unknown"
            let uiState = model.snapshot?.currentState.rawValue ?? "missing"
            print("CODEX_MONITOR_SMOKE runtime=\(snapshot.currentState.rawValue) ui=\(uiState) activity=\(snapshot.currentActivity.rawValue) threads=\(snapshot.threads.count) desktop=\(desktop) token=\(snapshot.sessionToken.map(String.init) ?? "unknown") usage=\(snapshot.usage.availability.rawValue) quota=\(snapshot.quota.primaryAvailability.rawValue) reset=\(snapshot.resetInformation.countAvailability.rawValue) uiUpdates=\(model.acceptedSnapshotCount)")
            await driver.stop(); NSApp.terminate(nil)
        }
    }
}
