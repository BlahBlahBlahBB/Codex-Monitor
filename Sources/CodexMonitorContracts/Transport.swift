import Foundation
import Network
import Darwin

/// Values exist only while a single wire message is decoded and routed. They
/// never cross the transport boundary as diagnostics or persisted data.
public indirect enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var objectValue: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    public var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    public var integerValue: Int? {
        guard case .number(let value) = self, value.isFinite, value.rounded() == value,
              value >= Double(Int.min), value <= Double(Int.max) else { return nil }
        return Int(value)
    }
}

/// Official app-server wire DTO: intentionally headerless. `jsonrpc` is not
/// emitted and is not required when decoding received app-server messages.
/// Exact pinned 0.147.0 `RequestId`: a JSON integer or string.  This is not
/// collapsed to `Int`, because app-server may send a valid string id.
public enum RequestID: Codable, Sendable, Equatable, Hashable {
    case integer(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let integer = try? container.decode(Int.self) { self = .integer(integer) }
        else { self = .string(try container.decode(String.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self { case .integer(let value): try container.encode(value); case .string(let value): try container.encode(value) }
    }
}

public struct JSONRPCRequest: Codable, Sendable, Equatable {
    public let id: RequestID
    public let method: String
    public let params: JSONValue?
    public init(id: RequestID, method: String, params: JSONValue?) { self.id = id; self.method = method; self.params = params }
}

public struct JSONRPCNotification: Codable, Sendable, Equatable {
    public let method: String
    public let params: JSONValue?
    public init(method: String, params: JSONValue?) { self.method = method; self.params = params }
}

public struct JSONRPCError: Codable, Sendable, Equatable {
    public let code: Int
    /// This is deliberately never surfaced outside request-local failure.
    public let message: String
    public let data: JSONValue?
    public init(code: Int, message: String, data: JSONValue? = nil) { self.code = code; self.message = message; self.data = data }
}

public struct JSONRPCResponse: Codable, Sendable, Equatable {
    public let id: RequestID
    public let result: JSONValue?
    public let error: JSONRPCError?
    public init(id: RequestID, result: JSONValue? = nil, error: JSONRPCError? = nil) { self.id = id; self.result = result; self.error = error }
}

public enum JSONRPCWireMessage: Sendable, Equatable {
    case request(JSONRPCRequest)
    case notification(JSONRPCNotification)
    case response(JSONRPCResponse)
}

public enum JSONRPCWireRejection: Error, Sendable, Equatable {
    case rootNotObject, invalidMethod, malformedID, serverRequestUnsupported
    case responseMustContainExactlyOneResultOrError, malformedError, malformedShape
}

public enum JSONRPCWireDecoder {
    public static func decode(_ data: Data) throws -> JSONRPCWireMessage {
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = value.objectValue else { throw JSONRPCWireRejection.rootNotObject }
        let method = object["method"]?.stringValue
        let hasID = object.keys.contains("id")
        let hasResult = object.keys.contains("result")
        let hasError = object.keys.contains("error")
        if let method {
            guard !method.isEmpty, !hasResult, !hasError else { throw JSONRPCWireRejection.malformedShape }
            if hasID {
                guard let id = requestID(object["id"]) else { throw JSONRPCWireRejection.malformedID }
                _ = id
                throw JSONRPCWireRejection.serverRequestUnsupported
            }
            return .notification(JSONRPCNotification(method: method, params: object["params"]))
        }
        guard hasID else { throw JSONRPCWireRejection.malformedShape }
        guard let id = requestID(object["id"]) else { throw JSONRPCWireRejection.malformedID }
        guard hasResult != hasError else { throw JSONRPCWireRejection.responseMustContainExactlyOneResultOrError }
        if hasError {
            guard let errorValue = object["error"], let error = try? JSONDecoder().decode(JSONRPCError.self, from: JSONEncoder().encode(errorValue)) else {
                throw JSONRPCWireRejection.malformedError
            }
            return .response(JSONRPCResponse(id: id, error: error))
        }
        return .response(JSONRPCResponse(id: id, result: object["result"]))
    }

    private static func requestID(_ value: JSONValue?) -> RequestID? {
        if let integer = value?.integerValue { return .integer(integer) }
        if let string = value?.stringValue { return .string(string) }
        return nil
    }
}

public struct JSONRPCClientInfo: Codable, Sendable, Equatable {
    public let name: String; public let title: String; public let version: String
    public init(name: String, title: String, version: String) { self.name = name; self.title = title; self.version = version }
    public static let h2TransportBoundary = JSONRPCClientInfo(name: "codex_monitor_h2", title: "Codex Monitor H2", version: "h2")
}

/// Selected required fields from generated `v1/InitializeResponse.json` in the
/// pinned 0.147.0 schema. Values are validated transiently and never retained.
private enum GeneratedInitializeResponse {
    static func isValid(_ value: JSONValue) -> Bool {
        guard let object = value.objectValue else { return false }
        return object["codexHome"]?.stringValue != nil && object["platformFamily"]?.stringValue != nil && object["platformOs"]?.stringValue != nil && object["userAgent"]?.stringValue != nil
    }
}

public struct JSONRPCClientBinding: Sendable, Equatable {
    public let sourceID: SourceID; public let sourceKind: SourceKind; public let adapterID: AdapterID; public let adapterVersion: AdapterVersion; public let runtimeInstanceID: RuntimeInstanceID?; public let accountEpoch: AccountEpoch?; public let lifecycleEpoch: LifecycleEpoch?
    public init(descriptor: AdapterDescriptor, runtimeInstanceID: RuntimeInstanceID? = nil, accountEpoch: AccountEpoch? = nil, lifecycleEpoch: LifecycleEpoch? = nil) throws {
        guard descriptor.sourceKind != .futureObserver,
              (descriptor.sourceKind == .monitorOwnedRuntime) == (runtimeInstanceID != nil),
              (descriptor.sourceKind == .monitorOwnedRuntime) == (lifecycleEpoch != nil) else { throw JSONRPCTransportError.sourceBindingRejected }
        self.sourceID = descriptor.sourceID; self.sourceKind = descriptor.sourceKind; self.adapterID = descriptor.adapterID; self.adapterVersion = descriptor.adapterVersion; self.runtimeInstanceID = runtimeInstanceID; self.accountEpoch = accountEpoch; self.lifecycleEpoch = lifecycleEpoch
    }
}

public struct ConnectionContext: Sendable, Equatable {
    public let binding: JSONRPCClientBinding; public let epoch: ConnectionEpoch
}

public enum JSONRPCTransportError: Error, Sendable, Equatable {
    case endpointRejected(UnixSocketValidationError), malformedMessage(JSONRPCWireRejection)
    case connectionClosed, requestCancelled, requestTimedOut, sourceBindingRejected, lifecycleUnavailable
    case protocolError(code: Int), transportFailure(TransportFailureCode), webSocketClosed(status: Int?, reason: String?)
}

public enum TransportFailureCode: String, Sendable, Equatable { case socketOpenFailed, socketSendFailed, socketReceiveFailed, nonTextFrame, incompleteFrame, socketClosed }

public enum SocketPathProvenance: Sendable, Equatable { case officialDefault, monitorOwnedRuntimeLaunch(RuntimeInstanceID) }

/// An opaque, validated authority to use one Unix socket.  Its initializer and
/// path are intentionally unavailable outside this module; a path string can
/// never self-attest as official or Monitor-owned.
public struct SocketPathCapability: Sendable, Equatable {
    fileprivate let path: String; fileprivate let provenance: SocketPathProvenance; fileprivate let issuance: UUID
    fileprivate init(path: String, provenance: SocketPathProvenance) { self.path = path; self.provenance = provenance; self.issuance = UUID() }
}

/// Resolves the daemon/control socket through the one official mechanism.  The
/// public API takes no caller supplied path. The internal initializer exists
/// solely for controlled Unix-socket integration tests.
public struct OfficialSocketResolver: Sendable {
    private let source: @Sendable () throws -> String
    public init() { self.source = { throw UnixSocketValidationError.inaccessible } }
    init(source: @escaping @Sendable () throws -> String) { self.source = source }
    public func resolve(expectedOwner: uid_t = getuid()) throws -> SocketPathCapability {
        let path = try source(); _ = try UnixSocketValidator.validate(path: path, expectedOwner: expectedOwner)
        return SocketPathCapability(path: path, provenance: .officialDefault)
    }
}

/// Created only by a verified Monitor-owned launch operation. It carries the
/// opaque socket authority rather than accepting a runtime id as proof.
public struct MonitorOwnedLaunchRecord: Sendable, Equatable {
    public let runtimeInstanceID: RuntimeInstanceID; fileprivate let socketCapability: SocketPathCapability
    init(runtimeInstanceID: RuntimeInstanceID, verifiedSocketPath: String, expectedOwner: uid_t = getuid()) throws {
        _ = try UnixSocketValidator.validate(path: verifiedSocketPath, expectedOwner: expectedOwner)
        self.runtimeInstanceID = runtimeInstanceID
        self.socketCapability = SocketPathCapability(path: verifiedSocketPath, provenance: .monitorOwnedRuntimeLaunch(runtimeInstanceID))
    }
    func endpoint(expectedOwner: uid_t = getuid()) throws -> UnixSocketWebSocketEndpoint { try UnixSocketWebSocketEndpoint(capability: socketCapability, expectedOwner: expectedOwner) }
}

/// The only H2 endpoint type. A path is accepted only through an explicit
/// official-default or Monitor-owned-launch provenance boundary.
public struct UnixSocketWebSocketEndpoint: Sendable, Equatable {
    fileprivate let path: String
    private let expectedOwner: uid_t
    private let identity: UnixSocketIdentity
    public let socketProvenance: SocketPathProvenance
    public let provenance: TransportProvenance

    public init(capability: SocketPathCapability, expectedOwner: uid_t = getuid()) throws {
        let path = capability.path
        let identity = try UnixSocketValidator.validate(path: path, expectedOwner: expectedOwner)
        self.path = path; self.expectedOwner = expectedOwner; self.identity = identity; self.socketProvenance = capability.provenance
        self.provenance = TransportProvenance(kind: .unixSocketWebSocket)
    }

    func validateImmediatelyBeforeOpen() throws {
        let current = try UnixSocketValidator.validate(path: path, expectedOwner: expectedOwner)
        guard current == identity else { throw UnixSocketValidationError.replacedOrRemoved }
    }
}

public enum TransportKind: String, Codable, Sendable, Equatable { case unixSocketWebSocket = "Unix-socket WebSocket" }
public struct TransportProvenance: Codable, Sendable, Equatable {
    public let kind: TransportKind; public let localOnly: Bool; public let historicalEvidenceRewritten: Bool
    public init(kind: TransportKind) { self.kind = kind; self.localOnly = true; self.historicalEvidenceRewritten = false }
}

public enum UnixSocketValidationError: Error, Sendable, Equatable {
    case emptyPath, inaccessible, symlinkRejected, notUnixDomainSocket, unexpectedOwner, groupOrWorldWritable, insecureParentDirectory, replacedOrRemoved
}

fileprivate struct UnixSocketIdentity: Sendable, Equatable { let device: UInt64; let inode: UInt64 }
fileprivate enum UnixSocketValidator {
    @discardableResult static func validate(path: String, expectedOwner: uid_t) throws -> UnixSocketIdentity {
        guard !path.isEmpty else { throw UnixSocketValidationError.emptyPath }
        try validateParentChain(path: path, expectedOwner: expectedOwner)
        var metadata = stat()
        guard lstat(path, &metadata) == 0 else { throw UnixSocketValidationError.inaccessible }
        guard (metadata.st_mode & S_IFMT) != S_IFLNK else { throw UnixSocketValidationError.symlinkRejected }
        guard (metadata.st_mode & S_IFMT) == S_IFSOCK else { throw UnixSocketValidationError.notUnixDomainSocket }
        guard metadata.st_uid == expectedOwner else { throw UnixSocketValidationError.unexpectedOwner }
        guard (metadata.st_mode & (S_IWGRP | S_IWOTH)) == 0 else { throw UnixSocketValidationError.groupOrWorldWritable }
        return UnixSocketIdentity(device: UInt64(metadata.st_dev), inode: UInt64(metadata.st_ino))
    }

    private static func validateParentChain(path: String, expectedOwner: uid_t) throws {
        let components = URL(fileURLWithPath: path).standardized.pathComponents.dropLast()
        var current = ""
        for component in components {
            current += component == "/" ? "/" : (current == "/" ? component : "/\(component)")
            var metadata = stat()
            guard lstat(current, &metadata) == 0 else { throw UnixSocketValidationError.inaccessible }
            guard (metadata.st_mode & S_IFMT) != S_IFLNK else { throw UnixSocketValidationError.symlinkRejected }
            guard (metadata.st_mode & S_IFMT) == S_IFDIR else { throw UnixSocketValidationError.insecureParentDirectory }
            let writable = (metadata.st_mode & (S_IWGRP | S_IWOTH)) != 0
            let sticky = (metadata.st_mode & S_ISVTX) != 0
            guard !writable || sticky, metadata.st_uid == expectedOwner || metadata.st_uid == 0 else { throw UnixSocketValidationError.insecureParentDirectory }
        }
    }
}

public enum WebSocketFrameKind: Sendable, Equatable { case text, binary, close(status: Int?, reason: String?) }
public struct JSONRPCFrame: Sendable, Equatable {
    public let kind: WebSocketFrameKind; public let data: Data?; public let isComplete: Bool
    public init(kind: WebSocketFrameKind, data: Data? = nil, isComplete: Bool = true) { self.kind = kind; self.data = data; self.isComplete = isComplete }
}

/// A channel must expose WebSocket message boundaries; callers cannot silently
/// downgrade a frame to a raw TCP byte stream.
public protocol JSONRPCByteChannel: Sendable {
    func open() async throws
    func send(_ frame: JSONRPCFrame) async throws
    func receive() async throws -> JSONRPCFrame?
    func close() async
}

private final class ConnectionOpenContinuation: @unchecked Sendable {
    private let lock = NSLock(); private var continuation: CheckedContinuation<Void, Error>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func resolve(_ result: Result<Void, Error>) { lock.lock(); let pending = continuation; continuation = nil; lock.unlock(); pending?.resume(with: result) }
}

public actor UnixSocketWebSocketChannel: JSONRPCByteChannel {
    private let endpoint: UnixSocketWebSocketEndpoint; private var socketFD: Int32 = -1; private var sentTextFrames = 0
    public init(endpoint: UnixSocketWebSocketEndpoint) { self.endpoint = endpoint }

    public func open() async throws {
        guard socketFD < 0 else { return }
        try endpoint.validateImmediatelyBeforeOpen()
        let candidate = socket(AF_UNIX, SOCK_STREAM, 0); guard candidate >= 0 else { throw JSONRPCTransportError.transportFailure(.socketOpenFailed) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        _ = endpoint.path.withCString { source in withUnsafeMutablePointer(to: &address.sun_path) { destination in strcpy(UnsafeMutableRawPointer(destination).assumingMemoryBound(to: CChar.self), source) } }
        let connected = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(candidate, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard connected == 0 else { Darwin.close(candidate); throw JSONRPCTransportError.transportFailure(.socketOpenFailed) }
        do {
            let key = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            try unixWriteAll(candidate, Data("GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: \(key)\r\n\r\n".utf8))
            let response = try unixReadHTTPHeader(candidate)
            guard response.hasPrefix("HTTP/1.1 101") || response.hasPrefix("HTTP/1.0 101") else { throw JSONRPCTransportError.transportFailure(.socketOpenFailed) }
            socketFD = candidate
        } catch { Darwin.close(candidate); throw error }
    }

    public func send(_ frame: JSONRPCFrame) async throws {
        guard case .text = frame.kind, let data = frame.data, frame.isComplete, socketFD >= 0 else { throw JSONRPCTransportError.transportFailure(.socketSendFailed) }
        do { try unixWriteFrame(socketFD, opcode: 0x1, payload: data, masked: true); sentTextFrames += 1 }
        catch { throw JSONRPCTransportError.transportFailure(.socketSendFailed) }
    }

    public func receive() async throws -> JSONRPCFrame? {
        guard socketFD >= 0 else { throw JSONRPCTransportError.connectionClosed }
        do {
            let frame = try unixReadFrame(socketFD)
            guard frame.fin else { return JSONRPCFrame(kind: .binary, data: frame.payload, isComplete: false) }
            switch frame.opcode {
            case 0x1: return JSONRPCFrame(kind: .text, data: frame.payload)
            case 0x8:
                let bytes = [UInt8](frame.payload); let status = bytes.count >= 2 ? Int(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) : nil
                let reason = bytes.count > 2 ? String(decoding: bytes.dropFirst(2), as: UTF8.self) : nil
                return JSONRPCFrame(kind: .close(status: status, reason: reason))
            default: return JSONRPCFrame(kind: .binary, data: frame.payload)
            }
        } catch { throw JSONRPCTransportError.transportFailure(.socketReceiveFailed) }
    }

    public func close() async { if socketFD >= 0 { Darwin.close(socketFD); socketFD = -1 } }
    public func sentTextFrameCount() -> Int { sentTextFrames }
}

private func unixReadHTTPHeader(_ fd: Int32) throws -> String { var bytes: [UInt8] = []; while bytes.suffix(4) != [13, 10, 13, 10] { var byte: UInt8 = 0; guard recv(fd, &byte, 1, 0) == 1 else { throw POSIXError(.ECONNRESET) }; bytes.append(byte); if bytes.count > 16_384 { throw POSIXError(.EMSGSIZE) } }; return String(decoding: bytes, as: UTF8.self) }
private func unixReadFrame(_ fd: Int32) throws -> (fin: Bool, opcode: UInt8, payload: Data) { var head = [UInt8](repeating: 0, count: 2); try unixReadExact(fd, &head); var length = Int(head[1] & 0x7f); if length == 126 { var extended = [UInt8](repeating: 0, count: 2); try unixReadExact(fd, &extended); length = Int(UInt16(extended[0]) << 8 | UInt16(extended[1])) }; guard length <= 1_048_576 else { throw POSIXError(.EMSGSIZE) }; var mask = [UInt8](); if head[1] & 0x80 != 0 { mask = [UInt8](repeating: 0, count: 4); try unixReadExact(fd, &mask) }; var payload = [UInt8](repeating: 0, count: length); try unixReadExact(fd, &payload); if !mask.isEmpty { for index in payload.indices { payload[index] ^= mask[index % 4] } }; return (head[0] & 0x80 != 0, head[0] & 0x0f, Data(payload)) }
private func unixWriteFrame(_ fd: Int32, opcode: UInt8, payload: Data, masked: Bool) throws { guard payload.count <= 65_535 else { throw POSIXError(.EMSGSIZE) }; var header = [UInt8(0x80 | opcode)]; if payload.count < 126 { header.append(UInt8(payload.count) | (masked ? 0x80 : 0)) } else { header += [masked ? 0xfe : 126, UInt8(payload.count >> 8), UInt8(payload.count & 0xff)] }; var body = [UInt8](payload); if masked { let mask = [arc4random_uniform(256), arc4random_uniform(256), arc4random_uniform(256), arc4random_uniform(256)].map(UInt8.init); header += mask; for index in body.indices { body[index] ^= mask[index % 4] } }; try unixWriteAll(fd, Data(header + body)) }
private func unixReadExact(_ fd: Int32, _ bytes: inout [UInt8]) throws { var offset = 0; let total = bytes.count; while offset < total { let remaining = total - offset; let count = bytes.withUnsafeMutableBytes { recv(fd, $0.baseAddress!.advanced(by: offset), remaining, 0) }; guard count > 0 else { throw POSIXError(.ECONNRESET) }; offset += count } }
private func unixWriteAll(_ fd: Int32, _ data: Data) throws { try data.withUnsafeBytes { raw in var offset = 0; while offset < raw.count { let count = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0); guard count > 0 else { throw POSIXError(.EPIPE) }; offset += count } } }

public enum JSONRPCLifecycleState: Sendable, Equatable { case closed, opening, initializing, initialized, closing }

/// A unique adapter-instance owner token. A client accepts exactly one token
/// for its lifetime, preventing handler takeover even for equal bindings.
public struct JSONRPCAdapterLease: Sendable, Equatable, Hashable { fileprivate let token: UUID; public init() { token = UUID() } }

public actor JSONRPCClient {
    public typealias NotificationHandler = @Sendable (JSONRPCNotification, ConnectionContext) async -> Void
    public nonisolated let binding: JSONRPCClientBinding
    private let channel: any JSONRPCByteChannel; private let clientInfo: JSONRPCClientInfo; private let requestTimeout: Duration
    private var nextRequestID = 1; private var pending: [RequestID: PendingRequest] = [:]; private var receiver: Task<Void, Never>?
    private var handler: NotificationHandler?; private var lease: JSONRPCAdapterLease?; private var state: JSONRPCLifecycleState = .closed; private var context: ConnectionContext?; private var epochNumber = 0
    private var lastTerminalError: JSONRPCTransportError?
    private var connectFlight: Task<ConnectionEpoch, Error>?

    private struct PendingRequest { let context: ConnectionContext; let continuation: CheckedContinuation<JSONValue, Error>; let timeout: Task<Void, Never> }

    public init(channel: any JSONRPCByteChannel, binding: JSONRPCClientBinding, clientInfo: JSONRPCClientInfo = .h2TransportBoundary, requestTimeout: Duration = .seconds(10)) {
        self.channel = channel; self.binding = binding; self.clientInfo = clientInfo; self.requestTimeout = requestTimeout
    }

    public func installNotificationHandler(owner: JSONRPCAdapterLease, _ handler: @escaping NotificationHandler) throws {
        guard lease == nil || lease == owner else { throw JSONRPCTransportError.sourceBindingRejected }
        lease = owner; self.handler = handler
    }
    public func lifecycleState() -> JSONRPCLifecycleState { state }
    public func currentConnectionContext() -> ConnectionContext? { context }
    public func terminalError() -> JSONRPCTransportError? { lastTerminalError }

    /// Reconnection creates a fresh transport context only. It never reads or
    /// reconstructs runtime state.
    public func connect() async throws -> ConnectionEpoch {
        if case .initialized = state, let context { return context.epoch }
        if let connectFlight { return try await connectFlight.value }
        guard state == .closed else { throw JSONRPCTransportError.lifecycleUnavailable }
        state = .opening
        let flight = Task { [weak self] () throws -> ConnectionEpoch in
            guard let self else { throw JSONRPCTransportError.connectionClosed }
            return try await self.performConnect()
        }
        connectFlight = flight
        do { let result = try await flight.value; connectFlight = nil; return result }
        catch { connectFlight = nil; throw error }
    }

    private func performConnect() async throws -> ConnectionEpoch {
        do { try await channel.open() }
        catch let error as UnixSocketValidationError { await transitionToClosed(error: .endpointRejected(error)); throw JSONRPCTransportError.endpointRejected(error) }
        catch let error as JSONRPCTransportError { await transitionToClosed(error: error); throw error }
        catch { await transitionToClosed(error: .transportFailure(.socketOpenFailed)); throw JSONRPCTransportError.transportFailure(.socketOpenFailed) }
        guard state == .opening else { await channel.close(); throw JSONRPCTransportError.connectionClosed }
        epochNumber += 1
        let opened = ConnectionContext(binding: binding, epoch: ConnectionEpoch("connection-\(epochNumber)")!)
        context = opened; state = .initializing
        receiver = Task { [weak self, opened] in await self?.receiveLoop(context: opened) }
        do {
            let initializeResponse = try await sendRequest(method: "initialize", params: .object(["clientInfo": .object(["name": .string(clientInfo.name), "title": .string(clientInfo.title), "version": .string(clientInfo.version)])]), context: opened)
            guard GeneratedInitializeResponse.isValid(initializeResponse) else { throw JSONRPCTransportError.malformedMessage(.malformedShape) }
            guard context == opened, state == .initializing else { throw JSONRPCTransportError.connectionClosed }
            try await sendNotification(method: "initialized", params: .object([:]), context: opened)
            guard context == opened, state == .initializing else { throw JSONRPCTransportError.connectionClosed }
            state = .initialized
            return opened.epoch
        } catch {
            await transitionToClosed(error: error as? JSONRPCTransportError ?? .transportFailure(.socketOpenFailed))
            throw error
        }
    }

    public func request(method: String, params: JSONValue? = nil) async throws -> JSONValue {
        guard state == .initialized, let context else { throw JSONRPCTransportError.connectionClosed }
        return try await sendRequest(method: method, params: params, context: context)
    }

    private func sendRequest(method: String, params: JSONValue?, context: ConnectionContext) async throws -> JSONValue {
        guard self.context == context, state == .initializing || state == .initialized else { throw JSONRPCTransportError.connectionClosed }
        guard !Task.isCancelled else { throw JSONRPCTransportError.requestCancelled }
        let id = RequestID.integer(nextRequestID); nextRequestID += 1
        let data = try JSONEncoder().encode(JSONRPCRequest(id: id, method: method, params: params))
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: JSONRPCTransportError.requestCancelled); return }
                let timeout = Task { [weak self, requestTimeout] in
                    try? await Task.sleep(for: requestTimeout)
                    await self?.failRequest(id: id, context: context, error: .requestTimedOut)
                }
                pending[id] = PendingRequest(context: context, continuation: continuation, timeout: timeout)
                Task { [channel] in
                    do { try await channel.send(JSONRPCFrame(kind: .text, data: data)) }
                    catch { self.failRequest(id: id, context: context, error: .transportFailure(.socketSendFailed)) }
                }
            }
        }, onCancel: { Task { await self.failRequest(id: id, context: context, error: .requestCancelled) } })
    }

    private func sendNotification(method: String, params: JSONValue?, context: ConnectionContext) async throws {
        guard self.context == context else { throw JSONRPCTransportError.connectionClosed }
        let data = try JSONEncoder().encode(JSONRPCNotification(method: method, params: params))
        do { try await channel.send(JSONRPCFrame(kind: .text, data: data)) }
        catch { throw JSONRPCTransportError.transportFailure(.socketSendFailed) }
    }

    public func close() async { await transitionToClosed(error: .connectionClosed) }

    private func transitionToClosed(error: JSONRPCTransportError) async {
        guard state != .closed else { return }
        state = .closing
        lastTerminalError = error
        let oldReceiver = receiver; receiver = nil; oldReceiver?.cancel()
        context = nil
        await channel.close()
        failAll(with: error)
        // A reconnect cannot install a new authoritative receiver until every
        // old receive task has terminated. `closeFromReceiver` clears itself
        // first, so this never awaits the currently executing task.
        if let oldReceiver { await oldReceiver.value }
        state = .closed
    }

    private func closeFromReceiver(context receiverContext: ConnectionContext, error: JSONRPCTransportError) async {
        guard self.context == receiverContext else { return }
        receiver = nil
        await transitionToClosed(error: error)
    }

    private func receiveLoop(context receiverContext: ConnectionContext) async {
        while !Task.isCancelled, self.context == receiverContext {
            do {
                guard let frame = try await channel.receive() else { await closeFromReceiver(context: receiverContext, error: .connectionClosed); return }
                guard frame.isComplete else { await closeFromReceiver(context: receiverContext, error: .transportFailure(.incompleteFrame)); return }
                switch frame.kind {
                case .text:
                    guard let data = frame.data else { recordMalformed(); continue }
                    await route(data: data, context: receiverContext)
                case .binary: await closeFromReceiver(context: receiverContext, error: .transportFailure(.nonTextFrame)); return
                case .close(let status, let reason): await closeFromReceiver(context: receiverContext, error: .webSocketClosed(status: status, reason: reason)); return
                }
            } catch { await closeFromReceiver(context: receiverContext, error: .transportFailure(.socketReceiveFailed)); return }
        }
    }

    private func route(data: Data, context receiverContext: ConnectionContext) async {
        guard self.context == receiverContext else { return }
        do {
            switch try JSONRPCWireDecoder.decode(data) {
            case .notification(let notification):
                guard state == .initialized, self.context == receiverContext else { return }
                await handler?(notification, receiverContext)
            case .response(let response):
                guard let pending = pending[response.id], pending.context == receiverContext else { return }
                self.pending.removeValue(forKey: response.id)?.timeout.cancel()
                if let error = response.error { pending.continuation.resume(throwing: JSONRPCTransportError.protocolError(code: error.code)) }
                else if let result = response.result { pending.continuation.resume(returning: result) }
                else { pending.continuation.resume(throwing: JSONRPCTransportError.malformedMessage(.malformedShape)) }
            case .request: recordMalformed()
            }
        } catch let rejection as JSONRPCWireRejection { _ = rejection; recordMalformed() }
        catch { recordMalformed() }
    }

    /// Malformed application messages are source-local diagnostics only. They
    /// cannot fail unrelated pending requests or be delivered to an Adapter.
    private func recordMalformed() {}

    private func failRequest(id: RequestID, context: ConnectionContext, error: JSONRPCTransportError) {
        guard let pending = pending[id], pending.context == context else { return }
        self.pending.removeValue(forKey: id)?.timeout.cancel(); pending.continuation.resume(throwing: error)
    }
    private func failAll(with error: JSONRPCTransportError) {
        let requests = pending; pending.removeAll()
        for request in requests.values { request.timeout.cancel(); request.continuation.resume(throwing: error) }
    }
}
