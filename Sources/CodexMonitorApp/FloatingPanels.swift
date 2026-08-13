import AppKit
import SwiftUI
import CodexMonitorContracts

@MainActor
final class FloatingStatusPanelController: NSObject, ObservableObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var quickView: NSPanel?
    private weak var preferences: MonitorPreferences?
    private let localization: LocalizationController
    private let actions: MonitorSurfaceActions
    private var hasPlacedPanel = false
    private var liveResizeCenter: CGPoint?
    private let quickViewAutoDismissDelay: Duration
    private var quickViewDismissTask: Task<Void, Never>?

    init(localization: LocalizationController, actions: MonitorSurfaceActions, quickViewAutoDismissDelay: Duration = QuickViewInteractionContract.automaticDismissDelay) {
        self.localization = localization
        self.actions = actions
        self.quickViewAutoDismissDelay = quickViewAutoDismissDelay
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
        hideQuickView()
        panel?.orderOut(nil)
    }

    func closeAll() {
        cancelQuickViewAutoDismiss()
        quickView?.close()
        panel?.close()
        quickView = nil
        panel = nil
        hasPlacedPanel = false
    }

    func toggleQuickView(model: MonitorAppModel) {
        guard let panel, let preferences else { return }

        let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let frame = FloatingPanelLayout.quickViewFrame(
            orbFrame: visibleOrbFrame(for: panel),
            desiredSize: FloatingOrbSurfaceConfiguration.quickViewSize,
            visibleFrame: screen
        )
        if let quickView {
            quickView.level = preferences.alwaysOnTop ? .floating : .normal
            quickView.setFrame(frame, display: true)
            quickView.orderFrontRegardless()
            scheduleQuickViewAutoDismiss()
            return
        }
        let quick = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        quick.level = preferences.alwaysOnTop ? .floating : .normal
        quick.isOpaque = false
        quick.backgroundColor = .clear
        quick.hasShadow = false
        quick.isReleasedWhenClosed = false
        quick.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        quick.contentView = NSHostingView(rootView: LocalizedRoot(localization: localization) { QuickView(model: model, preferences: preferences) })
        DiagnosticEvent.record(.localization, ["event": "quickViewFirstCreation", "resolvedLocale": L10n.resolvedLanguage])
        quick.orderFrontRegardless()
        quickView = quick
        scheduleQuickViewAutoDismiss()
    }

    /// Narrow lifecycle seam for the product regression test. The panel stays
    /// owned by this controller and is never exposed to SwiftUI.
    var quickViewForTesting: NSPanel? { quickView }

    func windowWillMove(_ notification: Notification) { hideQuickView() }

    func windowDidMove(_ notification: Notification) { persistFrame() }
    func windowWillStartLiveResize(_ notification: Notification) {
        liveResizeCenter = panel.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else { return }
        if let center = liveResizeCenter {
            let size = MonitorPreferences.clampedSize(panel.frame.width - FloatingOrbSurfaceConfiguration.shadowInset * 2)
            let origin = FloatingPanelLayout.centerPreservingOrigin(
                center: center,
                size: FloatingOrbSurfaceConfiguration.hostSize(forOrbSize: size),
                screens: NSScreen.screens.map(\.visibleFrame)
            )
            panel.setFrame(NSRect(origin: origin, size: FloatingOrbSurfaceConfiguration.hostSize(forOrbSize: size)), display: true)
        }
        liveResizeCenter = nil
        persistFrame()
    }

    private func createPanel(model: MonitorAppModel, preferences: MonitorPreferences) {
        let size = preferences.orbSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: FloatingOrbSurfaceConfiguration.hostSize(forOrbSize: size)),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = preferences.alwaysOnTop ? .floating : .normal
        panel.isOpaque = FloatingOrbSurfaceConfiguration.isOpaque
        panel.backgroundColor = .clear
        panel.hasShadow = FloatingOrbSurfaceConfiguration.hasPanelShadow
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let root = AnyView(LocalizedRoot(localization: localization) { FloatingOrbRoot(model: model, preferences: preferences) { [weak self] in
            self?.toggleQuickView(model: model)
        } })
        let hostingView = OrbHostingView(rootView: root, menuProvider: { [weak self] in
            self?.makeContextMenu() ?? NSMenu()
        })
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        hostingView.layer?.cornerRadius = 0
        hostingView.layer?.masksToBounds = false
        hostingView.layer?.shadowOpacity = 0
        panel.contentView = hostingView
        self.panel = panel
        OrbHostDiagnostics.capture(panel: panel, contentView: hostingView)
        DispatchQueue.main.async {
            DiagnosticEvent.record(.orbHost, [
                "event": "hostCompositorContract",
                "panelOpaque": String(panel.isOpaque),
                "panelShadow": String(panel.hasShadow),
                "hostOpaque": String(hostingView.isOpaque),
                "hostBackgroundClear": String(hostingView.layer?.backgroundColor == NSColor.clear.cgColor),
                "orbMaterial": "CircularVisualEffectView"
            ])
        }
    }

    private func applyPreferences() {
        guard let panel, let preferences else { return }
        panel.level = preferences.alwaysOnTop ? .floating : .normal
        panel.isMovableByWindowBackground = !preferences.lockPosition
        let size = MonitorPreferences.clampedSize(preferences.orbSize)
        let hostSize = FloatingOrbSurfaceConfiguration.hostSize(forOrbSize: size)
        let screenFrames = NSScreen.screens.map(\.visibleFrame)
        let orbOrigin: CGPoint
        if hasPlacedPanel {
            let current = visibleOrbFrame(for: panel)
            if abs(current.width - size) > 0.5 {
                // Live preference changes retain the screen-space center.
                orbOrigin = FloatingPanelLayout.centerPreservingOrigin(
                    center: CGPoint(x: current.midX, y: current.midY),
                    size: CGSize(width: size, height: size),
                    screens: screenFrames
                )
            } else {
                orbOrigin = current.origin
            }
        } else {
            orbOrigin = preferences.orbOrigin ?? CGPoint(
                x: (NSScreen.main?.visibleFrame.maxX ?? 300) - size - 24,
                y: (NSScreen.main?.visibleFrame.midY ?? 300) - size / 2
            )
        }
        let clampedOrbOrigin = FloatingPanelLayout.clampedOrigin(orbOrigin, size: CGSize(width: size, height: size), screens: screenFrames)
        panel.setFrame(
            NSRect(
                origin: CGPoint(x: clampedOrbOrigin.x - FloatingOrbSurfaceConfiguration.shadowInset, y: clampedOrbOrigin.y - FloatingOrbSurfaceConfiguration.shadowInset),
                size: hostSize
            ),
            display: true
        )
        hasPlacedPanel = true
    }

    private func persistFrame() {
        guard let panel, let preferences else { return }
        let size = MonitorPreferences.clampedSize(panel.frame.width - FloatingOrbSurfaceConfiguration.shadowInset * 2)
        preferences.orbSize = size
        let origin = FloatingPanelLayout.clampedOrigin(
            visibleOrbFrame(for: panel).origin,
            size: CGSize(width: size, height: size),
            screens: NSScreen.screens.map(\.visibleFrame)
        )
        preferences.orbOrigin = origin
    }

    private func visibleOrbFrame(for panel: NSPanel) -> CGRect {
        panel.frame.insetBy(dx: FloatingOrbSurfaceConfiguration.shadowInset, dy: FloatingOrbSurfaceConfiguration.shadowInset)
    }

    private func scheduleQuickViewAutoDismiss() {
        cancelQuickViewAutoDismiss()
        let delay = quickViewAutoDismissDelay
        quickViewDismissTask = Task { [weak self, delay] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.hideQuickView()
        }
    }

    private func cancelQuickViewAutoDismiss() {
        quickViewDismissTask?.cancel()
        quickViewDismissTask = nil
    }

    private func hideQuickView() {
        cancelQuickViewAutoDismiss()
        quickView?.orderOut(nil)
    }

    private func makeContextMenu() -> NSMenu {
        DiagnosticEvent.record(.localization, ["event": "contextMenuCreation", "resolvedLocale": L10n.resolvedLanguage])
        let menu = NSMenu(title: "Codex Monitor")
        menu.addItem(withTitle: L10n.tr("menu.refresh"), action: #selector(refresh), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.tr("menu.usage"), action: #selector(showUsage), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.tr("menu.openCodex"), action: #selector(openCodex), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let alwaysOnTop = menu.addItem(withTitle: L10n.tr("menu.alwaysOnTop"), action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTop.target = self
        alwaysOnTop.state = preferences?.alwaysOnTop == true ? .on : .off
        let lockPosition = menu.addItem(withTitle: L10n.tr("menu.lockPosition"), action: #selector(toggleLockPosition), keyEquivalent: "")
        lockPosition.target = self
        lockPosition.state = preferences?.lockPosition == true ? .on : .off
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
    @objc private func toggleAlwaysOnTop() { preferences?.alwaysOnTop.toggle() }
    @objc private func toggleLockPosition() { preferences?.lockPosition.toggle() }
}

final class OrbHostingView: NSHostingView<AnyView> {
    private let menuProvider: () -> NSMenu

    init(rootView: AnyView, menuProvider: @escaping () -> NSMenu) {
        self.menuProvider = menuProvider
        super.init(rootView: rootView)
    }

    convenience init(rootView: FloatingOrbRoot, menuProvider: @escaping () -> NSMenu = { NSMenu() }) {
        self.init(rootView: AnyView(rootView), menuProvider: menuProvider)
    }

    required init(rootView: AnyView) {
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
        MonitorOrbView(snapshot: model.snapshot, presentation: model.presentation(using: preferences), size: preferences.orbSize)
            .contentShape(Circle())
            .onTapGesture(perform: action)
    }
}

private struct QuickView: View {
    @ObservedObject var model: MonitorAppModel
    @ObservedObject var preferences: MonitorPreferences
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let snapshot = model.snapshot
        let presentation = model.presentation(using: preferences)
        GlassSurface(cornerRadius: 22, shadow: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Codex")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.15)
                    Spacer(minLength: 8)
                    Text(MonitorDisplayValue.update(snapshot))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Circle().fill(presentation.orbTone.color).frame(width: 7, height: 7)
                    Text(MonitorDisplayValue.state(presentation))
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.top, 5)

                Text(MonitorDisplayValue.quickViewTaskTitle(snapshot))
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .padding(.top, 12)
                Text(MonitorDisplayValue.activity(snapshot))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 3)
                MonitorDivider().padding(.vertical, 12)

                Text(MonitorDisplayValue.modelRuntime(snapshot))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(String(format: L10n.tr("session.tokenQuota"), MonitorDisplayValue.token(snapshot), MonitorDisplayValue.orbQuota(snapshot)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.top, 6)
                Text("\(L10n.tr("label.quotaReset"))  \(MonitorDisplayValue.quotaResetDate(snapshot))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .frame(width: 350, height: 214)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: L10n.tr("accessibility.quickView"), MonitorDisplayValue.state(presentation), MonitorDisplayValue.activity(snapshot)))
    }
}
