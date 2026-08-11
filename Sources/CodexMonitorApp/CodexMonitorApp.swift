import AppKit
import SwiftUI
import CodexMonitorContracts

@main
struct CodexMonitorApp: App {
    @StateObject private var model: MonitorAppModel
    @StateObject private var panelController = FloatingStatusPanelController()
    private let runtime: MonitorRuntimeStore
    private let driver: CodexLocalMonitorDriver

    init() {
        let runtime = MonitorRuntimeStore()
        self.runtime = runtime
        driver = CodexLocalMonitorDriver(runtime: runtime)
        _model = StateObject(wrappedValue: MonitorAppModel())
    }

    var body: some Scene {
        WindowGroup("Codex Monitor") {
            MonitorDebugView(model: model)
                .frame(minWidth: 560, minHeight: 600)
                .onAppear {
                    model.startObserving(runtime)
                    panelController.show(model: model)
                    Task { await driver.start() }
                    startSmokeExitIfRequested()
                }
                .onDisappear {
                    model.stopObserving()
                    Task { await driver.stop() }
                }
        }
    }

    private func startSmokeExitIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment["CODEX_MONITOR_SMOKE_EXIT_SECONDS"],
              let seconds = Double(raw), seconds > 0 else { return }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            let snapshot = await runtime.snapshot()
            let desktop = snapshot.sourceHealth[.desktopLocal]?.availability.rawValue ?? "unknown"
            let uiState = model.snapshot?.currentState.rawValue ?? "missing"
            let token = snapshot.sessionToken.map(String.init) ?? snapshot.currentThread?.sessionTokenAvailability.rawValue ?? "unknown"
            let usage = snapshot.usage.availability.rawValue
            let quota = snapshot.quota.primaryAvailability.rawValue
            print("CODEX_MONITOR_SMOKE runtime=\(snapshot.currentState.rawValue) ui=\(uiState) activity=\(snapshot.currentActivity.rawValue) threads=\(snapshot.threads.count) desktop=\(desktop) token=\(token) usage=\(usage) quota=\(quota) uiUpdates=\(model.acceptedSnapshotCount)")
            await driver.stop()
            NSApp.terminate(nil)
        }
    }
}

private struct MonitorDebugView: View {
    @ObservedObject var model: MonitorAppModel

    var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                MonitorOrbView(snapshot: snapshot)
                VStack(alignment: .leading) {
                    Text("Codex Monitor").font(.title2.weight(.semibold))
                    Text(snapshot?.currentState.rawValue ?? "UNAVAILABLE").font(.headline)
                    Text(snapshot?.currentActivity.rawValue ?? "No runtime snapshot").foregroundStyle(.secondary)
                }
                Spacer()
            }
            GroupBox("Current Session / Thread") {
                LabeledContent("Thread", value: snapshot?.currentSessionThread?.threadID.rawID ?? "unavailable")
                LabeledContent("Turn", value: snapshot?.currentSessionThread?.activeTurnID?.rawID ?? "unavailable")
                LabeledContent("Session Token", value: snapshot?.sessionToken.map(String.init) ?? availabilityLabel(snapshot?.currentThread?.sessionTokenAvailability))
            }
            GroupBox("Usage / Quota / Reset") {
                LabeledContent("Usage", value: snapshot?.usage.usage?.totalTokens.map(String.init) ?? availabilityLabel(snapshot?.usage.availability))
                LabeledContent("Primary quota", value: snapshot?.quota.primary?.usedPercent.map { String(format: "%.0f%% used", $0) } ?? availabilityLabel(snapshot?.quota.primaryAvailability))
                LabeledContent("Secondary quota", value: snapshot?.quota.secondary?.usedPercent.map { String(format: "%.0f%% used", $0) } ?? availabilityLabel(snapshot?.quota.secondaryAvailability))
                LabeledContent("Reset credits", value: snapshot?.resetInformation.count.map(String.init) ?? availabilityLabel(snapshot?.resetInformation.countAvailability))
            }
            GroupBox("Source Health") {
                ForEach(MonitorRuntimeSource.allCases, id: \.rawValue) { source in
                    LabeledContent(source.rawValue, value: availabilityLabel(snapshot?.sourceHealth[source]?.availability))
                }
            }
            GroupBox("Capabilities") {
                ForEach(MonitorRuntimeCapability.allCases, id: \.rawValue) { capability in
                    let value = snapshot?.capabilities[capability]
                    LabeledContent(capability.rawValue, value: availabilityLabel(value?.availability, reason: value?.reason))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func availabilityLabel(_ availability: MonitorDataAvailability?, reason: MonitorUnavailabilityReason? = nil) -> String {
        let value = availability?.rawValue.uppercased() ?? "UNAVAILABLE"
        return reason.map { "\(value) (\($0.rawValue))" } ?? value
    }
}

private struct MonitorOrbView: View {
    let snapshot: MonitorRuntimeSnapshot?

    var body: some View {
        Circle()
            .fill(color.opacity(0.2))
            .overlay(Circle().stroke(color, lineWidth: 3))
            .overlay(Text(label).font(.caption2.weight(.bold)).multilineTextAlignment(.center).padding(8))
            .frame(width: 84, height: 84)
    }

    private var label: String {
        guard let snapshot else { return "OFFLINE" }
        if snapshot.sourceHealth[.desktopLocal]?.availability == .unavailable { return "SOURCE\nUNAVAILABLE" }
        return snapshot.currentState.rawValue.replacingOccurrences(of: "_", with: "\n")
    }

    private var color: Color {
        switch snapshot?.currentState {
        case .waitingApproval: .orange
        case .working: .blue
        case .thinking: .purple
        case .failed, .interrupted: .red
        case .completed: .green
        case .idle: .gray
        case .paused, .disconnected, .systemError, .none: .secondary
        }
    }
}

@MainActor
private final class FloatingStatusPanelController: NSObject, ObservableObject {
    private var panel: NSPanel?

    func show(model: MonitorAppModel) {
        guard panel == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 108, height: 108), styleMask: [.nonactivatingPanel, .titled], backing: .buffered, defer: false)
        panel.title = "Codex Monitor"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: FloatingOrbRoot(model: model))
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

private struct FloatingOrbRoot: View {
    @ObservedObject var model: MonitorAppModel
    var body: some View { MonitorOrbView(snapshot: model.snapshot).padding(12) }
}
