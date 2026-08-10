import Foundation
import Network
import Darwin

/// JSON values are retained only while routing a request. Adapters must turn
/// them into normalized contracts or sanitized diagnostics before output.
public indirect enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

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

    public var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
    public var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }
}

public struct JSONRPCRequest: Codable, Sendable, Equatable {
    public let jsonrpc: String
    public let id: Int
    public let method: String
    public let params: JSONValue?

    public init(id: Int, method: String, params: JSONValue?) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Sendable, Equatable {
    public let jsonrpc: String
    public let id: Int?
    public let result: JSONValue?
    public let error: JSONRPCError?
}

public struct JSONRPCNotification: Codable, Sendable, Equatable {
    public let jsonrpc: String
    public let method: String
    public let params: JSONValue?
}

public struct JSONRPCError: Codable, Sendable, Equatable {
    public let code: Int
    public let message: String?
    public let data: JSONValue?
}

public struct JSONRPCClientInfo: Codable, Sendable, Equatable {
    public let name: String
    public let title: String
    public let version: String

    public init(name: String, title: String, version: String) {
        self.name = name
        self.title = title
        self.version = version
    }

    public static let h2TransportBoundary = JSONRPCClientInfo(name: "codex_monitor_h2", title: "Codex Monitor H2", version: "h2")
}

public enum JSONRPCTransportError: Error, Sendable, Equatable {
    case endpointRejected(UnixSocketValidationError)
    case malformedMessage
    case connectionClosed
    case protocolError(code: Int)
    case requestCancelled
    case transportFailure(String)
}

/// The only H2 endpoint type. TCP and URL endpoints cannot be represented.
public struct UnixSocketWebSocketEndpoint: Sendable, Equatable {
    fileprivate let path: String
    public let provenance: TransportProvenance

    public init(validating path: String, expectedOwner: uid_t = getuid()) throws {
        try UnixSocketValidator.validate(path: path, expectedOwner: expectedOwner)
        self.path = path
        self.provenance = TransportProvenance(kind: .unixSocketWebSocket)
    }
}

public enum TransportKind: String, Codable, Sendable, Equatable {
    case unixSocketWebSocket = "Unix-socket WebSocket"
}

/// This intentionally records the forward binding without copying or changing
/// the AR-P0 historical transport label held in EvidenceMetadata.
public struct TransportProvenance: Codable, Sendable, Equatable {
    public let kind: TransportKind
    public let localOnly: Bool
    public let historicalEvidenceRewritten: Bool

    public init(kind: TransportKind) {
        self.kind = kind
        self.localOnly = true
        self.historicalEvidenceRewritten = false
    }
}

public enum UnixSocketValidationError: Error, Sendable, Equatable {
    case emptyPath
    case inaccessible
    case notUnixDomainSocket
    case unexpectedOwner
    case groupOrWorldWritable
}

public enum UnixSocketValidator {
    public static func validate(path: String, expectedOwner: uid_t) throws {
        guard !path.isEmpty else { throw UnixSocketValidationError.emptyPath }
        var metadata = stat()
        guard lstat(path, &metadata) == 0 else { throw UnixSocketValidationError.inaccessible }
        guard (metadata.st_mode & S_IFMT) == S_IFSOCK else { throw UnixSocketValidationError.notUnixDomainSocket }
        guard metadata.st_uid == expectedOwner else { throw UnixSocketValidationError.unexpectedOwner }
        guard (metadata.st_mode & (S_IWGRP | S_IWOTH)) == 0 else { throw UnixSocketValidationError.groupOrWorldWritable }
    }
}

/// An injectable byte channel makes routing deterministic in tests while the
/// production implementation remains a Unix-domain WebSocket channel.
public protocol JSONRPCByteChannel: Sendable {
    func open() async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data?
    func close() async
}

private final class ConnectionOpenContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }

    func resolve(_ result: Result<Void, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

public actor UnixSocketWebSocketChannel: JSONRPCByteChannel {
    private let endpoint: UnixSocketWebSocketEndpoint
    private var connection: NWConnection?

    public init(endpoint: UnixSocketWebSocketEndpoint) { self.endpoint = endpoint }

    public func open() async throws {
        guard connection == nil else { return }
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        let candidate = NWConnection(to: .unix(path: endpoint.path), using: parameters)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = ConnectionOpenContinuation(continuation)
            candidate.stateUpdateHandler = { state in
                switch state {
                case .ready: completion.resolve(.success(()))
                case .failed: completion.resolve(.failure(JSONRPCTransportError.transportFailure("socketConnectionFailed")))
                case .cancelled: completion.resolve(.failure(JSONRPCTransportError.connectionClosed))
                default: break
                }
            }
            candidate.start(queue: .global(qos: .utility))
        }
        connection = candidate
    }

    public func send(_ data: Data) async throws {
        guard let connection else { throw JSONRPCTransportError.connectionClosed }
        try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { error in
                if error == nil { continuation.resume() }
                else { continuation.resume(throwing: JSONRPCTransportError.transportFailure("socketSendFailed")) }
            })
        }
    }

    public func receive() async throws -> Data? {
        guard let connection else { throw JSONRPCTransportError.connectionClosed }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receiveMessage { data, _, complete, error in
                if error != nil { continuation.resume(throwing: JSONRPCTransportError.transportFailure("socketReceiveFailed")) }
                else if complete { continuation.resume(returning: data) }
                else { continuation.resume(returning: data) }
            }
        }
    }

    public func close() async {
        connection?.cancel()
        connection = nil
    }
}

public actor JSONRPCClient {
    public typealias NotificationHandler = @Sendable (JSONRPCNotification) async -> Void

    private let channel: any JSONRPCByteChannel
    private let clientInfo: JSONRPCClientInfo
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var receiver: Task<Void, Never>?
    private var handler: NotificationHandler?
    private var isOpen = false
    private var isInitialized = false
    private var epochNumber = 0

    public init(channel: any JSONRPCByteChannel, clientInfo: JSONRPCClientInfo = .h2TransportBoundary) {
        self.channel = channel
        self.clientInfo = clientInfo
    }

    public func setNotificationHandler(_ handler: NotificationHandler?) { self.handler = handler }

    /// Reopening replaces only the low-level connection epoch. It does not load
    /// prior runtime state, reattach an owner, or reconstruct missed events.
    public func connect() async throws -> ConnectionEpoch {
        if isOpen, isInitialized { return ConnectionEpoch("connection-\(epochNumber)")! }
        do { try await channel.open() }
        catch let error as UnixSocketValidationError { throw JSONRPCTransportError.endpointRejected(error) }
        catch { throw JSONRPCTransportError.transportFailure("socketOpenFailed") }
        isOpen = true
        epochNumber += 1
        receiver = Task { [weak self] in await self?.receiveLoop() }
        do {
            _ = try await request(method: "initialize", params: .object([
                "clientInfo": .object([
                    "name": .string(clientInfo.name),
                    "title": .string(clientInfo.title),
                    "version": .string(clientInfo.version)
                ])
            ]))
            try await notify(method: "initialized", params: .object([:]))
            isInitialized = true
        } catch {
            await close()
            throw error
        }
        return ConnectionEpoch("connection-\(epochNumber)")!
    }

    public func request(method: String, params: JSONValue? = nil) async throws -> JSONValue {
        guard isOpen, isInitialized || method == "initialize" else { throw JSONRPCTransportError.connectionClosed }
        let id = nextRequestID
        nextRequestID += 1
        let data = try JSONEncoder().encode(JSONRPCRequest(id: id, method: method, params: params))
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                Task { [channel] in
                    do { try await channel.send(data) }
                    catch { self.failRequest(id: id, error: JSONRPCTransportError.transportFailure("socketSendFailed")) }
                }
            }
        }, onCancel: {
            Task { await self.failRequest(id: id, error: JSONRPCTransportError.requestCancelled) }
        })
    }

    private func notify(method: String, params: JSONValue?) async throws {
        let data = try JSONEncoder().encode(JSONRPCNotification(jsonrpc: "2.0", method: method, params: params))
        do { try await channel.send(data) }
        catch { throw JSONRPCTransportError.transportFailure("socketSendFailed") }
    }

    public func close() async {
        receiver?.cancel()
        receiver = nil
        isOpen = false
        isInitialized = false
        await channel.close()
        failAll(with: JSONRPCTransportError.connectionClosed)
    }

    private func receiveLoop() async {
        while !Task.isCancelled, isOpen {
            do {
                guard let data = try await channel.receive() else { await close(); return }
                try await route(data)
            } catch {
                await close()
                return
            }
        }
    }

    private func route(_ data: Data) async throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = value.objectValue else { throw JSONRPCTransportError.malformedMessage }
        if object["method"] != nil {
            let notification = try JSONDecoder().decode(JSONRPCNotification.self, from: data)
            await handler?(notification)
            return
        }
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        guard let id = response.id, let continuation = pending.removeValue(forKey: id) else { return }
        if let error = response.error { continuation.resume(throwing: JSONRPCTransportError.protocolError(code: error.code)) }
        else if let result = response.result { continuation.resume(returning: result) }
        else { continuation.resume(throwing: JSONRPCTransportError.malformedMessage) }
    }

    private func failRequest(id: Int, error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func failAll(with error: Error) {
        let requests = pending
        pending.removeAll()
        requests.values.forEach { $0.resume(throwing: error) }
    }
}
