import AppKit
import SwiftUI
import CodexMonitorContracts

@MainActor
final class FloatingStatusPanelController: NSObject, ObservableObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var quickView: NSPanel?
    private weak var preferences: MonitorPreferences?

    func configure(model: MonitorAppModel, preferences: MonitorPreferences) {
        self.preferences = preferences
        guard preferences.showOrb else { hide(); return }
        if panel == nil { createPanel(model: model, preferences: preferences) }
        applyPreferences()
        panel?.orderFrontRegardless()
    }

    func hide() { quickView?.orderOut(nil); panel?.orderOut(nil) }
    func toggleQuickView(model: MonitorAppModel) {
        guard let panel else { return }
        if quickView?.isVisible == true { quickView?.orderOut(nil); return }
        let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let frame = FloatingPanelLayout.quickViewFrame(orbFrame: panel.frame, desiredSize: CGSize(width: 300, height: 270), visibleFrame: screen)
        let quick = NSPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: false)
        quick.title = "Codex Monitor"
        quick.level = .floating
        quick.isReleasedWhenClosed = false
        quick.contentView = NSHostingView(rootView: QuickView(model: model).padding(16))
        quick.orderFrontRegardless()
        quickView = quick
    }

    func windowDidMove(_ notification: Notification) { persistFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { persistFrame() }

    private func createPanel(model: MonitorAppModel, preferences: MonitorPreferences) {
        let size = preferences.orbSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: CGSize(width: size, height: size)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: FloatingOrbRoot(model: model, preferences: preferences) { [weak self] in self?.toggleQuickView(model: model) })
        self.panel = panel
    }

    private func applyPreferences() {
        guard let panel, let preferences else { return }
        let size = MonitorPreferences.clampedSize(preferences.orbSize)
        let screenFrames = NSScreen.screens.map(\.visibleFrame)
        let origin = preferences.orbOrigin ?? CGPoint(x: (NSScreen.main?.visibleFrame.maxX ?? 300) - size - 24, y: (NSScreen.main?.visibleFrame.midY ?? 300) - size / 2)
        panel.setFrame(NSRect(origin: FloatingPanelLayout.clampedOrigin(origin, size: CGSize(width: size, height: size), screens: screenFrames), size: CGSize(width: size, height: size)), display: true)
    }

    private func persistFrame() {
        guard let panel, let preferences else { return }
        let origin = FloatingPanelLayout.clampedOrigin(panel.frame.origin, size: panel.frame.size, screens: NSScreen.screens.map(\.visibleFrame))
        preferences.orbOrigin = origin
    }
}

private struct FloatingOrbRoot: View {
    @ObservedObject var model: MonitorAppModel
    @ObservedObject var preferences: MonitorPreferences
    let action: () -> Void
    var body: some View { MonitorOrbView(snapshot: model.snapshot, size: preferences.orbSize).contentShape(Circle()).onTapGesture(perform: action) }
}

struct MonitorOrbView: View {
    let snapshot: MonitorRuntimeSnapshot?
    let size: CGFloat

    var body: some View {
        Circle().fill(color.opacity(0.2)).overlay(Circle().stroke(color, lineWidth: max(2, size / 32))).overlay(Text(label).font(.system(size: max(9, size / 9), weight: .bold)).multilineTextAlignment(.center).padding(size / 8)).frame(width: size, height: size)
    }
    private var label: String {
        guard let snapshot else { return "OFFLINE" }
        if snapshot.sourceHealth[.desktopLocal]?.availability == .unavailable { return "SOURCE\nUNAVAILABLE" }
        if snapshot.currentState == .disconnected { return "CODEX\nUNAVAILABLE" }
        return snapshot.currentState.rawValue.replacingOccurrences(of: "_", with: "\n")
    }
    private var color: Color {
        switch snapshot?.currentState { case .waitingApproval: .orange; case .working: .blue; case .thinking: .purple; case .failed, .interrupted: .red; case .completed: .green; case .idle: .gray; case .paused, .disconnected, .systemError, .none: .secondary }
    }
}

private struct QuickView: View {
    @ObservedObject var model: MonitorAppModel
    var body: some View {
        let value = model.snapshot
        VStack(alignment: .leading, spacing: 10) {
            Text(value?.currentState.rawValue ?? "UNAVAILABLE").font(.headline)
            LabeledContent("Session Token", value: value?.sessionToken.map(String.init) ?? label(value?.currentThread?.sessionTokenAvailability))
            LabeledContent("Usage", value: value?.usage.usage?.totalTokens.map(String.init) ?? label(value?.usage.availability))
            LabeledContent("Quota", value: value?.quota.primary?.usedPercent.map { String(format: "%.0f%% used", $0) } ?? label(value?.quota.primaryAvailability))
            LabeledContent("Reset", value: value?.resetInformation.count.map(String.init) ?? label(value?.resetInformation.countAvailability))
            if value?.currentState == .waitingApproval { Text("Waiting Approval").foregroundStyle(.orange) }
            Divider(); Text("Source Health").font(.subheadline.weight(.medium))
            ForEach(MonitorRuntimeSource.allCases, id: \.rawValue) { source in LabeledContent(source.rawValue, value: label(value?.sourceHealth[source]?.availability)) }
        }
    }
    private func label(_ availability: MonitorDataAvailability?) -> String { availability?.rawValue.uppercased() ?? "UNAVAILABLE" }
}
