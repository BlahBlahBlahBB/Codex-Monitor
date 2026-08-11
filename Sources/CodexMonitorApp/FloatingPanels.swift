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
        let frame = FloatingPanelLayout.quickViewFrame(orbFrame: panel.frame, desiredSize: CGSize(width: 320, height: 330), visibleFrame: screen)
        let quick = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        quick.level = .floating
        quick.isOpaque = false
        quick.backgroundColor = .clear
        quick.hasShadow = true
        quick.isReleasedWhenClosed = false
        quick.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        quick.contentView = NSHostingView(rootView: QuickView(model: model))
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
    var body: some View {
        MonitorOrbView(snapshot: model.snapshot, size: preferences.orbSize)
            .contentShape(Circle())
            .onTapGesture(perform: action)
    }
}

private struct QuickView: View {
    @ObservedObject var model: MonitorAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false

    var body: some View {
        let value = model.snapshot
        GlassSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MonitorDisplayValue.state(value))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text(MonitorDisplayValue.activity(value))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    MonitorStatusCapsule(snapshot: value)
                }

                if value?.currentState == .waitingApproval {
                    Label("Waiting Approval", systemImage: "hand.raised.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .systemYellow))
                }

                MonitorDivider()
                VStack(alignment: .leading, spacing: 10) {
                    MonitorSectionTitle(title: "Session")
                    MonitorValueRow(title: "Session Token", value: MonitorDisplayValue.token(value))
                }
                VStack(alignment: .leading, spacing: 10) {
                    MonitorSectionTitle(title: "Account")
                    MonitorValueRow(title: "Usage", value: MonitorDisplayValue.usage(value))
                    MonitorValueRow(title: "Quota", value: MonitorDisplayValue.quota(value))
                    MonitorValueRow(title: "Reset", value: MonitorDisplayValue.reset(value))
                }
                VStack(alignment: .leading, spacing: 10) {
                    MonitorSectionTitle(title: "Source Health")
                    ForEach(MonitorRuntimeSource.allCases, id: \.rawValue) { source in
                        MonitorValueRow(
                            title: MonitorDisplayValue.source(source),
                            value: MonitorDisplayValue.availability(value?.sourceHealth[source]?.availability),
                            valueColor: source == .desktopLocal && value?.sourceHealth[source]?.availability == .available ? Color(nsColor: .systemGreen) : .secondary
                        )
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 320, height: 330)
        .scaleEffect(isPresented || reduceMotion ? 1 : 0.97)
        .opacity(isPresented || reduceMotion ? 1 : 0)
        .onAppear {
            if reduceMotion {
                isPresented = true
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isPresented = true
                }
            }
        }
        .onChange(of: reduceMotion) { value in
            if value { isPresented = true }
        }
    }
}
