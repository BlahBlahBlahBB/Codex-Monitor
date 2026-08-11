import AppKit
import SwiftUI
import CodexMonitorContracts

@MainActor
final class FloatingStatusPanelController: NSObject, ObservableObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var quickView: NSPanel?
    private weak var preferences: MonitorPreferences?
    private let actions: MonitorSurfaceActions
    private var hasPlacedPanel = false
    private var liveResizeCenter: CGPoint?

    init(actions: MonitorSurfaceActions) {
        self.actions = actions
        super.init()
    }

    func configure(model: MonitorAppModel, preferences: MonitorPreferences) {
        self.preferences = preferences
        guard preferences.showOrb else { hide(); return }
        if panel == nil { createPanel(model: model, preferences: preferences) }
        applyPreferences()
        panel?.orderFrontRegardless()
    }

    func hide() {
        quickView?.orderOut(nil)
        panel?.orderOut(nil)
    }

    func closeAll() {
        quickView?.close()
        panel?.close()
        quickView = nil
        panel = nil
        hasPlacedPanel = false
    }

    func toggleQuickView(model: MonitorAppModel) {
        guard let panel else { return }
        if quickView?.isVisible == true {
            quickView?.orderOut(nil)
            return
        }

        let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let frame = FloatingPanelLayout.quickViewFrame(
            orbFrame: panel.frame,
            desiredSize: FloatingOrbSurfaceConfiguration.quickViewSize,
            visibleFrame: screen
        )
        let quick = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        quick.level = .floating
        quick.isOpaque = false
        quick.backgroundColor = .clear
        quick.hasShadow = false
        quick.isReleasedWhenClosed = false
        quick.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        quick.contentView = NSHostingView(rootView: QuickView(model: model))
        quick.orderFrontRegardless()
        quickView = quick
    }

    func windowWillMove(_ notification: Notification) {
        quickView?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) { persistFrame() }
    func windowWillStartLiveResize(_ notification: Notification) {
        liveResizeCenter = panel.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else { return }
        if let center = liveResizeCenter {
            let size = MonitorPreferences.clampedSize(panel.frame.width)
            let origin = FloatingPanelLayout.centerPreservingOrigin(
                center: center,
                size: CGSize(width: size, height: size),
                screens: NSScreen.screens.map(\.visibleFrame)
            )
            panel.setFrame(NSRect(origin: origin, size: CGSize(width: size, height: size)), display: true)
        }
        liveResizeCenter = nil
        persistFrame()
    }

    private func createPanel(model: MonitorAppModel, preferences: MonitorPreferences) {
        let size = preferences.orbSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: size, height: size)),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = FloatingOrbSurfaceConfiguration.isOpaque
        panel.backgroundColor = .clear
        panel.hasShadow = FloatingOrbSurfaceConfiguration.hasPanelShadow
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let root = FloatingOrbRoot(model: model, preferences: preferences) { [weak self] in
            self?.toggleQuickView(model: model)
        }
        let hostingView = OrbHostingView(rootView: root, menuProvider: { [weak self] in
            self?.makeContextMenu() ?? NSMenu()
        })
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        self.panel = panel
    }

    private func applyPreferences() {
        guard let panel, let preferences else { return }
        let size = MonitorPreferences.clampedSize(preferences.orbSize)
        let screenFrames = NSScreen.screens.map(\.visibleFrame)
        let origin: CGPoint
        if hasPlacedPanel {
            let current = panel.frame
            if abs(current.width - size) > 0.5 {
                // Live preference changes retain the screen-space center.
                origin = FloatingPanelLayout.centerPreservingOrigin(
                    center: CGPoint(x: current.midX, y: current.midY),
                    size: CGSize(width: size, height: size),
                    screens: screenFrames
                )
            } else {
                origin = current.origin
            }
        } else {
            origin = preferences.orbOrigin ?? CGPoint(
                x: (NSScreen.main?.visibleFrame.maxX ?? 300) - size - 24,
                y: (NSScreen.main?.visibleFrame.midY ?? 300) - size / 2
            )
        }
        panel.setFrame(
            NSRect(
                origin: FloatingPanelLayout.clampedOrigin(origin, size: CGSize(width: size, height: size), screens: screenFrames),
                size: CGSize(width: size, height: size)
            ),
            display: true
        )
        hasPlacedPanel = true
    }

    private func persistFrame() {
        guard let panel, let preferences else { return }
        let size = MonitorPreferences.clampedSize(panel.frame.width)
        preferences.orbSize = size
        let origin = FloatingPanelLayout.clampedOrigin(
            panel.frame.origin,
            size: CGSize(width: size, height: size),
            screens: NSScreen.screens.map(\.visibleFrame)
        )
        preferences.orbOrigin = origin
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Codex Monitor")
        menu.addItem(withTitle: L10n.tr("menu.refresh"), action: #selector(refresh), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.tr("menu.usage"), action: #selector(showUsage), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.tr("menu.openCodex"), action: #selector(openCodex), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let alwaysOnTop = menu.addItem(withTitle: L10n.tr("menu.alwaysOnTopUnavailable"), action: nil, keyEquivalent: "")
        alwaysOnTop.isEnabled = false
        let lockPosition = menu.addItem(withTitle: L10n.tr("menu.lockPositionUnavailable"), action: nil, keyEquivalent: "")
        lockPosition.isEnabled = false
        menu.addItem(withTitle: L10n.tr("menu.hideFloating"), action: #selector(hideOrb), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("menu.settings"), action: #selector(showSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.tr("menu.quitMonitor"), action: #selector(quit), keyEquivalent: "").target = self
        return menu
    }

    @objc private func refresh() { actions.refresh() }
    @objc private func showUsage() { actions.showUsage() }
    @objc private func openCodex() { actions.openCodex() }
    @objc private func hideOrb() { actions.toggleOrb() }
    @objc private func showSettings() { actions.showSettings() }
    @objc private func quit() { actions.quit() }
}

private final class OrbHostingView: NSHostingView<FloatingOrbRoot> {
    private let menuProvider: () -> NSMenu

    init(rootView: FloatingOrbRoot, menuProvider: @escaping () -> NSMenu) {
        self.menuProvider = menuProvider
        super.init(rootView: rootView)
    }

    required init(rootView: FloatingOrbRoot) {
        menuProvider = { NSMenu() }
        super.init(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        menuProvider = { NSMenu() }
        super.init(coder: coder)
    }

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider()
    }
}

struct FloatingOrbRoot: View {
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let snapshot = model.snapshot
        GlassSurface(cornerRadius: 22, shadow: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Codex")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(MonitorDisplayValue.update(snapshot))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Circle().fill(MonitorVisualPalette.forSnapshot(snapshot).tint).frame(width: 7, height: 7)
                    Text(MonitorDisplayValue.state(snapshot))
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.top, 5)

                Text(MonitorDisplayValue.taskTitle(snapshot))
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .padding(.top, 14)
                Text(MonitorDisplayValue.activity(snapshot))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 3)

                MonitorDivider().padding(.vertical, 14)

                Text(MonitorDisplayValue.modelRuntime(snapshot))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(String(format: L10n.tr("session.tokenQuota"), MonitorDisplayValue.token(snapshot), MonitorDisplayValue.orbQuota(snapshot)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
        }
        .frame(width: 350, height: 214)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Codex \(MonitorDisplayValue.state(snapshot)). \(MonitorDisplayValue.activity(snapshot))")
    }
}
