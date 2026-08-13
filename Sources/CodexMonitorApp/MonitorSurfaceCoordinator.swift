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
    private let localization: LocalizationController
    private let refreshMonitoring: () -> Void
    private let setMonitoringPaused: (Bool) -> Void
    private let ownership = MonitorSurfaceOwnership()
    private let loginItem = LoginItemController()
    private let notifications = MonitorNotificationController()
    private var preferencesObserver: AnyCancellable?
    private var statusItemController: MonitorStatusItemController?
    private var floatingController: FloatingStatusPanelController?
    private var usageWindowController: UsageWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var diagnosticsWindowController: DiagnosticsWindowController?

    init(model: MonitorAppModel, preferences: MonitorPreferences, localization: LocalizationController, refreshMonitoring: @escaping () -> Void, setMonitoringPaused: @escaping (Bool) -> Void) {
        self.model = model
        self.preferences = preferences
        self.localization = localization
        self.refreshMonitoring = refreshMonitoring
        self.setMonitoringPaused = setMonitoringPaused
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

        statusItemController = MonitorStatusItemController(model: model, preferences: preferences, localization: localization, actions: actions)
        floatingController = FloatingStatusPanelController(localization: localization, actions: actions)
        floatingController?.configure(model: model, preferences: preferences)
        notifications.start(model: model, preferences: preferences)

        preferencesObserver = preferences.objectWillChange.sink { [weak self] _ in
            // Published sends before mutation; schedule after the value lands.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                DiagnosticEvent.record(.settings, [
                    "event": "preferencesApplied",
                    "showOrb": String(self.preferences.showOrb),
                    "orbSize": String(Int(self.preferences.orbSize)),
                    "alwaysOnTop": String(self.preferences.alwaysOnTop),
                    "locked": String(self.preferences.lockPosition),
                    "language": self.preferences.interfaceLanguage.rawValue
                ])
                self.floatingController?.configure(model: self.model, preferences: self.preferences)
                self.statusItemController?.refresh()
            }
        }
    }

    func stop() {
        preferencesObserver?.cancel()
        preferencesObserver = nil
        notifications.stop()
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
            usageWindowController = UsageWindowController(model: model, preferences: preferences, localization: localization)
            DiagnosticEvent.record(.localization, ["event": "usageFirstCreation", "resolvedLocale": L10n.resolvedLanguage])
        }
        usageWindowController?.show()
    }

    func showSettings() {
        if settingsWindowController == nil {
            guard ownership.acquire(.settings) else { return }
            settingsWindowController = SettingsWindowController(
                preferences: preferences,
                localization: localization,
                actions: SettingsSystemActions(
                    refresh: { [weak self] in self?.refreshMonitoring() },
                    openCodex: { [weak self] in self?.openCodex() },
                    openLogsFolder: Self.openLogsFolder,
                    setMonitoringPaused: { [weak self] in self?.setMonitoringPaused($0) },
                    requestNotificationPermission: { [weak self] preference in
                        guard let self else { return }
                        self.notifications.requestPermissionThenEnable(preference, preferences: self.preferences)
                    },
                    exportDiagnostics: { [weak self] in self?.exportDiagnostics() },
                    loginItem: loginItem,
                    showDiagnostics: { [weak self] in self?.showDiagnostics() }
                )
            )
            DiagnosticEvent.record(.localization, ["event": "settingsFirstCreation", "resolvedLocale": L10n.resolvedLanguage])
        }
        settingsWindowController?.show()
    }

    func showDiagnostics() {
        if diagnosticsWindowController == nil {
            guard ownership.acquire(.diagnostics) else { return }
            diagnosticsWindowController = DiagnosticsWindowController(model: model, localization: localization)
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

    private static func openLogsFolder() {
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        guard FileManager.default.fileExists(atPath: logs.path) else { return }
        NSWorkspace.shared.open(logs)
    }

    private func exportDiagnostics() {
        let snapshot = DiagnosticPreferenceSnapshot(preferences)
        Task {
            do {
                let url = try await MonitorDiagnostics.shared.export(preferences: snapshot)
                DiagnosticEvent.record(.settings, ["event": "diagnosticsExported", "file": url.lastPathComponent])
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                DiagnosticEvent.record(.settings, ["event": "diagnosticsExportFailed", "reason": "fileWriteFailure"])
            }
        }
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
final class MonitorStatusItemController: NSObject, NSPopoverDelegate {
    private let model: MonitorAppModel
    private let preferences: MonitorPreferences
    private let localization: LocalizationController
    private let actions: MonitorSurfaceActions
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var hostedCapsule: NSHostingView<AnyView>?
    /// Native `.transient` remains the primary behavior. These monitors exist
    /// only while the popover is visible to cover AppKit's menu-bar dismissal
    /// gaps on some macOS versions, then are removed immediately on close.
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?

    init(model: MonitorAppModel, preferences: MonitorPreferences, localization: LocalizationController, actions: MonitorSurfaceActions) {
        self.model = model
        self.preferences = preferences
        self.localization = localization
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: 48)
        super.init()
        configureStatusItem()
        configurePopover()
    }

    func refresh() {
        hostedCapsule?.rootView = AnyView(LocalizedRoot(localization: localization) { MenuStatusCapsuleView(model: model, preferences: preferences).allowsHitTesting(false) })
    }

    func invalidate() {
        popover.performClose(nil)
        removeOutsideClickFallback()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Read-only lifecycle seam for the native-popover regression test.
    var popoverBehaviorForTesting: NSPopover.Behavior { popover.behavior }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            preparePopoverContent(for: button)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            installOutsideClickFallback()
            DiagnosticEvent.record(.popover, [
                "event": "show", "placementOwner": "AppKitNativePopover",
                "locale": L10n.resolvedLanguage
            ])
            DispatchQueue.main.async { [weak self] in self?.recordPresentedPopoverFrame() }
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = ""
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        // A status-item tooltip can overlap an attached NSPopover. This item
        // always uses its accessible label instead.
        button.toolTip = nil

        let hosting = NSHostingView(rootView: AnyView(LocalizedRoot(localization: localization) { MenuStatusCapsuleView(model: model, preferences: preferences).allowsHitTesting(false) }))
        hosting.frame = NSRect(x: 0, y: 0, width: 48, height: 22)
        hosting.autoresizingMask = [.width, .height]
        button.addSubview(hosting)
        hostedCapsule = hosting
    }

    private func configurePopover() {
        popover.delegate = self
        popover.behavior = .transient
        DiagnosticEvent.record(.localization, ["event": "popoverFirstCreation", "resolvedLocale": L10n.resolvedLanguage])
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickFallback()
        DiagnosticEvent.record(.popover, ["event": "close", "locale": L10n.resolvedLanguage])
    }

    private func installOutsideClickFallback() {
        guard localOutsideClickMonitor == nil, globalOutsideClickMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let point = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.dismissPopoverIfOutsideClick(at: point) }
            return event
        }
        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.dismissPopoverIfOutsideClick(at: point) }
        }
        DiagnosticEvent.record(.popover, ["event": "outsideClickFallbackInstalled"])
    }

    private func removeOutsideClickFallback() {
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
    }

    private func dismissPopoverIfOutsideClick(at screenPoint: CGPoint) {
        guard popover.isShown,
              let popoverFrame = popover.contentViewController?.view.window?.frame,
              let statusButtonFrame = statusButtonFrameOnScreen else {
            return
        }
        guard Self.shouldDismissPopover(at: screenPoint, popoverFrame: popoverFrame, statusButtonFrame: statusButtonFrame) else { return }
        DiagnosticEvent.record(.popover, ["event": "outsideClickFallbackDismiss"])
        popover.performClose(nil)
    }

    private var statusButtonFrameOnScreen: CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    static func shouldDismissPopover(at point: CGPoint, popoverFrame: CGRect, statusButtonFrame: CGRect) -> Bool {
        !popoverFrame.contains(point) && !statusButtonFrame.contains(point)
    }

    private func popoverRoot(maximumContentHeight: CGFloat?) -> AnyView {
        AnyView(LocalizedRoot(localization: localization) {
            MenuBarPopoverView(
                model: model,
                preferences: preferences,
                actions: actions,
                maximumContentHeight: maximumContentHeight
            )
        })
    }

    /// A popover's previous hosting tree can retain layout constraints and a
    /// ScrollView offset. Each open therefore measures a brand-new host, then
    /// installs exactly one fresh normal-or-scrollable root. AppKit remains
    /// the only placement owner; this never calls `setFrame` on a window.
    private func preparePopoverContent(for button: NSStatusBarButton) {
        let normalHost = NSHostingController(rootView: popoverRoot(maximumContentHeight: nil))
        let desired = normalHost.sizeThatFits(in: NSSize(width: 340, height: CGFloat.greatestFiniteMagnitude))
        let visible = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonScreenRect = button.window?.convertToScreen(buttonRectInWindow) ?? .zero
        let availableBelow = buttonScreenRect.minY - visible.minY
        // Preserve space for the native arrow and chrome. The content itself
        // scrolls only when it cannot fit below this real status-item anchor.
        let maximumHeight = max(1, floor(availableBelow - 32))
        let desiredHeight = max(1, ceil(desired.height))
        if desiredHeight > maximumHeight {
            let scrollHost = NSHostingController(rootView: popoverRoot(maximumContentHeight: maximumHeight))
            popover.contentViewController = scrollHost
            popover.contentSize = NSSize(width: 340, height: maximumHeight)
            DiagnosticEvent.record(.popover, ["event": "contentScrollEnabled", "height": String(Int(maximumHeight))])
        } else {
            popover.contentViewController = normalHost
            popover.contentSize = NSSize(width: 340, height: desiredHeight)
        }
    }

    private func recordPresentedPopoverFrame() {
        guard let frame = popover.contentViewController?.view.window?.frame else { return }
        let visible = statusItem.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let contained = visible.map { $0.contains(frame) } ?? false
        DiagnosticEvent.record(.popover, [
            "event": "presentedFrame",
            "containedInVisibleFrame": String(contained),
            "width": String(Int(frame.width)),
            "height": String(Int(frame.height))
        ])
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
    init(model: MonitorAppModel, preferences: MonitorPreferences, localization: LocalizationController) {
        let window = Self.makeWindow(size: NSSize(width: 600, height: 560), minSize: NSSize(width: 500, height: 460))
        window.contentView = NSHostingView(rootView: LocalizedRoot(localization: localization) { UsageWindowView(model: model, preferences: preferences) })
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

/// The one Settings surface owner. It is retained for the app lifetime and
/// closes by ordering out, so every entry point reopens the exact same host.
@MainActor
final class SettingsWindowController: ReusableNativeWindowController, NSWindowDelegate {
    let presentation: SettingsPresentationModel
    let hostingController: NSHostingController<AnyView>

    init(preferences: MonitorPreferences, localization: LocalizationController, actions: SettingsSystemActions) {
        let presentation = SettingsPresentationModel()
        let window = Self.makeWindow(size: NSSize(width: 780, height: 540), minSize: NSSize(width: 760, height: 460))
        let hostingController = NSHostingController(
            rootView: AnyView(LocalizedRoot(localization: localization) { NativeSettingsWindowView(
                preferences: preferences,
                presentation: presentation,
                actions: actions
            ) })
        )
        window.contentViewController = hostingController
        self.presentation = presentation
        self.hostingController = hostingController
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    /// The title-bar close control follows the same order-out path as every
    /// programmatic close, preserving the retained root and selected section.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

@MainActor
final class DiagnosticsWindowController: ReusableNativeWindowController {
    init(model: MonitorAppModel, localization: LocalizationController) {
        let window = Self.makeWindow(size: NSSize(width: 520, height: 510), minSize: NSSize(width: 460, height: 400))
        window.contentView = NSHostingView(rootView: LocalizedRoot(localization: localization) { DiagnosticsWindowView(model: model) })
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}
