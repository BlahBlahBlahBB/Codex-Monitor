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
public struct JSONRPCRequest: Codable, Sendable, Equatable {
    public let id: Int
    public let method: String
    public let params: JSONValue?
    public init(id: Int, method: String, params: JSONValue?) { self.id = id; self.method = method; self.params = params }
}

public struct JSONRPCNotification: Codable, Sendable, Equatable {
    public let method: String
    public let params: JSONValue?
    public init(method: String, params: JSONValue?) { self.method = method; self.params = params }
}

public struct JSONRPCError: Codable, Sendable, Equatable {
    public let code: Int
    /// This is deliberately never surfaced outside request-local failure.
    public let message: String?
    public let data: JSONValue?
    public init(code: Int, message: String? = nil, data: JSONValue? = nil) { self.code = code; self.message = message; self.data = data }
}

public struct JSONRPCResponse: Codable, Sendable, Equatable {
    public let id: Int
    public let result: JSONValue?
    public let error: JSONRPCError?
    public init(id: Int, result: JSONValue? = nil, error: JSONRPCError? = nil) { self.id = id; self.result = result; self.error = error }
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
                guard let id = object["id"]?.integerValue else { throw JSONRPCWireRejection.malformedID }
                _ = id
                throw JSONRPCWireRejection.serverRequestUnsupported
            }
            return .notification(JSONRPCNotification(method: method, params: object["params"]))
        }
        guard hasID else { throw JSONRPCWireRejection.malformedShape }
        guard let id = object["id"]?.integerValue else { throw JSONRPCWireRejection.malformedID }
        guard hasResult != hasError else { throw JSONRPCWireRejection.responseMustContainExactlyOneResultOrError }
        if hasError {
            guard let errorValue = object["error"], let error = try? JSONDecoder().decode(JSONRPCError.self, from: JSONEncoder().encode(errorValue)) else {
                throw JSONRPCWireRejection.malformedError
            }
            return .response(JSONRPCResponse(id: id, error: error))
        }
        return .response(JSONRPCResponse(id: id, result: object["result"]))
    }
}

public struct JSONRPCClientInfo: Codable, Sendable, Equatable {
    public let name: String; public let title: String; public let version: String
    public init(name: String, title: String, version: String) { self.name = name; self.title = title; self.version = version }
    public static let h2TransportBoundary = JSONRPCClientInfo(name: "codex_monitor_h2", title: "Codex Monitor H2", version: "h2")
}

public struct JSONRPCClientBinding: Sendable, Equatable {
    public let sourceID: SourceID; public let sourceKind: SourceKind; public let adapterID: AdapterID; public let adapterVersion: AdapterVersion; public let runtimeInstanceID: RuntimeInstanceID?
    public init(descriptor: AdapterDescriptor, runtimeInstanceID: RuntimeInstanceID? = nil) throws {
        guard descriptor.sourceKind != .futureObserver,
              (descriptor.sourceKind == .monitorOwnedRuntime) == (runtimeInstanceID != nil) else { throw JSONRPCTransportError.sourceBindingRejected }
        self.sourceID = descriptor.sourceID; self.sourceKind = descriptor.sourceKind; self.adapterID = descriptor.adapterID; self.adapterVersion = descriptor.adapterVersion; self.runtimeInstanceID = runtimeInstanceID
    }
}

public struct ConnectionContext: Sendable, Equatable {
    public let binding: JSONRPCClientBinding; public let epoch: ConnectionEpoch
}

public enum JSONRPCTransportError: Error, Sendable, Equatable {
    case endpointRejected(UnixSocketValidationError), malformedMessage(JSONRPCWireRejection)
    case connectionClosed, requestCancelled, requestTimedOut, sourceBindingRejected, lifecycleUnavailable
    case protocolError(code: Int), transportFailure(TransportFailureCode)
}

public enum TransportFailureCode: String, Sendable, Equatable { case socketOpenFailed, socketSendFailed, socketReceiveFailed, nonTextFrame, incompleteFrame, socketClosed }

public enum SocketPathProvenance: Sendable, Equatable { case officialDefault, monitorOwnedRuntimeLaunch(RuntimeInstanceID) }

/// The only H2 endpoint type. A path is accepted only through an explicit
/// official-default or Monitor-owned-launch provenance boundary.
public struct UnixSocketWebSocketEndpoint: Sendable, Equatable {
    fileprivate let path: String
    private let expectedOwner: uid_t
    private let identity: UnixSocketIdentity
    public let socketProvenance: SocketPathProvenance
    public let provenance: TransportProvenance

    init(authorizedPath path: String, socketProvenance: SocketPathProvenance, expectedOwner: uid_t = getuid()) throws {
        let identity = try UnixSocketValidator.validate(path: path, expectedOwner: expectedOwner)
        self.path = path; self.expectedOwner = expectedOwner; self.identity = identity; self.socketProvenance = socketProvenance
        self.provenance = TransportProvenance(kind: .unixSocketWebSocket)
    }

    public static func officialDefault(path: String, expectedOwner: uid_t = getuid()) throws -> Self {
        try Self(authorizedPath: path, socketProvenance: .officialDefault, expectedOwner: expectedOwner)
    }

    public static func monitorOwnedLaunch(path: String, runtimeInstanceID: RuntimeInstanceID, expectedOwner: uid_t = getuid()) throws -> Self {
        try Self(authorizedPath: path, socketProvenance: .monitorOwnedRuntimeLaunch(runtimeInstanceID), expectedOwner: expectedOwner)
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
    private let endpoint: UnixSocketWebSocketEndpoint; private var connection: NWConnection?
    public init(endpoint: UnixSocketWebSocketEndpoint) { self.endpoint = endpoint }

    public func open() async throws {
        guard connection == nil else { return }
        try endpoint.validateImmediatelyBeforeOpen()
        let webSocket = NWProtocolWebSocket.Options(); webSocket.autoReplyPing = true
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options()); parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        let candidate = NWConnection(to: .unix(path: endpoint.path), using: parameters)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = ConnectionOpenContinuation(continuation)
            candidate.stateUpdateHandler = { state in
                switch state {
                case .ready: completion.resolve(.success(()))
                case .failed: completion.resolve(.failure(JSONRPCTransportError.transportFailure(.socketOpenFailed)))
                case .cancelled: completion.resolve(.failure(JSONRPCTransportError.connectionClosed))
                default: break
                }
            }
            candidate.start(queue: .global(qos: .utility))
        }
        connection = candidate
    }

    public func send(_ frame: JSONRPCFrame) async throws {
        guard case .text = frame.kind, let data = frame.data, frame.isComplete, let connection else { throw JSONRPCTransportError.transportFailure(.socketSendFailed) }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "app-server-text", metadata: [metadata])
        try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                error == nil ? continuation.resume() : continuation.resume(throwing: JSONRPCTransportError.transportFailure(.socketSendFailed))
            })
        }
    }

    public func receive() async throws -> JSONRPCFrame? {
        guard let connection else { throw JSONRPCTransportError.connectionClosed }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receiveMessage { data, context, complete, error in
                if error != nil { continuation.resume(throwing: JSONRPCTransportError.transportFailure(.socketReceiveFailed)); return }
                guard complete else { continuation.resume(returning: JSONRPCFrame(kind: .binary, data: data, isComplete: false)); return }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                switch metadata?.opcode {
                case .text: continuation.resume(returning: JSONRPCFrame(kind: .text, data: data))
                case .close: continuation.resume(returning: JSONRPCFrame(kind: .close(status: nil, reason: nil)))
                default: continuation.resume(returning: JSONRPCFrame(kind: .binary, data: data))
                }
            }
        }
    }

    public func close() async { connection?.cancel(); connection = nil }
}

public enum JSONRPCLifecycleState: Sendable, Equatable { case closed, opening, initializing, initialized, closing }

public actor JSONRPCClient {
    public typealias NotificationHandler = @Sendable (JSONRPCNotification, ConnectionContext) async -> Void
    public nonisolated let binding: JSONRPCClientBinding
    private let channel: any JSONRPCByteChannel; private let clientInfo: JSONRPCClientInfo; private let requestTimeout: Duration
    private var nextRequestID = 1; private var pending: [Int: PendingRequest] = [:]; private var receiver: Task<Void, Never>?
    private var handler: NotificationHandler?; private var state: JSONRPCLifecycleState = .closed; private var context: ConnectionContext?; private var epochNumber = 0
    private var connectFlight: Task<ConnectionEpoch, Error>?

    private struct PendingRequest { let context: ConnectionContext; let continuation: CheckedContinuation<JSONValue, Error>; let timeout: Task<Void, Never> }

    public init(channel: any JSONRPCByteChannel, binding: JSONRPCClientBinding, clientInfo: JSONRPCClientInfo = .h2TransportBoundary, requestTimeout: Duration = .seconds(10)) {
        self.channel = channel; self.binding = binding; self.clientInfo = clientInfo; self.requestTimeout = requestTimeout
    }

    public func setNotificationHandler(_ handler: NotificationHandler?) { self.handler = handler }
    public func lifecycleState() -> JSONRPCLifecycleState { state }
    public func currentConnectionContext() -> ConnectionContext? { context }

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
            _ = try await sendRequest(method: "initialize", params: .object(["clientInfo": .object(["name": .string(clientInfo.name), "title": .string(clientInfo.title), "version": .string(clientInfo.version)])]), context: opened)
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
        let id = nextRequestID; nextRequestID += 1
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
        let oldReceiver = receiver; receiver = nil; oldReceiver?.cancel()
        context = nil
        await channel.close()
        failAll(with: error)
        state = .closed
    }

    private func receiveLoop(context receiverContext: ConnectionContext) async {
        while !Task.isCancelled, self.context == receiverContext {
            do {
                guard let frame = try await channel.receive() else { await transitionToClosed(error: .connectionClosed); return }
                guard frame.isComplete else { await transitionToClosed(error: .transportFailure(.incompleteFrame)); return }
                switch frame.kind {
                case .text:
                    guard let data = frame.data else { recordMalformed(); continue }
                    await route(data: data, context: receiverContext)
                case .binary: await transitionToClosed(error: .transportFailure(.nonTextFrame)); return
                case .close: await transitionToClosed(error: .connectionClosed); return
                }
            } catch { await transitionToClosed(error: .transportFailure(.socketReceiveFailed)); return }
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

    private func failRequest(id: Int, context: ConnectionContext, error: JSONRPCTransportError) {
        guard let pending = pending[id], pending.context == context else { return }
        self.pending.removeValue(forKey: id)?.timeout.cancel(); pending.continuation.resume(throwing: error)
    }
    private func failAll(with error: JSONRPCTransportError) {
        let requests = pending; pending.removeAll()
        for request in requests.values { request.timeout.cancel(); request.continuation.resume(throwing: error) }
    }
}
