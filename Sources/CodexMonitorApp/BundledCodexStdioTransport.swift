import AppKit
import Foundation
import CodexMonitorContracts

/// Locates only the app-server executable embedded in the installed Codex
/// Desktop application.  Neither PATH nor a caller-controlled executable is
/// accepted as an Account authority.
struct TrustedCodexBundledExecutableResolver: Sendable {
    static let bundleIdentifier = "com.openai.codex"

    private let applicationURL: @Sendable () -> URL?

    init(applicationURL: @escaping @Sendable () -> URL? = {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }) {
        self.applicationURL = applicationURL
    }

    func resolve() throws -> URL {
        guard let suppliedURL = applicationURL() else { throw TrustedCodexStdioError.applicationNotFound }
        let applicationURL = suppliedURL.resolvingSymlinksInPath().standardizedFileURL
        guard applicationURL.pathExtension == "app",
              let bundle = Bundle(url: applicationURL),
              bundle.bundleIdentifier == Self.bundleIdentifier,
              let resources = bundle.resourceURL else {
            throw TrustedCodexStdioError.untrustedBundle
        }

        let executable = resources.appendingPathComponent("codex", isDirectory: false)
            .resolvingSymlinksInPath().standardizedFileURL
        let applicationPrefix = applicationURL.path.hasSuffix("/") ? applicationURL.path : applicationURL.path + "/"
        guard executable.path.hasPrefix(applicationPrefix) else { throw TrustedCodexStdioError.bundleEscape }
        let values = try executable.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey])
        guard values.isRegularFile == true, values.isExecutable == true else {
            throw TrustedCodexStdioError.executableRejected
        }
        return executable
    }
}

enum TrustedCodexStdioError: Error, Sendable, Equatable {
    case applicationNotFound
    case untrustedBundle
    case bundleEscape
    case executableRejected
    case processLaunchFailed
}

/// JSON-RPC's existing lifecycle owns initialization and request routing; this
/// channel only turns the trusted app-server's newline-delimited stdio into
/// the required JSONRPCByteChannel frames.
actor BundledCodexStdioChannel: JSONRPCByteChannel {
    private let executableURL: URL
    private var process: Process?
    private var input: FileHandle?
    private var reader: StdioLineReader?
    private var errorDrainer: StdioDrainer?

    init(executableURL: URL) { self.executableURL = executableURL }

    func open() async throws {
        guard process == nil else { return }
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        let reader = StdioLineReader(handle: stdout.fileHandleForReading)
        let drainer = StdioDrainer(handle: stderr.fileHandleForReading)
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { _ in
            reader.finish()
            drainer.finish()
        }
        do {
            try process.run()
        } catch {
            reader.finish()
            drainer.finish()
            throw TrustedCodexStdioError.processLaunchFailed
        }
        self.process = process
        input = stdin.fileHandleForWriting
        self.reader = reader
        errorDrainer = drainer
    }

    func send(_ frame: JSONRPCFrame) async throws {
        guard case .text = frame.kind,
              frame.isComplete,
              let data = frame.data,
              let input else { throw JSONRPCTransportError.transportFailure(.socketSendFailed) }
        do {
            var line = data
            line.append(0x0A)
            try input.write(contentsOf: line)
        } catch {
            throw JSONRPCTransportError.transportFailure(.socketSendFailed)
        }
    }

    func receive() async throws -> JSONRPCFrame? {
        guard let reader else { throw JSONRPCTransportError.connectionClosed }
        guard let line = await reader.nextLine() else { return nil }
        return JSONRPCFrame(kind: .text, data: line)
    }

    func close() async {
        let ownedProcess = process
        process = nil
        input?.closeFile()
        input = nil
        reader?.finish()
        reader = nil
        errorDrainer?.finish()
        errorDrainer = nil
        if ownedProcess?.isRunning == true { ownedProcess?.terminate() }
    }
}

private final class StdioLineReader: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    private var buffered = Data()
    private var lines = [Data]()
    private var finished = false
    private var waiter: CheckedContinuation<Data?, Never>?

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] source in self?.read(source.availableData) }
    }

    func nextLine() async -> Data? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if !lines.isEmpty { continuation.resume(returning: lines.removeFirst()) }
            else if finished { continuation.resume(returning: nil) }
            else { waiter = continuation }
            lock.unlock()
        }
    }

    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        handle.readabilityHandler = nil
        let waiting = waiter
        waiter = nil
        lock.unlock()
        handle.closeFile()
        waiting?.resume(returning: nil)
    }

    private func read(_ data: Data) {
        guard !data.isEmpty else { finish(); return }
        lock.lock()
        guard !finished else { lock.unlock(); return }
        buffered.append(data)
        while let newline = buffered.firstIndex(of: 0x0A) {
            var line = buffered.prefix(upTo: newline)
            if line.last == 0x0D { line.removeLast() }
            lines.append(Data(line))
            buffered.removeSubrange(...newline)
        }
        let waiting = waiter
        let line = waiting == nil || lines.isEmpty ? nil : lines.removeFirst()
        if line != nil { waiter = nil }
        lock.unlock()
        if let waiting { waiting.resume(returning: line) }
    }
}

private final class StdioDrainer: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var finished = false

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] source in self?.drain(source.availableData) }
    }

    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        handle.readabilityHandler = nil
        lock.unlock()
        handle.closeFile()
    }

    private func drain(_ data: Data) {
        if data.isEmpty { finish() }
    }
}
