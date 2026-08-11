import AppKit
import Combine
import SwiftUI
import CodexMonitorContracts

/// Owns native presentation surfaces only. Runtime observation, capability
/// admission, and source I/O remain outside this coordinator.
@MainActor
final class MonitorSurfaceCoordinator: NSObject {
    private let model: MonitorAppModel
    private let preferences: MonitorPreferences
    private let refreshMonitoring: () -> Void
    private let ownership = MonitorSurfaceOwnership()
    private var preferencesObserver: AnyCancellable?
    private var statusItemController: MonitorStatusItemController?
    private var floatingController: FloatingStatusPanelController?
    private var usageWindowController: UsageWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var diagnosticsWindowController: DiagnosticsWindowController?

    init(model: MonitorAppModel, preferences: MonitorPreferences, refreshMonitoring: @escaping () -> Void) {
        self.model = model
        self.preferences = preferences
        self.refreshMonitoring = refreshMonitoring
    }

    func start() {
        guard ownership.acquire(.statusItem), ownership.acquire(.orb) else { return }
        let actions = MonitorSurfaceActions(
            showUsage: { [weak self] in self?.showUsage() },
            showSettings: { [weak self] in self?.showSettings() },
            toggleOrb: { [weak self] in self?.toggleOrb() },
            openCodex: { [weak self] in self?.openCodex() },
            quit: { NSApp.terminate(nil) },
            refresh: { [weak self] in self?.refreshMonitoring() },
            showDiagnostics: { [weak self] in self?.showDiagnostics() }
        )

        statusItemController = MonitorStatusItemController(model: model, preferences: preferences, actions: actions)
        floatingController = FloatingStatusPanelController(actions: actions)
        floatingController?.configure(model: model, preferences: preferences)

        preferencesObserver = preferences.objectWillChange.sink { [weak self] _ in
            // Published sends before mutation; schedule after the value lands.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.floatingController?.configure(model: self.model, preferences: self.preferences)
                self.statusItemController?.refresh()
            }
        }
    }

    func stop() {
        preferencesObserver?.cancel()
        preferencesObserver = nil
        floatingController?.closeAll()
        statusItemController?.invalidate()
        usageWindowController?.close()
        settingsWindowController?.close()
        diagnosticsWindowController?.close()
        ownership.reset()
    }

    func showUsage() {
        if usageWindowController == nil {
            guard ownership.acquire(.usage) else { return }
            usageWindowController = UsageWindowController(model: model)
        }
        usageWindowController?.show()
    }

    func showSettings() {
        if settingsWindowController == nil {
            guard ownership.acquire(.settings) else { return }
            settingsWindowController = SettingsWindowController(
                preferences: preferences,
                showDiagnostics: { [weak self] in self?.showDiagnostics() }
            )
        }
        settingsWindowController?.show()
    }

    func showDiagnostics() {
        if diagnosticsWindowController == nil {
            guard ownership.acquire(.diagnostics) else { return }
            diagnosticsWindowController = DiagnosticsWindowController(model: model)
        }
        diagnosticsWindowController?.show()
    }

    func toggleOrb() {
        preferences.showOrb.toggle()
    }

    private func openCodex() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

struct MonitorSurfaceActions {
    let showUsage: () -> Void
    let showSettings: () -> Void
    let toggleOrb: () -> Void
    let openCodex: () -> Void
    let quit: () -> Void
    let refresh: () -> Void
    let showDiagnostics: () -> Void
}

@MainActor
final class MonitorStatusItemController: NSObject {
    private let model: MonitorAppModel
    private let preferences: MonitorPreferences
    private let actions: MonitorSurfaceActions
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var hostedCapsule: NSHostingView<AnyView>?

    init(model: MonitorAppModel, preferences: MonitorPreferences, actions: MonitorSurfaceActions) {
        self.model = model
        self.preferences = preferences
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: 48)
        super.init()
        configureStatusItem()
        configurePopover()
    }

    func refresh() {
        hostedCapsule?.rootView = AnyView(MenuStatusCapsuleView(model: model).allowsHitTesting(false))
    }

    func invalidate() {
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = ""
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        button.toolTip = "Codex Monitor"

        let hosting = NSHostingView(rootView: AnyView(MenuStatusCapsuleView(model: model).allowsHitTesting(false)))
        hosting.frame = NSRect(x: 0, y: 0, width: 48, height: 22)
        hosting.autoresizingMask = [.width, .height]
        button.addSubview(hosting)
        hostedCapsule = hosting
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 350)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(model: model, preferences: preferences, actions: actions)
        )
    }
}

@MainActor
class ReusableNativeWindowController: NSWindowController {
    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    override func close() {
        window?.orderOut(nil)
    }

    static func makeWindow(size: NSSize, minSize: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.collectionBehavior = [.fullScreenAuxiliary]
        return window
    }
}

@MainActor
final class UsageWindowController: ReusableNativeWindowController {
    init(model: MonitorAppModel) {
        let window = Self.makeWindow(size: NSSize(width: 600, height: 560), minSize: NSSize(width: 500, height: 460))
        window.contentView = NSHostingView(rootView: UsageWindowView(model: model))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

/// The one Settings surface owner. It is retained for the app lifetime and
/// closes by ordering out, so every entry point reopens the exact same host.
@MainActor
final class SettingsWindowController: ReusableNativeWindowController {
    let presentation: SettingsPresentationModel
    init(preferences: MonitorPreferences, showDiagnostics: @escaping () -> Void) {
        let presentation = SettingsPresentationModel()
        let window = Self.makeWindow(size: NSSize(width: 720, height: 500), minSize: NSSize(width: 600, height: 420))
        window.contentView = NSHostingView(rootView: NativeSettingsWindowView(preferences: preferences, presentation: presentation, showDiagnostics: showDiagnostics))
        self.presentation = presentation
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
final class DiagnosticsWindowController: ReusableNativeWindowController {
    init(model: MonitorAppModel) {
        let window = Self.makeWindow(size: NSSize(width: 520, height: 510), minSize: NSSize(width: 460, height: 400))
        window.contentView = NSHostingView(rootView: DiagnosticsWindowView(model: model))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}
