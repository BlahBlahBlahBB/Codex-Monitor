#if CODEX_MONITOR_QA_ISOLATION
import AppKit
import Foundation

/// QA-only passive event observer. Every local monitor returns its input event
/// unchanged; no event routing, window geometry, or gesture behavior is altered.
@MainActor
final class OrbDragProbe {
    static let shared = OrbDragProbe()
    static let outputURL = URL(fileURLWithPath: "/private/tmp/codex-monitor-d1-p7-events.jsonl")

    private weak var targetPanel: NSPanel?
    private weak var preferences: MonitorPreferences?
    private var monitors: [Any] = []
    private var lines: [String] = []
    private var isRecording = false
    private var sequenceID: String?
    private let maximumLogBytes: UInt64 = 1_000_000
    private var loggingCapped = false

    private init() {}

    func installIfNeeded(targetPanel: NSPanel?, preferences: MonitorPreferences) {
        guard monitors.isEmpty, let targetPanel else { return }
        self.targetPanel = targetPanel
        self.preferences = preferences
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        guard let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.observe(event)
            }
            return event
        }) else {
            append("t=\(ProcessInfo.processInfo.systemUptime) sequence=none event=probe.install.failed")
            flushSoon()
            return
        }
        monitors.append(monitor)
        record("probe.install monitor.count=\(monitors.count)", panel: targetPanel, preferences: preferences)
    }

    func recordLifecycle(_ event: String, monitorCount: Int, tracking: Bool, hasMouseDown: Bool, panel: NSPanel?) {
        guard isRecording else { return }
        append("t=\(ProcessInfo.processInfo.systemUptime) event=\(event) monitor.count=\(monitorCount) tracking=\(tracking) hasMouseDownEvent=\(hasMouseDown) panelWindow=\(panel?.windowNumber ?? -1) frame=\(panel.map { Self.rect($0.frame) } ?? "nil")")
    }

    func flushSoon() {
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    func record(_ name: String, panel: NSPanel?, preferences: MonitorPreferences?) {
        guard isRecording || name.hasPrefix("probe.install") || name == "configure.begin" else { return }
        guard let panel else {
            append("t=\(ProcessInfo.processInfo.systemUptime) event=\(name) panel=nil")
            return
        }
        let frame = Self.rect(panel.frame)
        let line = "t=\(ProcessInfo.processInfo.systemUptime) event=\(name) panelWindow=\(panel.windowNumber) movable=\(panel.isMovable) backgroundMovable=\(panel.isMovableByWindowBackground) lockPosition=\(preferences?.lockPosition.description ?? "nil") frame=\(frame)"
        append(line)
    }

    static func rect(_ rect: NSRect) -> String {
        "(x:\(rect.origin.x),y:\(rect.origin.y),w:\(rect.width),h:\(rect.height))"
    }

    private static func viewChain(from hitView: NSView?, through contentView: NSView) -> String {
        guard let hitView else { return "none" }
        var entries: [String] = []
        var current: NSView? = hitView
        while let view = current {
            entries.append("\(String(describing: type(of: view))){mouseDownCanMoveWindow:\(view.mouseDownCanMoveWindow),isOpaque:\(view.isOpaque)}")
            if view === contentView { break }
            current = view.superview
        }
        return "[\(entries.joined(separator: ">"))]"
    }

    private func observe(_ event: NSEvent) {
        let kind: String
        switch event.type {
        case .leftMouseDown:
            kind = "mouseDown"
            sequenceID = UUID().uuidString
            isRecording = true
        case .leftMouseDragged: kind = "mouseDragged"
        case .leftMouseUp: kind = "mouseUp"
        default: return
        }
        let eventWindow = event.window?.windowNumber ?? -1
        let targetNumber = targetPanel?.windowNumber ?? -1
        let location = event.locationInWindow
        let panel = targetPanel
        var hitDetails = ""
        if event.type == .leftMouseDown, let panel, let contentView = panel.contentView {
            let point = contentView.convert(location, from: nil)
            let hitView = contentView.hitTest(point)
            let hostEligibility = (contentView as? OrbHostingView)?.mouseDownCanMoveWindow.description ?? "notOrbHostingView"
            hitDetails = " hitChain=\(Self.viewChain(from: hitView, through: contentView)) orbHostingMouseDownCanMoveWindow=\(hostEligibility)"
        }
        let line = "t=\(ProcessInfo.processInfo.systemUptime) event=\(kind) eventWindow=\(eventWindow) targetWindow=\(targetNumber) locationInWindow=(x:\(location.x),y:\(location.y)) movable=\(panel?.isMovable.description ?? "nil") backgroundMovable=\(panel?.isMovableByWindowBackground.description ?? "nil") lockPosition=\(preferences?.lockPosition.description ?? "nil") frame=\(panel.map { Self.rect($0.frame) } ?? "nil")\(hitDetails)"
        append(line)
        if event.type == .leftMouseUp {
            DispatchQueue.main.async { [weak self] in
                self?.flush()
                self?.isRecording = false
            }
        }
    }

    private func append(_ line: String) {
        lines.append("sequence=\(sequenceID ?? "none") \(line)")
    }

    private func flush() {
        guard !lines.isEmpty else { return }
        let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
        do {
            guard !loggingCapped else { lines.removeAll(keepingCapacity: true); return }
            if !FileManager.default.fileExists(atPath: Self.outputURL.path) {
                FileManager.default.createFile(atPath: Self.outputURL.path, contents: nil)
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: Self.outputURL.path)
            let currentSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard currentSize + UInt64(data.count) <= maximumLogBytes else {
                loggingCapped = true
                lines.removeAll(keepingCapacity: true)
                NSLog("Codex Monitor D1 probe log reached its QA size limit")
                return
            }
            let handle = try FileHandle(forWritingTo: Self.outputURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
            NSLog("Codex Monitor D1 drag probe log: %@", Self.outputURL.path)
        } catch {
            NSLog("Codex Monitor D1 drag probe log write failed: %@", String(describing: error))
        }
        lines.removeAll(keepingCapacity: true)
    }
}
#endif
