import AppKit
import Foundation
import OSLog

enum MonitorDiagnosticCategory: String, CaseIterable {
    case state, presentation, localization, settings, popover, usageChart, orbHost
}

/// Sanitized, structured QA evidence. It deliberately records only stable
/// state names, capability/presentation facts, and one-way identifiers; it
/// never accepts transcript, account, credential, or raw source payload text.
actor MonitorDiagnostics {
    static let shared = MonitorDiagnostics()

    private var sequence: UInt64 = 0
    private var lines: [MonitorDiagnosticCategory: [String]] = [:]
    private var latestOrbLayerTree = "orb host not yet created\n"

    static var buildRevision: String {
        Bundle.main.object(forInfoDictionaryKey: "UIBuildRevision") as? String ?? "development"
    }

    func record(_ category: MonitorDiagnosticCategory, _ fields: [String: String]) {
        sequence &+= 1
        var payload = fields
        payload["sequence"] = String(sequence)
        payload["monotonicNanoseconds"] = String(DispatchTime.now().uptimeNanoseconds)
        payload["buildCommit"] = Self.buildRevision
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        lines[category, default: []].append(line)
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "CodexMonitor", category: category.rawValue)
            .notice("\(line, privacy: .public)")
    }

    func recordOrbLayerTree(_ value: String) {
        latestOrbLayerTree = value
        record(.orbHost, ["event": "hierarchyCaptured", "bytes": String(value.utf8.count)])
    }

    func export(preferences: DiagnosticPreferenceSnapshot) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("CodexMonitor-Diagnostics-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for category in MonitorDiagnosticCategory.allCases {
            let name: String = switch category {
            case .state: "runtime-state.jsonl"
            case .presentation: "presentation.jsonl"
            case .localization: "localization.jsonl"
            case .settings: "settings.jsonl"
            case .popover: "popover.jsonl"
            case .usageChart: "usage-chart.jsonl"
            case .orbHost: "orb-host.jsonl"
            }
            let content = (lines[category] ?? []).joined(separator: "\n") + "\n"
            try content.data(using: .utf8)?.write(to: root.appendingPathComponent(name), options: .atomic)
        }
        try latestOrbLayerTree.data(using: .utf8)?.write(to: root.appendingPathComponent("orb-layer-tree.txt"), options: .atomic)
        let preferencePayload: [String: Any] = [
            "showOrb": preferences.showOrb,
            "orbSize": preferences.orbSize,
            "alwaysOnTop": preferences.alwaysOnTop,
            "lockPosition": preferences.lockPosition,
            "pauseMonitoring": preferences.pauseMonitoring,
            "hideAccountInfo": preferences.hideAccountInfo,
            "interfaceLanguage": preferences.interfaceLanguage
        ]
        let preferenceData = try JSONSerialization.data(withJSONObject: preferencePayload, options: [.prettyPrinted, .sortedKeys])
        try preferenceData.write(to: root.appendingPathComponent("preferences-sanitized.json"), options: .atomic)
        let build = "buildCommit=\(Self.buildRevision)\nexportedAt=\(ISO8601DateFormatter().string(from: Date()))\n"
        try build.data(using: .utf8)?.write(to: root.appendingPathComponent("build.txt"), options: .atomic)

        let destination = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CodexMonitor-Diagnostics.zip")
        try? fileManager.removeItem(at: destination)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-r", destination.path, "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return destination
    }
}

struct DiagnosticPreferenceSnapshot: Sendable {
    let showOrb: Bool
    let orbSize: Int
    let alwaysOnTop: Bool
    let lockPosition: Bool
    let pauseMonitoring: Bool
    let hideAccountInfo: Bool
    let interfaceLanguage: String

    @MainActor
    init(_ preferences: MonitorPreferences) {
        showOrb = preferences.showOrb
        orbSize = Int(preferences.orbSize)
        alwaysOnTop = preferences.alwaysOnTop
        lockPosition = preferences.lockPosition
        pauseMonitoring = preferences.pauseMonitoring
        hideAccountInfo = preferences.hideAccountInfo
        interfaceLanguage = preferences.interfaceLanguage.rawValue
    }
}

enum DiagnosticEvent {
    static func record(_ category: MonitorDiagnosticCategory, _ fields: [String: String]) {
        Task { await MonitorDiagnostics.shared.record(category, fields) }
    }

    static func presentation(_ presentation: VisualStatePresentation, event: String) {
        let dots = presentation.dots
        record(.presentation, [
            "event": event,
            "statusDot1": dot(dots, 0), "statusDot2": dot(dots, 1), "statusDot3": dot(dots, 2),
            "orbColor": String(describing: presentation.orbTone),
            "orbBreathing": String(presentation.breathes),
            "stateTextKey": presentation.stateTextKey
        ])
    }

    private static func dot(_ dots: [VisualStateDot], _ index: Int) -> String {
        guard dots.indices.contains(index) else { return "missing" }
        return "color=\(dots[index].tone),active=\(dots[index].tone != .inactive),breathing=\(dots[index].breathes)"
    }
}

enum OrbHostDiagnostics {
    @MainActor
    static func capture(panel: NSPanel, contentView: NSView) {
        let panelRecord = "NSPanel frame=\(panel.frame.integral) opaque=\(panel.isOpaque) background=\(panel.backgroundColor.description) shadow=\(panel.hasShadow)\n"
        let tree = panelRecord + describe(view: contentView, depth: 0)
        Task { await MonitorDiagnostics.shared.recordOrbLayerTree(tree) }
    }

    @MainActor
    private static func describe(view: NSView, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let layer = view.layer
        let line = "\(indent)\(String(describing: type(of: view))) frame=\(view.frame.integral) opaque=\(view.isOpaque) wantsLayer=\(view.wantsLayer) layerBackground=\(layer?.backgroundColor.map { String(describing: $0) } ?? "nil") cornerRadius=\(layer?.cornerRadius ?? 0) masks=\(layer?.masksToBounds ?? false) shadowOpacity=\(layer?.shadowOpacity ?? 0) sublayers=\(layer?.sublayers?.count ?? 0)\n"
        return line + view.subviews.map { describe(view: $0, depth: depth + 1) }.joined()
    }
}

enum OrbTransparencyProbe {
    /// A compositor contract for the rectangular host corners. These are the
    /// exact properties that must be clear regardless of the desktop behind
    /// the panel (white, black, orange, or split-color).
    @MainActor
    static func passes(for panel: NSPanel?, host: NSView?) -> Bool {
        guard let panel, let host else { return false }
        return !panel.isOpaque && panel.backgroundColor == .clear && !panel.hasShadow &&
            !host.isOpaque && host.layer?.backgroundColor == NSColor.clear.cgColor &&
            host.layer?.shadowOpacity == 0
    }

    /// Samples the four rectangular host corners from the rendered view. A
    /// transparent sample composites unchanged over every supplied backdrop;
    /// this gives QA a real alpha observation in addition to the AppKit layer
    /// contract above, without sampling the user's desktop.
    @MainActor
    static func renderedBackgroundResults(for host: NSView?) -> [String: String] {
        guard let host,
              host.bounds.width >= 4,
              host.bounds.height >= 4,
              let representation = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return ["white": "unavailable", "black": "unavailable", "orange": "unavailable", "splitColor": "unavailable"]
        }
        host.layoutSubtreeIfNeeded()
        host.cacheDisplay(in: host.bounds, to: representation)
        let inset = max(1, Int(min(host.bounds.width, host.bounds.height) * 0.06))
        let points = [
            (inset, inset),
            (max(inset, Int(host.bounds.width) - inset - 1), inset),
            (inset, max(inset, Int(host.bounds.height) - inset - 1)),
            (max(inset, Int(host.bounds.width) - inset - 1), max(inset, Int(host.bounds.height) - inset - 1))
        ]
        let alphaIsClear = points.allSatisfy { point in
            (representation.colorAt(x: point.0, y: point.1)?.alphaComponent ?? 1) < 0.01
        }
        let result = alphaIsClear ? "pass" : "fail"
        return ["white": result, "black": result, "orange": result, "splitColor": result]
    }
}
