import AppKit
import Foundation

enum MonitorDiagnosticCategory: String, CaseIterable {
    case state, presentation, localization, settings, popover, usageChart, orbHost
}

/// Diagnostics are evidence, not an unbounded event journal. These caps are
/// intentionally independent of ZIP compression: retained in-memory data is
/// bounded even if archive creation fails or produces no compression.
struct DiagnosticRetentionPolicy: Sendable, Equatable {
    let perCategoryRecordLimit: Int
    let perCategoryByteLimit: Int
    let totalByteLimit: Int

    init(perCategoryRecordLimit: Int = 500, perCategoryByteLimit: Int = 512 * 1024, totalByteLimit: Int = 2 * 1024 * 1024) {
        self.perCategoryRecordLimit = max(1, perCategoryRecordLimit)
        self.perCategoryByteLimit = max(1, perCategoryByteLimit)
        self.totalByteLimit = max(1, totalByteLimit)
    }
}

private struct RetainedDiagnosticRecord: Sendable {
    var fields: [String: String]
    let signature: String?
    let firstSeen: Date
    var lastSeen: Date
    var count: UInt64
    let estimatedBytes: Int

    func exportedLine() -> String? {
        var payload = fields
        payload["firstRetainedAt"] = ISO8601DateFormatter().string(from: firstSeen)
        payload["lastRetainedAt"] = ISO8601DateFormatter().string(from: lastSeen)
        if count > 1 { payload["aggregateCount"] = String(count) }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct DiagnosticBucket: Sendable {
    var records: [RetainedDiagnosticRecord] = []
    var bytes = 0
    var droppedRecords: UInt64 = 0
}

struct DiagnosticRetentionStatistics: Sendable, Equatable {
    let retainedRecords: Int
    let retainedBytes: Int
    let droppedRecords: UInt64
    let aggregatedEvents: UInt64
    let retainedRecordsByCategory: [String: Int]
    let retainedEventNames: Set<String>
}

/// Sanitized, structured QA evidence. It deliberately records only stable
/// state names, capability/presentation facts, and one-way identifiers; it
/// never accepts transcript, account, credential, or raw source payload text.
actor MonitorDiagnostics {
    static let shared = MonitorDiagnostics()

    private var sequence: UInt64 = 0
    private let retentionPolicy: DiagnosticRetentionPolicy
    private var buckets: [MonitorDiagnosticCategory: DiagnosticBucket] = [:]
    private var retainedBytes = 0
    private var latestOrbLayerTree = "orb host not yet created\n"

    static var buildRevision: String {
        Bundle.main.object(forInfoDictionaryKey: "UIBuildRevision") as? String ?? "development"
    }

    init(retentionPolicy: DiagnosticRetentionPolicy = .init()) {
        self.retentionPolicy = retentionPolicy
    }

    func record(_ category: MonitorDiagnosticCategory, _ fields: [String: String]) {
        sequence &+= 1
        var payload = Self.sanitizedFields(fields)
        payload["sequence"] = String(sequence)
        payload["monotonicNanoseconds"] = String(DispatchTime.now().uptimeNanoseconds)
        payload["buildCommit"] = Self.buildRevision
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        let now = Date()
        let signature = Self.aggregateSignature(category: category, fields: payload)
        var bucket = buckets[category, default: DiagnosticBucket()]
        if let signature, let index = bucket.records.indices.last, bucket.records[index].signature == signature {
            bucket.records[index].count &+= 1
            bucket.records[index].lastSeen = now
            buckets[category] = bucket
            return
        }
        let record = RetainedDiagnosticRecord(fields: payload, signature: signature, firstSeen: now, lastSeen: now, count: 1, estimatedBytes: data.count)
        bucket.records.append(record)
        bucket.bytes += record.estimatedBytes
        retainedBytes += record.estimatedBytes
        buckets[category] = bucket
        enforceRetention()
    }

    private static func aggregateSignature(category: MonitorDiagnosticCategory, fields: [String: String]) -> String? {
        guard let event = fields["event"] else { return nil }
        let isNoOpSnapshot = event == "runtimeSnapshotApply" && fields["accepted"] == "false" && fields["changedFields"] == "none"
        let isTransientDB = event == "STATE_DB_TRANSIENT_WAL_MISSING"
        guard isNoOpSnapshot || isTransientDB else { return nil }
        return "\(category.rawValue)|\(event)|\(fields["rejectionReason"] ?? fields["decisionReason"] ?? fields["error"] ?? "none")"
    }

    private func enforceRetention() {
        for category in MonitorDiagnosticCategory.allCases {
            while var bucket = buckets[category],
                  (bucket.records.count > retentionPolicy.perCategoryRecordLimit || bucket.bytes > retentionPolicy.perCategoryByteLimit),
                  !bucket.records.isEmpty {
                let removed = bucket.records.removeFirst()
                bucket.bytes -= removed.estimatedBytes
                bucket.droppedRecords &+= removed.count
                retainedBytes -= removed.estimatedBytes
                buckets[category] = bucket
            }
        }
        while retainedBytes > retentionPolicy.totalByteLimit {
            guard let category = MonitorDiagnosticCategory.allCases
                .filter({ !(buckets[$0]?.records.isEmpty ?? true) })
                .min(by: { (buckets[$0]?.records.first?.firstSeen ?? .distantFuture) < (buckets[$1]?.records.first?.firstSeen ?? .distantFuture) }),
                var bucket = buckets[category], !bucket.records.isEmpty else { break }
            let removed = bucket.records.removeFirst()
            bucket.bytes -= removed.estimatedBytes
            bucket.droppedRecords &+= removed.count
            retainedBytes -= removed.estimatedBytes
            buckets[category] = bucket
        }
    }

    private static func sanitizedFields(_ fields: [String: String]) -> [String: String] {
        fields.reduce(into: [:]) { sanitized, field in
            let key = field.key.lowercased()
            let isCredential = ["api", "credential", "authorization", "cookie", "secret", "bearer"].contains { key.contains($0) }
            let isPersonalContent = ["transcript", "prompt", "conversation", "email", "raw", "path"].contains { key.contains($0) }
            // Token counts are permitted QA evidence; session/access tokens are not.
            let isRawToken = key.contains("token") && !["tokens", "totaltokens", "inputtokens", "outputtokens", "cachedinputtokens", "reasoningoutputtokens"].contains(key)
            guard !isCredential, !isPersonalContent, !isRawToken, field.value.utf8.count <= 256 else { return }
            sanitized[field.key] = field.value
        }
    }

    func recordOrbLayerTree(_ value: String) {
        // The hierarchy is supporting evidence, never an unbounded dump.
        latestOrbLayerTree = String(decoding: value.utf8.prefix(64 * 1024), as: UTF8.self)
        record(.orbHost, ["event": "hierarchyCaptured", "bytes": String(latestOrbLayerTree.utf8.count)])
    }

    func retentionStatistics() -> DiagnosticRetentionStatistics {
        let all = buckets.values
        return DiagnosticRetentionStatistics(
            retainedRecords: all.reduce(0) { $0 + $1.records.count },
            retainedBytes: retainedBytes,
            droppedRecords: all.reduce(0) { $0 + $1.droppedRecords },
            aggregatedEvents: all.flatMap(\.records).reduce(0) { $0 + $1.count },
            retainedRecordsByCategory: Dictionary(uniqueKeysWithValues: MonitorDiagnosticCategory.allCases.map { category in
                (category.rawValue, buckets[category]?.records.count ?? 0)
            }),
            retainedEventNames: Set(all.flatMap(\.records).compactMap { $0.fields["event"] })
        )
    }

    func recordRepeated(_ category: MonitorDiagnosticCategory, fields: [String: String], count: Int) {
        for _ in 0..<max(0, count) { record(category, fields) }
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
            let bucket = buckets[category] ?? DiagnosticBucket()
            let retained = bucket.records.compactMap { $0.exportedLine() }
            let first = bucket.records.first.map { ISO8601DateFormatter().string(from: $0.firstSeen) } ?? "none"
            let last = bucket.records.last.map { ISO8601DateFormatter().string(from: $0.lastSeen) } ?? "none"
            let retention = "{\"event\":\"diagnosticRetention\",\"retainedRecords\":\(retained.count),\"droppedRecords\":\(bucket.droppedRecords),\"firstRetainedAt\":\"\(first)\",\"lastRetainedAt\":\"\(last)\"}"
            let content = (retained + [retention]).joined(separator: "\n") + "\n"
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
    case downloadsUnavailable, archiveCreationFailed
    case writeFailed
    case noAvailableFilename

    static func sanitizedCode(for error: Error) -> Self {
        (error as? Self) ?? .writeFailed
    }
}

/// Produces a standard DEFLATE ZIP through the fixed macOS system executable.
/// Entry names and the temporary directory are generated by this module; no
/// user string is ever interpreted as a shell command or executable path.
enum DiagnosticsZIPArchive {
    static func make(entries: [(name: String, data: Data)], date: Date) throws -> Data {
        let totalInputBytes = entries.reduce(0) { $0 + $1.data.count }
        guard totalInputBytes <= 3 * 1024 * 1024 else { throw DiagnosticsExportFailure.archiveCreationFailed }
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("CodexMonitorDiagnostics-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        for entry in entries {
            guard URL(fileURLWithPath: entry.name).lastPathComponent == entry.name,
                  !entry.name.contains("..") else { throw DiagnosticsExportFailure.archiveCreationFailed }
            try entry.data.write(to: root.appendingPathComponent(entry.name), options: .atomic)
        }
        let archiveURL = root.appendingPathComponent("diagnostics.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", archiveURL.path, "."]
        process.currentDirectoryURL = root
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw DiagnosticsExportFailure.archiveCreationFailed }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let archive = try? Data(contentsOf: archiveURL), !archive.isEmpty else {
            throw DiagnosticsExportFailure.archiveCreationFailed
        }
        return archive
        /*
         The legacy stored-entry writer is retained below only as a small
         format reference for CRC tests. It is deliberately unreachable: ZIP
         method 0 cannot meet the archive size requirement.
         */
#if false
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
#endif
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
