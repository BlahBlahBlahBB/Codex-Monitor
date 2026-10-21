import XCTest
import Darwin
@testable import CodexMonitorApp
@testable import CodexMonitorContracts

final class AccountRefreshAttributionTests: XCTestCase {
    func testOfficialAccountReadFailureUsesProductionStageWrapper() async throws {
        let fields = try await officialDiagnostic(outcomes: [.success(initialize()), .failure])
        XCTAssertEqual(fields["route"], "officialSocket")
        XCTAssertEqual(fields["stage"], "accountRead")
        XCTAssertEqual(fields["reason"], "protocolError")
    }

    func testOfficialOpenFailureUsesProductionConnectBoundary() async throws {
        let channel = ScriptedAccountChannel(openError: JSONRPCTransportError.transportFailure(.socketOpenFailed))
        let fields = try await officialDiagnostic(channel: channel)
        XCTAssertEqual(fields["stage"], "socketOpen")
        XCTAssertEqual(fields["reason"], "transportFailure")
    }

    func testInitializeFailureAfterOpenUsesProductionConnectBoundary() async throws {
        let fields = try await officialDiagnostic(outcomes: [.failure])
        XCTAssertEqual(fields["stage"], "initialize")
        XCTAssertEqual(fields["reason"], "protocolError")
    }

    func testBundledLaunchFailureUsesProductionConnectBoundary() async throws {
        let channel = ScriptedAccountChannel(openError: JSONRPCTransportError.transportFailure(.processLaunchFailed))
        let fields = try await bundledDiagnostic(channel: channel)
        XCTAssertEqual(fields["route"], "bundledStdio")
        XCTAssertEqual(fields["stage"], "processLaunch")
        XCTAssertEqual(fields["reason"], "transportFailure")
    }

    func testBundledRateLimitsReadFailureUsesSharedProductionWrapper() async throws {
        let fields = try await bundledDiagnostic(outcomes: [.success(initialize()), .success(account()), .failure])
        XCTAssertEqual(fields["route"], "bundledStdio")
        XCTAssertEqual(fields["stage"], "rateLimitsRead")
        XCTAssertEqual(fields["reason"], "protocolError")
    }

    func testUsageReadFailureUsesProductionStageWrapper() async throws {
        let fields = try await officialDiagnostic(outcomes: [.success(initialize()), .success(account()), .success(limits()), .failure])
        XCTAssertEqual(fields["route"], "officialSocket")
        XCTAssertEqual(fields["stage"], "usageRead")
        XCTAssertEqual(fields["reason"], "protocolError")
    }

    func testMalformedSuccessfulPayloadUsesResponseDecodeAndLeaksNoMarker() async throws {
        let marker = "FAKE_BEARER_GATE2_DO_NOT_LEAK"
        let fields = try await officialDiagnostic(outcomes: [.success(initialize()), .success(account()), .success(.string(marker)), .success(usage())])
        XCTAssertEqual(fields["stage"], "responseDecode")
        XCTAssertEqual(fields["reason"], "responseIncompatible")
        XCTAssertFalse(fields.values.joined().contains(marker))
    }

    func testOfficialSocketResolveFailureUsesProductionResolverBoundary() async throws {
        let fields = try await diagnostic(
            dependencies: testDependencies(
                official: ScriptedAccountChannel(),
                bundled: ScriptedAccountChannel(openError: JSONRPCTransportError.lifecycleUnavailable),
                officialSocketResolver: { throw UnixSocketValidationError.inaccessible }
            ),
            expectedRoute: "officialSocket"
        )
        XCTAssertEqual(fields["stage"], "socketResolve")
        XCTAssertEqual(fields["reason"], "inaccessible")
    }

    func testOfficialSocketValidateFailureUsesProductionValidationBoundary() async throws {
        let fields = try await diagnostic(
            dependencies: testDependencies(
                official: ScriptedAccountChannel(),
                bundled: ScriptedAccountChannel(openError: JSONRPCTransportError.lifecycleUnavailable),
                officialEndpoint: { _ in throw UnixSocketValidationError.inaccessible }
            ),
            expectedRoute: "officialSocket"
        )
        XCTAssertEqual(fields["stage"], "socketValidate")
        XCTAssertEqual(fields["reason"], "inaccessible")
    }

    func testBundledExecutableResolveFailureUsesProductionResolverBoundary() async throws {
        let fields = try await diagnostic(
            dependencies: testDependencies(
                official: ScriptedAccountChannel(openError: JSONRPCTransportError.requestTimedOut),
                bundled: ScriptedAccountChannel(),
                bundledExecutableResolver: { throw TrustedCodexStdioError.executableMissing }
            ),
            expectedRoute: "bundledStdio"
        )
        XCTAssertEqual(fields["stage"], "executableResolve")
        XCTAssertEqual(fields["reason"], "executableMissing")
    }

    func testBundledInitializeFailureOccursAfterChannelOpen() async throws {
        let bundled = ScriptedAccountChannel(outcomes: [.failure])
        let fields = try await diagnostic(
            dependencies: testDependencies(
                official: ScriptedAccountChannel(openError: JSONRPCTransportError.requestTimedOut),
                bundled: bundled
            ),
            expectedRoute: "bundledStdio"
        )
        let opened = await bundled.didOpen()
        XCTAssertTrue(opened)
        XCTAssertEqual(fields["stage"], "initialize")
        XCTAssertEqual(fields["reason"], "protocolError")
    }

    func testProviderSelectsEligibleFallbackAndAdmitsBundledAuthoritativeCycle() async throws {
        let official = ScriptedAccountChannel(openError: JSONRPCTransportError.requestTimedOut)
        let bundled = ScriptedAccountChannel(outcomes: [.success(initialize()), .success(account()), .success(limits()), .success(usage())])
        let recorder = EmittedAccountDiagnosticRecorder()
        let dependencies = try testDependencies(official: official, bundled: bundled)
        let runtime = MonitorRuntimeStore(initialPhase: .live)
        let provider = AccountUsageProvider(runtime: runtime, routeDependencies: dependencies, diagnosticRecorder: { category, fields in
            recorder.record(category: category, fields: fields)
        })
        let before = await runtime.accountRefreshTimestamps()
        let beforeSnapshot = await runtime.snapshot()
        XCTAssertNil(before.lastAuthoritative)
        XCTAssertNil(beforeSnapshot.quota.primary)
        XCTAssertNil(beforeSnapshot.usage.usage)

        await provider.refreshOnce()

        let timestamps = await runtime.accountRefreshTimestamps()
        let snapshot = await runtime.snapshot()
        XCTAssertNotNil(timestamps.lastAuthoritative)
        XCTAssertNil(timestamps.degradedSince)
        XCTAssertNil(timestamps.lastFailure)
        XCTAssertEqual(snapshot.accountFreshness, .fresh)
        XCTAssertEqual(snapshot.quota.primary?.usedPercent, 10)
        XCTAssertEqual(snapshot.usage.usage?.totalTokens, 1)

        let emitted = recorder.events()
        XCTAssertTrue(emitted.contains(where: { $0.fields["event"] == "accountRefresh" && $0.fields["route"] == "officialSocket" && $0.fields["stage"] == "initialize" && $0.fields["reason"] == "requestTimedOut" }))
        XCTAssertTrue(emitted.contains(where: { $0.fields["event"] == "accountRefreshFallback" && $0.fields["route"] == "officialSocket" && $0.fields["nextRoute"] == "bundledStdio" }))
        XCTAssertTrue(emitted.contains(where: { $0.fields["event"] == "accountRefreshSucceeded" && $0.fields["route"] == "bundledStdio" }))
    }

    func testFinalEmittedAccountEventsExcludeSyntheticSensitiveMarkers() async throws {
        let markers = [
            "FAKE_BEARER_GATE2_DO_NOT_LEAK",
            "fake-gate2@example.test",
            "/private/FAKE_GATE2_SECRET_PATH",
            "RAW_SERVER_GATE2_DO_NOT_LEAK",
            "REQUEST_ID_GATE2_DO_NOT_LEAK"
        ]
        let recorder = EmittedAccountDiagnosticRecorder()
        let combinedMarker = markers.joined(separator: " ")
        let initializeResponse = initialize()
        let accountResponse = account()
        let limitsResponse = limits()
        let usageResponse = usage()

        let fallbackRuntime = MonitorRuntimeStore(initialPhase: .live)
        let fallbackProvider = AccountUsageProvider(
            runtime: fallbackRuntime,
            routeDependencies: try testDependencies(
                official: ScriptedAccountChannel(openError: JSONRPCTransportError.webSocketClosed(status: 4000, reason: combinedMarker)),
                bundled: ScriptedAccountChannel(outcomes: [.success(initializeResponse), .success(accountResponse), .success(limitsResponse), .success(usageResponse)])
            ),
            diagnosticRecorder: { category, fields in recorder.record(category: category, fields: fields) }
        )
        await fallbackProvider.refreshOnce()

        let malformedRuntime = MonitorRuntimeStore(initialPhase: .live)
        let malformedProvider = AccountUsageProvider(
            runtime: malformedRuntime,
            routeDependencies: try testDependencies(
                official: ScriptedAccountChannel(outcomes: [.success(initializeResponse), .success(accountResponse), .success(.string(combinedMarker)), .success(usageResponse)]),
                bundled: ScriptedAccountChannel(openError: JSONRPCTransportError.lifecycleUnavailable)
            ),
            diagnosticRecorder: { category, fields in recorder.record(category: category, fields: fields) }
        )
        await malformedProvider.refreshOnce()

        let emitted = recorder.events()
        XCTAssertTrue(emitted.contains(where: { $0.fields["event"] == "accountRefreshFallback" }))
        XCTAssertTrue(emitted.contains(where: { $0.fields["event"] == "accountRefreshSucceeded" && $0.fields["route"] == "bundledStdio" }))
        XCTAssertTrue(emitted.contains(where: { $0.fields["event"] == "accountRefresh" && $0.fields["stage"] == "responseDecode" && $0.fields["reason"] == "responseIncompatible" }))
        let emittedText = emitted.flatMap { $0.fields.values }.joined(separator: "\n")
        for marker in markers { XCTAssertFalse(emittedText.contains(marker), "Leaked marker: \(marker)") }
        let allowedKeys: Set<String> = ["event", "account", "rateLimits", "usage", "degraded", "route", "stage", "reason", "nextRoute"]
        XCTAssertTrue(emitted.allSatisfy { Set($0.fields.keys).isSubset(of: allowedKeys) })
    }

    private func officialDiagnostic(outcomes: [ScriptedAccountChannel.Outcome]) async throws -> [String: String] {
        let channel = ScriptedAccountChannel(outcomes: outcomes)
        return try await officialDiagnostic(channel: channel)
    }

    private func officialDiagnostic(channel: ScriptedAccountChannel) async throws -> [String: String] {
        try await diagnostic(official: channel, bundled: ScriptedAccountChannel(openError: JSONRPCTransportError.lifecycleUnavailable), expectedRoute: "officialSocket")
    }

    private func bundledDiagnostic(outcomes: [ScriptedAccountChannel.Outcome]) async throws -> [String: String] {
        try await bundledDiagnostic(channel: ScriptedAccountChannel(outcomes: outcomes))
    }

    private func bundledDiagnostic(channel: ScriptedAccountChannel) async throws -> [String: String] {
        try await diagnostic(official: ScriptedAccountChannel(openError: JSONRPCTransportError.requestTimedOut), bundled: channel, expectedRoute: "bundledStdio")
    }

    private func diagnostic(official: ScriptedAccountChannel, bundled: ScriptedAccountChannel, expectedRoute: String) async throws -> [String: String] {
        try await diagnostic(dependencies: testDependencies(official: official, bundled: bundled), expectedRoute: expectedRoute)
    }

    private func diagnostic(dependencies: AccountUsageProvider.RouteDependencies, expectedRoute: String) async -> [String: String] {
        let recorder = EmittedAccountDiagnosticRecorder()
        let provider = AccountUsageProvider(
            runtime: MonitorRuntimeStore(initialPhase: .live),
            routeDependencies: dependencies,
            diagnosticRecorder: { category, fields in recorder.record(category: category, fields: fields) }
        )
        await provider.refreshOnce()
        guard let fields = recorder.events().first(where: { $0.fields["event"] == "accountRefresh" && $0.fields["route"] == expectedRoute })?.fields else {
            XCTFail("Expected production-emitted account diagnostic for \(expectedRoute)")
            return [:]
        }
        return fields
    }

    private static func makeClient(channel: ScriptedAccountChannel) throws -> JSONRPCClient {
        JSONRPCClient(channel: channel, binding: try JSONRPCClientBinding(descriptor: AccountUsageProvider.descriptor))
    }

    private func testDependencies(
        official: ScriptedAccountChannel,
        bundled: ScriptedAccountChannel,
        officialSocketResolver: (@Sendable () throws -> SocketPathCapability)? = nil,
        officialEndpoint: (@Sendable (SocketPathCapability) throws -> UnixSocketWebSocketEndpoint)? = nil,
        bundledExecutableResolver: (@Sendable () throws -> URL)? = nil
    ) throws -> AccountUsageProvider.RouteDependencies {
        let socket = try AccountSocketFixture()
        return .init(
            officialSocketResolver: officialSocketResolver ?? { try socket.capability() },
            officialEndpoint: officialEndpoint ?? { try UnixSocketWebSocketEndpoint(capability: $0) },
            officialClient: { _ in try Self.makeClient(channel: official) },
            bundledExecutableResolver: bundledExecutableResolver ?? { URL(fileURLWithPath: "/private/tmp/codex-monitor-account-test") },
            bundledClient: { _ in try Self.makeClient(channel: bundled) }
        )
    }

    private func initialize() -> JSONValue { .object(["codexHome": .string("/tmp"), "platformFamily": .string("mac"), "platformOs": .string("macOS"), "userAgent": .string("test")]) }
    private func account() -> JSONValue { .object(["account": .object(["type": .string("chatgpt"), "email": .string("fake-gate2@example.test"), "planType": .string("plus")])]) }
    private func limits() -> JSONValue { .object(["rateLimits": .object(["primary": .object(["usedPercent": .number(10)])])]) }
    private func usage() -> JSONValue { .object(["summary": .object(["lifetimeTokens": .number(1)])]) }
}

private final class AccountSocketFixture: @unchecked Sendable {
    private let directory: String
    private let path: String
    private var fd: Int32 = -1

    init() throws {
        var template = Array("/private/tmp/codex-monitor-account.XXXXXX".utf8CString)
        guard let created = mkdtemp(&template) else { throw POSIXError(.ENOSPC) }
        directory = String(cString: created)
        path = directory + "/app-server.sock"
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENFILE) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        _ = path.withCString { source in withUnsafeMutablePointer(to: &address.sun_path) { destination in strcpy(UnsafeMutableRawPointer(destination).assumingMemoryBound(to: CChar.self), source) } }
        guard withUnsafePointer(to: &address, { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }) == 0 else { throw POSIXError(.EADDRINUSE) }
        chmod(path, 0o600)
    }

    deinit { if fd >= 0 { Darwin.close(fd) }; unlink(path); rmdir(directory) }

    func capability() throws -> SocketPathCapability {
        try OfficialSocketResolver(testSocketPath: { self.path }).resolveTestSocket()
    }
}

private final class EmittedAccountDiagnosticRecorder: @unchecked Sendable {
    struct Event { let category: MonitorDiagnosticCategory; let fields: [String: String] }
    private let lock = NSLock()
    private var stored: [Event] = []

    func record(category: MonitorDiagnosticCategory, fields: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        stored.append(Event(category: category, fields: fields))
    }

    func events() -> [Event] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}

private actor ScriptedAccountChannel: JSONRPCByteChannel {
    enum Outcome { case success(JSONValue), failure }
    private var outcomes: [Outcome]
    private var frames: [JSONRPCFrame] = []
    private var closed = false
    private var opened = false
    private let openError: Error?

    init(outcomes: [Outcome] = [], openError: Error? = nil) { self.outcomes = outcomes; self.openError = openError }
    func open() async throws { if let openError { throw openError }; opened = true }
    func send(_ frame: JSONRPCFrame) async throws {
        guard let data = frame.data, let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else { return }
        guard !outcomes.isEmpty else { return }
        let outcome = outcomes.removeFirst()
        let response: JSONRPCResponse
        switch outcome {
        case .success(let value): response = JSONRPCResponse(id: request.id, result: value)
        case .failure: response = JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32000, message: "RAW_SERVER_GATE2_DO_NOT_LEAK"))
        }
        frames.append(JSONRPCFrame(kind: .text, data: try JSONEncoder().encode(response)))
    }
    func receive() async throws -> JSONRPCFrame? {
        while frames.isEmpty && !closed { try? await Task.sleep(for: .milliseconds(1)) }
        return frames.isEmpty ? nil : frames.removeFirst()
    }
    func close() async { closed = true }
    func didOpen() -> Bool { opened }
}
