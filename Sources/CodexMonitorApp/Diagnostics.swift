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
        var payload = Self.sanitizedFields(fields)
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

    private static func sanitizedFields(_ fields: [String: String]) -> [String: String] {
        fields.reduce(into: [:]) { sanitized, field in
            let key = field.key.lowercased()
            let isCredential = ["api", "credential", "authorization", "cookie", "secret", "bearer"].contains { key.contains($0) }
            let isPersonalContent = ["transcript", "prompt", "conversation", "email"].contains { key.contains($0) }
            // Token counts are permitted QA evidence; session/access tokens are not.
            let isRawToken = key.contains("token") && !["tokens", "totaltokens", "inputtokens", "outputtokens", "cachedinputtokens", "reasoningoutputtokens"].contains(key)
            guard !isCredential, !isPersonalContent, !isRawToken, field.value.utf8.count <= 256 else { return }
            sanitized[field.key] = field.value
        }
    }

    func recordOrbLayerTree(_ value: String) {
        latestOrbLayerTree = value
        record(.orbHost, ["event": "hierarchyCaptured", "bytes": String(value.utf8.count)])
    }

    /// Produces a portable ZIP without launching a subprocess. The archive uses
    /// ZIP's standard "stored" entries: diagnostics are small, and keeping the
    /// implementation in-process avoids granting an export path arbitrary-shell
    /// capabilities.
    func export(
        preferences: DiagnosticPreferenceSnapshot,
        destinationDirectory: URL? = nil,
        now: Date = Date()
    ) throws -> URL {
        let fileManager = FileManager.default
        var entries: [(name: String, data: Data)] = []
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
            entries.append((name, Data(content.utf8)))
        }
        entries.append(("orb-layer-tree.txt", Data(latestOrbLayerTree.utf8)))
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
        entries.append(("preferences-sanitized.json", preferenceData))
        let build = "buildCommit=\(Self.buildRevision)\nexportedAt=\(ISO8601DateFormatter().string(from: Date()))\n"
        entries.append(("build.txt", Data(build.utf8)))

        let outputDirectory = destinationDirectory ?? fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let outputDirectory else { throw DiagnosticsExportFailure.downloadsUnavailable }
        let archive = try DiagnosticsZIPArchive.make(entries: entries, date: now)
        return try writeArchiveWithoutOverwriting(archive, to: outputDirectory, date: now, fileManager: fileManager)
    }

    private func writeArchiveWithoutOverwriting(_ archive: Data, to directory: URL, date: Date, fileManager: FileManager) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = "CodexMonitor-Diagnostics-\(formatter.string(from: date))"

        for suffix in 0...999 {
            let name = suffix == 0 ? stem : "\(stem)-\(suffix)"
            let destination = directory.appendingPathComponent(name).appendingPathExtension("zip")
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            do {
                try archive.write(to: destination, options: .withoutOverwriting)
                return destination
            } catch {
                if fileManager.fileExists(atPath: destination.path) { continue }
                throw DiagnosticsExportFailure.writeFailed
            }
        }
        throw DiagnosticsExportFailure.noAvailableFilename
    }
}

enum DiagnosticsExportFailure: String, Error, Sendable {
    case downloadsUnavailable
    case writeFailed
    case noAvailableFilename

    static func sanitizedCode(for error: Error) -> Self {
        (error as? Self) ?? .writeFailed
    }
}

/// Minimal standards-compliant ZIP writer for the fixed, sanitized diagnostics
/// payload. It writes uncompressed entries, which keeps the archive readable by
/// Finder and Archive Utility without an external archive tool or framework.
private enum DiagnosticsZIPArchive {
    static func make(entries: [(name: String, data: Data)], date: Date) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        let dosTime = Self.dosTime(for: date)
        let dosDate = Self.dosDate(for: date)

        for entry in entries {
            let name = Data(entry.name.utf8)
            guard name.count <= Int(UInt16.max), entry.data.count <= Int(UInt32.max) else {
                throw DiagnosticsExportFailure.writeFailed
            }
            let offset = archive.count
            guard offset <= Int(UInt32.max) else { throw DiagnosticsExportFailure.writeFailed }
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            archive.appendLE(UInt32(0x04034B50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(dosTime)
            archive.appendLE(dosDate)
            archive.appendLE(crc)
            archive.appendLE(size)
            archive.appendLE(size)
            archive.appendLE(UInt16(name.count))
            archive.appendLE(UInt16(0))
            archive.append(name)
            archive.append(entry.data)

            centralDirectory.appendLE(UInt32(0x02014B50))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(dosTime)
            centralDirectory.appendLE(dosDate)
            centralDirectory.appendLE(crc)
            centralDirectory.appendLE(size)
            centralDirectory.appendLE(size)
            centralDirectory.appendLE(UInt16(name.count))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt32(0))
            centralDirectory.appendLE(UInt32(offset))
            centralDirectory.append(name)
        }

        guard entries.count <= Int(UInt16.max), centralDirectory.count <= Int(UInt32.max), archive.count <= Int(UInt32.max) else {
            throw DiagnosticsExportFailure.writeFailed
        }
        let centralDirectoryOffset = archive.count
        archive.append(centralDirectory)
        archive.appendLE(UInt32(0x06054B50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt32(centralDirectory.count))
        archive.appendLE(UInt32(centralDirectoryOffset))
        archive.appendLE(UInt16(0))
        return archive
    }

    private static func dosTime(for date: Date) -> UInt16 {
        let values = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute, .second], from: date)
        return UInt16((values.hour ?? 0) << 11 | (values.minute ?? 0) << 5 | (values.second ?? 0) / 2)
    }

    private static func dosDate(for date: Date) -> UInt16 {
        let values = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: date)
        return UInt16((max(1980, values.year ?? 1980) - 1980) << 9 | (values.month ?? 1) << 5 | (values.day ?? 1))
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xEDB8_8320 }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
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
