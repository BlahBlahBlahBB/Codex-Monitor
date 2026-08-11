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
            MonitorDebugView(model: model, preferences: preferences)
                .frame(minWidth: 560, minHeight: 600)
                .onAppear { start() }
                .onChange(of: preferences.showOrb) { _ in panelController.configure(model: model, preferences: preferences) }
                .onChange(of: preferences.orbSize) { _ in panelController.configure(model: model, preferences: preferences) }
        }
        Settings { SettingsView(preferences: preferences) }
        MenuBarExtra("Codex Monitor", systemImage: "circle.fill") {
            if preferences.showUsageMenu { Button("Usage") { activateMainWindow() } }
            if preferences.showSettingsMenu { Button("Settings") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) } }
            Divider()
            Button(preferences.showOrb ? "Hide Floating Window" : "Show Floating Window") { preferences.showOrb.toggle(); panelController.configure(model: model, preferences: preferences) }
            Button("Open Codex") { openCodex() }
            Divider(); Button("Quit") { NSApp.terminate(nil) }
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

private struct MonitorDebugView: View {
    @ObservedObject var model: MonitorAppModel
    @ObservedObject var preferences: MonitorPreferences
    var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) { MonitorOrbView(snapshot: snapshot, size: 84); VStack(alignment: .leading) { Text("Codex Monitor").font(.title2.weight(.semibold)); Text(snapshot?.currentState.rawValue ?? "UNAVAILABLE").font(.headline); Text(snapshot?.currentActivity.rawValue ?? "No runtime snapshot").foregroundStyle(.secondary) }; Spacer() }
            GroupBox("Current Session / Thread") { LabeledContent("Thread", value: snapshot?.currentSessionThread?.threadID.rawID ?? "unavailable"); LabeledContent("Turn", value: snapshot?.currentSessionThread?.activeTurnID?.rawID ?? "unavailable"); LabeledContent("Session Token", value: snapshot?.sessionToken.map(String.init) ?? label(snapshot?.currentThread?.sessionTokenAvailability)) }
            GroupBox("Usage / Quota / Reset") { LabeledContent("Usage", value: snapshot?.usage.usage?.totalTokens.map(String.init) ?? label(snapshot?.usage.availability)); LabeledContent("Primary quota", value: snapshot?.quota.primary?.usedPercent.map { String(format: "%.0f%% used", $0) } ?? label(snapshot?.quota.primaryAvailability)); LabeledContent("Reset credits", value: snapshot?.resetInformation.count.map(String.init) ?? label(snapshot?.resetInformation.countAvailability)) }
            GroupBox("Source Health") { ForEach(MonitorRuntimeSource.allCases, id: \.rawValue) { source in LabeledContent(source.rawValue, value: label(snapshot?.sourceHealth[source]?.availability)) } }
            GroupBox("Capabilities") { ForEach(MonitorRuntimeCapability.allCases, id: \.rawValue) { capability in let value = snapshot?.capabilities[capability]; LabeledContent(capability.rawValue, value: label(value?.availability, reason: value?.reason)) } }
            Spacer(minLength: 0)
        }.padding(20)
    }
    private func label(_ availability: MonitorDataAvailability?, reason: MonitorUnavailabilityReason? = nil) -> String { let value = availability?.rawValue.uppercased() ?? "UNAVAILABLE"; return reason.map { "\(value) (\($0.rawValue))" } ?? value }
}

private struct SettingsView: View {
    @ObservedObject var preferences: MonitorPreferences
    var body: some View {
        Form { Toggle("Show floating window", isOn: $preferences.showOrb); HStack { Text("Floating window size"); Slider(value: $preferences.orbSize, in: 72...180, step: 1); Text("\(Int(preferences.orbSize)) pt").monospacedDigit() }; Divider(); Toggle("Show Usage in menu bar", isOn: $preferences.showUsageMenu); Toggle("Show Settings in menu bar", isOn: $preferences.showSettingsMenu) }.padding(20).frame(width: 420)
    }
}
