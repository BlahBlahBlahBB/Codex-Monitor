import CryptoKit
import Darwin
import Foundation
import Security

/// App-owned storage shared by the main app and the independently packaged
/// observer helper.  It is intentionally outside Codex's configuration home.
public struct AppOwnedApprovalObserverPaths: Sendable, Equatable {
    public let rootURL: URL
    public let versionsURL: URL
    public let journalURL: URL
    public let sequenceURL: URL
    public let identityKeyURL: URL
    public let receiptURL: URL
    public let diagnosticURL: URL
    public let codexHomeURL: URL

    public init(rootURL: URL, codexHomeURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)) {
        let normalizedRoot = rootURL.standardizedFileURL
        self.rootURL = normalizedRoot
        versionsURL = normalizedRoot.appendingPathComponent("versions", isDirectory: true)
        let journalDirectory = normalizedRoot.appendingPathComponent("journal", isDirectory: true)
        journalURL = journalDirectory.appendingPathComponent("events.ndjson")
        sequenceURL = journalDirectory.appendingPathComponent("sequence")
        identityKeyURL = normalizedRoot.appendingPathComponent("identity.key")
        receiptURL = normalizedRoot.appendingPathComponent("installation.json")
        diagnosticURL = normalizedRoot.appendingPathComponent("diagnostics", isDirectory: true).appendingPathComponent("observer.ndjson")
        self.codexHomeURL = codexHomeURL.standardizedFileURL
    }

    public static var `default`: Self {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return Self(rootURL: applicationSupport.appendingPathComponent("Codex Monitor", isDirectory: true).appendingPathComponent("ApprovalObserver", isDirectory: true))
    }
}

/// A deliberately closed, non-sensitive operational signal from the helper.
/// It never records raw IDs, prompts, command text, Hook input, or output.
private struct ApprovalObserverDiagnostic: Encodable {
    let schema = 1
    let observedAtMilliseconds: Int64
    let release: String
    let stage: String
    let eventKind: String?
}

/// The independently signed helper's sole behavior.  It always fails open:
/// it writes no stdout protocol/control response and returns normally on all
/// malformed or unavailable conditions.
public enum ApprovalObserverHookRunner {
    public static let maximumInputBytes = 1 * 1_024 * 1_024
    private static let sourceRawID = "codex-desktop-local"

    public static func run(paths: AppOwnedApprovalObserverPaths = .default) {
        guard verifyOwnCodeSignature() else {
            recordDiagnostic(paths: paths, stage: "signature_validation_failed", kind: nil)
            return
        }
        recordDiagnostic(paths: paths, stage: "process_started", kind: nil)
        do {
            guard let input = try FileHandle.standardInput.read(upToCount: maximumInputBytes + 1) else {
                recordDiagnostic(paths: paths, stage: "input_decode_failed", kind: nil)
                return
            }
            guard input.count <= maximumInputBytes else {
                recordDiagnostic(paths: paths, stage: "stdin_oversized", kind: nil)
                return
            }
            _ = run(input: input, paths: paths, keyMaterial: nil)
        } catch {
            recordDiagnostic(paths: paths, stage: "input_decode_failed", kind: nil)
        }
    }

    @discardableResult
    public static func run(input: Data, paths: AppOwnedApprovalObserverPaths, keyMaterial: Data?) -> Bool {
        guard input.count <= maximumInputBytes else {
            recordDiagnostic(paths: paths, stage: "stdin_oversized", kind: nil)
            return false
        }
        guard let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let rawEvent = object["hook_event_name"] as? String,
              let kind = kind(for: rawEvent) else {
            recordDiagnostic(paths: paths, stage: "input_decode_or_unsupported_event", kind: nil)
            return false
        }
        guard let sessionID = object["session_id"] as? String,
              let turnID = object["turn_id"] as? String else {
            recordDiagnostic(paths: paths, stage: "input_missing_identity", kind: kind)
            return false
        }
        let material: Data
        if let keyMaterial {
            material = keyMaterial
        } else {
            guard let loaded = try? Data(contentsOf: paths.identityKeyURL) else {
                recordDiagnostic(paths: paths, stage: "secret_unavailable", kind: kind)
                return false
            }
            material = loaded
        }
        guard let deriver = KeyedHookApprovalIdentityDeriver(keyMaterial: material),
              let owner = deriver.owner(sourceRawID: sourceRawID, sessionRawID: sessionID, turnRawID: turnID) else {
            recordDiagnostic(paths: paths, stage: "identity_derivation_failed", kind: kind)
            return false
        }
        let reviewer = kind == .permissionRequest
            ? transcriptReviewer(path: object["transcript_path"] as? String, turnID: turnID)
            : nil
        let appended = append(kind: kind, owner: owner, reviewer: reviewer, observedAt: Date(), paths: paths)
        recordDiagnostic(paths: paths, stage: appended ? "event_appended" : "journal_append_failed", kind: kind)
        return appended
    }

    private static func verifyOwnCodeSignature() -> Bool {
        let executablePath = CommandLine.arguments.first ?? ""
        guard !executablePath.isEmpty else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: executablePath) as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess
    }

    private static func kind(for rawEvent: String) -> HookApprovalJournalRecordKind? {
        switch rawEvent.lowercased() {
        case "permissionrequest": .permissionRequest
        case "posttooluse": .postToolUse
        case "stop": .stop
        default: nil
        }
    }

    /// Scan backward from one EOF snapshot. Memory is bounded per record, not
    /// by distance to the context. No transcript content escapes this function.
    static let transcriptChunkBytes = 64 * 1_024
    static let maximumTranscriptRecordBytes = 8 * 1_024 * 1_024

    static func transcriptReviewer(path: String?, turnID: String) -> ApprovalReviewer {
        guard let path, path.hasPrefix("/"), !path.utf8.contains(0),
              URL(fileURLWithPath: path).pathExtension.lowercased() == "jsonl",
              !turnID.isEmpty else { return .unknown }
        // O_NONBLOCK prevents a FIFO disguised as .jsonl from blocking open.
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return .unknown }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG, metadata.st_size > 0 else { return .unknown }
        var offset = metadata.st_size
        var bytes = [UInt8](repeating: 0, count: transcriptChunkBytes)
        // Store bytes in reverse order to avoid repeatedly prepending/copying
        // a record spanning many chunks. Reverse once when decoding it.
        var record = [UInt8]()
        func classifyRecord() -> ApprovalReviewer? {
            guard let object = try? JSONSerialization.jsonObject(with: Data(record.reversed())) as? [String: Any] else {
                return .unknown
            }
            guard object["type"] as? String == "turn_context",
                  let payload = object["payload"] as? [String: Any],
                  payload["turn_id"] as? String == turnID else { return nil }
            return (payload["approvals_reviewer"] as? String).flatMap(ApprovalReviewer.init(rawValue:)) ?? .unknown
        }
        var atEOF = true
        while offset > 0 {
            let count = Int(min(offset, off_t(transcriptChunkBytes)))
            offset -= off_t(count)
            let received = bytes.withUnsafeMutableBytes { buffer in
                pread(descriptor, buffer.baseAddress!, count, offset)
            }
            // A short read (including truncation) cannot establish a reviewer.
            guard received == count else { return .unknown }
            for index in (0..<count).reversed() {
                let byte = bytes[index]
                if atEOF {
                    guard byte == 0x0A else { return .unknown }
                    atEOF = false
                } else if byte == 0x0A {
                    if let reviewer = classifyRecord() { return reviewer }
                    record.removeAll(keepingCapacity: true)
                } else {
                    guard record.count < maximumTranscriptRecordBytes else { return .unknown }
                    record.append(byte)
                }
            }
        }
        // The first record starts at byte zero, with no preceding newline.
        if let reviewer = classifyRecord() { return reviewer }
        return .unknown
    }

    private static func append(kind: HookApprovalJournalRecordKind, owner: HookApprovalTurnOwner, reviewer: ApprovalReviewer?, observedAt: Date, paths: AppOwnedApprovalObserverPaths) -> Bool {
        let fileManager = FileManager.default
        do {
            let journalDirectory = paths.journalURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: journalDirectory.path)
            let descriptor = open(paths.sequenceURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { return false }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX) == 0 else { return false }
            defer { _ = flock(descriptor, LOCK_UN) }
            let current = UInt64(String(data: readAll(from: descriptor), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
            guard current < UInt64.max else { return false }
            let next = current + 1
            guard let eventID = HookApprovalJournalEventID(next),
                  let record = HookApprovalJournalRecord(journalEventID: eventID, kind: kind, sourceID: owner.sourceID, sessionID: owner.sessionID, turnID: owner.turnID, observedAtMilliseconds: Int64(observedAt.timeIntervalSince1970 * 1_000), reviewer: reviewer),
                  let encoded = try? JSONEncoder().encode(record),
                  lseek(descriptor, 0, SEEK_SET) >= 0,
                  ftruncate(descriptor, 0) == 0,
                  writeAll(to: descriptor, data: Data(String(next).utf8)) else { return false }
            if !fileManager.fileExists(atPath: paths.journalURL.path) {
                guard fileManager.createFile(atPath: paths.journalURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return false }
            }
            let handle = try FileHandle(forWritingTo: paths.journalURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: encoded + Data([0x0A]))
            try handle.close()
            return true
        } catch { return false }
    }

    private static func recordDiagnostic(paths: AppOwnedApprovalObserverPaths, stage: String, kind: HookApprovalJournalRecordKind?) {
        do {
            let directory = paths.diagnosticURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let executableURL = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            let parent = executableURL.deletingLastPathComponent().lastPathComponent
            let release = parent.hasPrefix("observer-") ? parent : executableURL.lastPathComponent
            let entry = ApprovalObserverDiagnostic(observedAtMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000), release: release, stage: stage, eventKind: kind?.rawValue)
            let data = try JSONEncoder().encode(entry) + Data([0x0A])
            if !FileManager.default.fileExists(atPath: paths.diagnosticURL.path) {
                _ = FileManager.default.createFile(atPath: paths.diagnosticURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: paths.diagnosticURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {}
    }

    private static func readAll(from descriptor: Int32) -> Data {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else { return Data() }
        var result = Data(); var buffer = [UInt8](repeating: 0, count: 256)
        while true { let count = read(descriptor, &buffer, buffer.count); guard count > 0 else { break }; result.append(contentsOf: buffer.prefix(count)) }
        return result
    }

    private static func writeAll(to descriptor: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < rawBuffer.count { let count = write(descriptor, baseAddress.advanced(by: offset), rawBuffer.count - offset); guard count > 0 else { return false }; offset += count }
            return true
        }
    }
}
