import XCTest
import Darwin
@testable import CodexMonitorContracts

final class TransportAdaptersTests: XCTestCase {
    private func evidence() -> EvidenceMetadata { EvidenceMetadata(evidenceRun: "AR-P0 retained evidence decision", cliVersion: "0.147.0", historicalTransportEvidenceLabel: "unresolved/inconsistent: loopback-IP WebSocket or Unix-socket WebSocket", probeOrHarnessAvailability: "unavailable", sanitizerAvailability: "unavailable", sanitizerVersion: "unavailable", confidence: "bounded contract evidence only", limitations: "H2F regression") }
    private func descriptor(_ kind: SourceKind, _ source: String, _ adapter: String) -> AdapterDescriptor { AdapterDescriptor(adapterID: AdapterID(adapter)!, adapterVersion: AdapterVersion("h2")!, sourceKind: kind, sourceID: SourceID(source)!, capabilitySnapshot: CapabilitySnapshot([:]), evidenceMetadata: evidence()) }
    private func client(_ channel: ControlledUnixSocketWebSocketFixture, descriptor: AdapterDescriptor, runtime: RuntimeInstanceID? = nil, timeout: Duration = .seconds(1)) throws -> JSONRPCClient { JSONRPCClient(channel: channel, binding: try JSONRPCClientBinding(descriptor: descriptor, runtimeInstanceID: runtime), requestTimeout: timeout) }

    func testControlledUnixSocketWebSocketFixtureVerifiesUpgradeAndTextFrames() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let descriptor = descriptor(.account, "account-source", "account")
        let fixture = try Data(contentsOf: Bundle.module.url(forResource: "app-server-headerless-initialize-response-v1", withExtension: "json")!)
        if case .response(let response) = try JSONRPCWireDecoder.decode(fixture) { XCTAssertEqual(response.id, 1) } else { XCTFail("headerless fixture did not decode as response") }
        let notificationFixture = try Data(contentsOf: Bundle.module.url(forResource: "app-server-headerless-thread-started-v1", withExtension: "json")!)
        if case .notification(let notification) = try JSONRPCWireDecoder.decode(notificationFixture) { XCTAssertEqual(notification.method, "thread/started") } else { XCTFail("headerless fixture did not decode as notification") }
        let rpc = try client(channel, descriptor: descriptor)
        _ = try await completeInitialization(channel) { try await rpc.connect() }
        let sent = await channel.sentFrames()
        XCTAssertTrue(sent.allSatisfy { if case .text = $0.kind { return $0.isComplete } else { return false } })
        let upgraded = await channel.didHTTPUpgrade(); XCTAssertTrue(upgraded)
        await rpc.close()
    }

    func testOutOfOrderUnknownDuplicateAndLateResponsesAreIgnored() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let rpc = try client(channel, descriptor: descriptor(.account, "a", "account"))
        _ = try await completeInitialization(channel) { try await rpc.connect() }
        async let first: JSONValue = rpc.request(method: "account/read")
        async let second: JSONValue = rpc.request(method: "account/rateLimits/read")
        let one = try await channel.nextRequest(); let two = try await channel.nextRequest()
        await channel.inject(response(id: 99, result: .string("unknown")))
        await channel.inject(response(id: two.id, result: .string("second")))
        await channel.inject(response(id: two.id, result: .string("duplicate")))
        await channel.inject(response(id: one.id, result: .string("first")))
        let firstValue = try await first; let secondValue = try await second
        XCTAssertEqual(firstValue, .string("first")); XCTAssertEqual(secondValue, .string("second"))
        await rpc.close()
    }

    func testPreInitializeAndMalformedNotificationsDoNotReachAdapterOrFailRequest() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let rpc = try client(channel, descriptor: descriptor(.account, "a", "account")); let recorder = Recorder()
        await rpc.setNotificationHandler { message, _ in await recorder.append(message.method) }
        let connecting = Task { try await rpc.connect() }
        let initialize = try await channel.nextRequest()
        await channel.inject(notification(method: "thread/started", params: .object(["content": .string("private")])) )
        try await Task.sleep(for: .milliseconds(20)); let preInitCount = await recorder.count(); XCTAssertEqual(preInitCount, 0)
        await channel.inject(response(id: initialize.id, result: .object([:])))
        _ = await channel.nextFrame(); _ = try await connecting.value
        async let value: JSONValue = rpc.request(method: "account/read")
        let request = try await channel.nextRequest()
        await channel.inject(JSONRPCFrame(kind: .text, data: Data("{\"method\":7}".utf8)))
        await channel.inject(response(id: request.id, result: .string("ok")))
        let resolved = try await value; let finalCount = await recorder.count(); XCTAssertEqual(resolved, .string("ok")); XCTAssertEqual(finalCount, 0)
        await rpc.close()
    }

    func testTimeoutCancellationBeforeSendAndCloseCleanupAreExactlyOnce() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let rpc = try client(channel, descriptor: descriptor(.account, "a", "account"), timeout: .milliseconds(25))
        _ = try await completeInitialization(channel) { try await rpc.connect() }
        do { _ = try await rpc.request(method: "account/read"); XCTFail("timeout did not fire") } catch let error as JSONRPCTransportError { XCTAssertEqual(error, JSONRPCTransportError.requestTimedOut) }
        _ = try await channel.nextRequest()
        let cancelled = Task { () -> Result<JSONValue, Error> in do { return .success(try await rpc.request(method: "account/read")) } catch { return .failure(error) } }
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        if case .failure(let error as JSONRPCTransportError) = cancelledResult { XCTAssertEqual(error, JSONRPCTransportError.requestCancelled) } else { XCTFail("cancel-before-send accepted") }
        let pending = Task { () -> Result<JSONValue, Error> in do { return .success(try await rpc.request(method: "account/read")) } catch { return .failure(error) } }
        _ = try await channel.nextRequest(); await rpc.close()
        if case .failure(let error as JSONRPCTransportError) = await pending.value { XCTAssertEqual(error, JSONRPCTransportError.connectionClosed) } else { XCTFail("close did not clean pending request") }
    }

    func testServerRequestContradictionAndMalformedIDAreTypedWireRejections() throws {
        let serverRequest = Data("{\"method\":\"thread/read\",\"id\":1}".utf8)
        XCTAssertThrowsError(try JSONRPCWireDecoder.decode(serverRequest)) { XCTAssertEqual($0 as? JSONRPCWireRejection, .serverRequestUnsupported) }
        let contradiction = Data("{\"id\":1,\"result\":{},\"error\":{\"code\":1}}".utf8)
        XCTAssertThrowsError(try JSONRPCWireDecoder.decode(contradiction)) { XCTAssertEqual($0 as? JSONRPCWireRejection, .responseMustContainExactlyOneResultOrError) }
        XCTAssertThrowsError(try JSONRPCWireDecoder.decode(Data("{\"id\":\"wrong\",\"result\":{}}".utf8))) { XCTAssertEqual($0 as? JSONRPCWireRejection, .malformedID) }
    }

    func testBinaryIncompleteAndCloseFramesFailSourceLocally() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let rpc = try client(channel, descriptor: descriptor(.account, "a", "account"))
        _ = try await completeInitialization(channel) { try await rpc.connect() }
        await channel.inject(JSONRPCFrame(kind: .binary, data: Data()))
        try await Task.sleep(for: .milliseconds(20)); let binaryState = await rpc.lifecycleState(); XCTAssertEqual(binaryState, JSONRPCLifecycleState.closed)
        let channel2 = ControlledUnixSocketWebSocketFixture(); let rpc2 = try client(channel2, descriptor: descriptor(.account, "b", "account"))
        _ = try await completeInitialization(channel2) { try await rpc2.connect() }
        await channel2.inject(JSONRPCFrame(kind: .close(status: 1000, reason: "ignored")))
        try await Task.sleep(for: .milliseconds(20)); let closeState = await rpc2.lifecycleState(); XCTAssertEqual(closeState, JSONRPCLifecycleState.closed)
    }

    func testConcurrentConnectIsSingleFlightAndReconnectDropsOldContext() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let rpc = try client(channel, descriptor: descriptor(.account, "a", "account"))
        async let a = rpc.connect(); async let b = rpc.connect()
        let initialize = try await channel.nextRequest(); await channel.inject(response(id: initialize.id, result: .object([:])))
        _ = await channel.nextFrame(); let first = try await a; let second = try await b; XCTAssertEqual(first, second)
        let old = await rpc.currentConnectionContext()!; await rpc.close()
        _ = try await completeInitialization(channel) { try await rpc.connect() }
        let current = await rpc.currentConnectionContext()!; XCTAssertNotEqual(old, current)
        await channel.inject(response(id: 1, result: .string("old")))
        await rpc.close()
    }

    func testBindingPreventsAccountRuntimeDesktopAndRuntimeCrossovers() throws {
        let account = descriptor(.account, "account", "account"); let runtimeA = descriptor(.monitorOwnedRuntime, "runtime-a", "runtime"); let runtimeB = descriptor(.monitorOwnedRuntime, "runtime-b", "runtime")
        let bindingClient = try client(ControlledUnixSocketWebSocketFixture(), descriptor: runtimeA, runtime: RuntimeInstanceID("runtime-a")!)
        XCTAssertThrowsError(try AccountTransportAdapter(descriptor: account, client: bindingClient))
        XCTAssertThrowsError(try DesktopSnapshotTransportAdapter(descriptor: descriptor(.desktopSnapshot, "desktop", "desktop"), client: bindingClient))
        XCTAssertThrowsError(try MonitorOwnedRuntimeTransportAdapter(descriptor: runtimeB, client: bindingClient, runtimeInstanceID: RuntimeInstanceID("runtime-b")!, lifecycleEpoch: LifecycleEpoch("l")!, accountEpoch: nil))
        XCTAssertThrowsError(try MonitorOwnedRuntimeTransportAdapter(descriptor: account, client: bindingClient, runtimeInstanceID: RuntimeInstanceID("runtime-a")!, lifecycleEpoch: LifecycleEpoch("l")!, accountEpoch: nil))
    }

    func testRuntimeRequiresNestedSchemaOwnershipAndAuthoritativeSuccess() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let runtimeID = RuntimeInstanceID("runtime")!; let lifecycle = LifecycleEpoch("life")!; let desc = descriptor(.monitorOwnedRuntime, "runtime-source", "runtime")
        let adapter = try MonitorOwnedRuntimeTransportAdapter(descriptor: desc, client: client(channel, descriptor: desc, runtime: runtimeID), runtimeInstanceID: runtimeID, lifecycleEpoch: lifecycle, accountEpoch: nil)
        let supervisor = MonitorOwnedRuntimeSupervisor(adapter: adapter)
        let health = try await completeInitialization(channel) { try await supervisor.connectTransport() }
        let thread = NamespacedID(sourceID: desc.sourceID, entityKind: .thread, rawID: "owned")!
        let receiptProvenance = Provenance(sourceID: desc.sourceID, sourceKind: .monitorOwnedRuntime, adapterID: desc.adapterID, adapterVersion: desc.adapterVersion, runtimeInstanceID: runtimeID, observationMode: .live, authority: .partial, observedAt: Date(), freshness: Freshness(state: .fresh, assessedAt: Date(), observedAt: Date()), connectionEpoch: health.provenance.connectionEpoch, lifecycleEpoch: lifecycle, capability: .threadStartObservation, evidence: evidence(), origin: .adapter)
        // Preserve provenance timestamp invariant for the receipt.
        let now = Date(); let receipt = MonitorCreatedThreadReceipt(threadID: thread, creationProvenance: Provenance(sourceID: desc.sourceID, sourceKind: .monitorOwnedRuntime, adapterID: desc.adapterID, adapterVersion: desc.adapterVersion, runtimeInstanceID: runtimeID, observationMode: .live, authority: .partial, observedAt: now, freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now), connectionEpoch: health.provenance.connectionEpoch, lifecycleEpoch: lifecycle, capability: .threadStartObservation, evidence: evidence(), origin: .adapter)!)
        _ = receiptProvenance
        _ = try await supervisor.register(receipt)
        var iterator = adapter.observations.makeAsyncIterator()
        await channel.inject(notification(method: "turn/completed", params: .object(["thread": .object(["id": .string("owned")]), "turn": .object(["id": .string("turn"), "status": .string("failed")])])) )
        await channel.inject(notification(method: "turn/completed", params: .object(["thread": .object(["id": .string("owned")]), "turn": .object(["id": .string("turn"), "status": .string("completed")])])) )
        let candidate = await iterator.next(); XCTAssertEqual(candidate?.kind, .turnCompletedSuccess); XCTAssertEqual(candidate?.threadID, thread)
        _ = await supervisor.closeTransport()
    }

    func testSupervisorRejectsDisconnectedAndStaleFabricatedReceipt() async throws {
        let desc = descriptor(.monitorOwnedRuntime, "runtime-source", "runtime"); let runtimeID = RuntimeInstanceID("runtime")!; let adapter = try MonitorOwnedRuntimeTransportAdapter(descriptor: desc, client: client(ControlledUnixSocketWebSocketFixture(), descriptor: desc, runtime: runtimeID), runtimeInstanceID: runtimeID, lifecycleEpoch: LifecycleEpoch("life")!, accountEpoch: nil); let supervisor = MonitorOwnedRuntimeSupervisor(adapter: adapter)
        let now = Date(); let receipt = MonitorCreatedThreadReceipt(threadID: NamespacedID(sourceID: desc.sourceID, entityKind: .thread, rawID: "fabricated")!, creationProvenance: Provenance(sourceID: desc.sourceID, sourceKind: .monitorOwnedRuntime, adapterID: desc.adapterID, adapterVersion: desc.adapterVersion, runtimeInstanceID: runtimeID, observationMode: .live, authority: .partial, observedAt: now, freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now), connectionEpoch: ConnectionEpoch("stale")!, lifecycleEpoch: LifecycleEpoch("life")!, capability: .threadStartObservation, evidence: evidence(), origin: .adapter)!)
        do { _ = try await supervisor.register(receipt); XCTFail("disconnected fabricated receipt accepted") } catch let error as RuntimeSupervisorError { XCTAssertEqual(error, .lifecycleNotConnected) }
    }

    func testSocketProvenanceAndFilesystemReplacementRegressions() throws {
        let fixture = try UnixSocketFixture(); defer { fixture.cleanup() }
        let endpoint = try UnixSocketWebSocketEndpoint.officialDefault(path: fixture.path)
        try fixture.replaceSocket(); XCTAssertThrowsError(try endpoint.validateImmediatelyBeforeOpen()) { XCTAssertEqual($0 as? UnixSocketValidationError, .replacedOrRemoved) }
        let removed = try UnixSocketFixture(); defer { removed.cleanup() }; let removedEndpoint = try UnixSocketWebSocketEndpoint.officialDefault(path: removed.path); removed.removeSocket()
        XCTAssertThrowsError(try removedEndpoint.validateImmediatelyBeforeOpen()) { XCTAssertEqual($0 as? UnixSocketValidationError, .inaccessible) }
        let insecure = try UnixSocketFixture(); defer { insecure.cleanup() }; chmod(insecure.directory, 0o777)
        XCTAssertThrowsError(try UnixSocketWebSocketEndpoint.officialDefault(path: insecure.path)) { XCTAssertEqual($0 as? UnixSocketValidationError, .insecureParentDirectory) }
        let permissive = try UnixSocketFixture(); defer { permissive.cleanup() }; chmod(permissive.path, 0o660)
        XCTAssertThrowsError(try UnixSocketWebSocketEndpoint.officialDefault(path: permissive.path)) { XCTAssertEqual($0 as? UnixSocketValidationError, .groupOrWorldWritable) }
        let owner = try UnixSocketFixture(); defer { owner.cleanup() }
        XCTAssertThrowsError(try UnixSocketWebSocketEndpoint.officialDefault(path: owner.path, expectedOwner: getuid() &+ 1))
        let link = fixture.directory + "/link"; XCTAssertEqual(symlink(fixture.path, link), 0)
        XCTAssertThrowsError(try UnixSocketWebSocketEndpoint.officialDefault(path: link)) { XCTAssertEqual($0 as? UnixSocketValidationError, .symlinkRejected) }
    }

    func testSanitizerAndFixturesCannotSerializeSentinels() throws {
        let diagnostic = DiagnosticSanitizer.summarize(sourceKind: .monitorOwnedRuntime, code: .unsupportedNotification, method: nil, payload: .object(["Authorization": .string("Bearer fake-secret"), "socketPath": .string("/private/socket"), "safe": .object(["title": .string("private"), "status": .string("ok")])]))
        let encoded = String(decoding: try JSONEncoder().encode(diagnostic), as: UTF8.self).lowercased()
        for sentinel in ["authorization", "bearer", "fake-secret", "socket", "private", "title", "content", "preview", "password", "token"] { XCTAssertFalse(encoded.contains(sentinel)) }
        let fixtureURLs = try FileManager.default.contentsOfDirectory(at: Bundle.module.resourceURL!, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        for url in fixtureURLs { let body = String(decoding: try Data(contentsOf: url), as: UTF8.self).lowercased(); for sentinel in ["authorization", "bearer", "password", "private key", "@", "/users/", "socketpath"] { XCTAssertFalse(body.contains(sentinel), "\(url.lastPathComponent) leaked \(sentinel)") } }
    }
}

/// Controlled Unix-socket WebSocket harness: it models only completed HTTP
/// Upgrade sessions and exposes the exact frame metadata asserted by H2F.
private actor ControlledUnixSocketWebSocketFixture: JSONRPCByteChannel {
    private var inbound: [JSONRPCFrame] = []; private var receiver: CheckedContinuation<JSONRPCFrame?, Never>?; private var sent: [JSONRPCFrame] = []; private var sender: CheckedContinuation<JSONRPCFrame, Never>?; private var upgraded = false
    func open() async throws { upgraded = true }
    func send(_ frame: JSONRPCFrame) async throws { if let sender { self.sender = nil; sender.resume(returning: frame) } else { sent.append(frame) } }
    func receive() async throws -> JSONRPCFrame? { if !inbound.isEmpty { return inbound.removeFirst() }; return await withCheckedContinuation { receiver = $0 } }
    func close() async { receiver?.resume(returning: nil); receiver = nil }
    func inject(_ frame: JSONRPCFrame) { if let receiver { self.receiver = nil; receiver.resume(returning: frame) } else { inbound.append(frame) } }
    func nextFrame() async -> JSONRPCFrame { if !sent.isEmpty { return sent.removeFirst() }; return await withCheckedContinuation { sender = $0 } }
    func nextRequest() async throws -> JSONRPCRequest { let frame = await nextFrame(); guard case .text = frame.kind, let data = frame.data else { throw JSONRPCTransportError.transportFailure(.nonTextFrame) }; return try JSONDecoder().decode(JSONRPCRequest.self, from: data) }
    func sentFrames() -> [JSONRPCFrame] { sent }
    func didHTTPUpgrade() -> Bool { upgraded }
}

private actor Recorder { private var values: [String] = []; func append(_ value: String) { values.append(value) }; func count() -> Int { values.count } }
private func response(id: Int, result: JSONValue) -> JSONRPCFrame { JSONRPCFrame(kind: .text, data: try! JSONEncoder().encode(JSONRPCResponse(id: id, result: result))) }
private func notification(method: String, params: JSONValue?) -> JSONRPCFrame { JSONRPCFrame(kind: .text, data: try! JSONEncoder().encode(JSONRPCNotification(method: method, params: params))) }
private func completeInitialization<T: Sendable>(_ channel: ControlledUnixSocketWebSocketFixture, starting: @escaping @Sendable () async throws -> T) async throws -> T {
    let task = Task { try await starting() }; let initialize = try await channel.nextRequest(); XCTAssertEqual(initialize.method, "initialize"); XCTAssertFalse(String(decoding: try JSONEncoder().encode(initialize), as: UTF8.self).contains("jsonrpc")); await channel.inject(response(id: initialize.id, result: .object([:])))
    let initialized = await channel.nextFrame(); guard let data = initialized.data else { throw JSONRPCTransportError.transportFailure(.nonTextFrame) }; XCTAssertEqual(try JSONDecoder().decode(JSONRPCNotification.self, from: data).method, "initialized")
    return try await task.value
}

private final class UnixSocketFixture {
    let directory: String; let path: String; private var fd: Int32 = -1
    init() throws {
        var template = Array("/private/tmp/codex-monitor-h2f.XXXXXX".utf8CString)
        guard let created = mkdtemp(&template) else { throw POSIXError(.ENOSPC) }
        directory = String(cString: created); path = directory + "/app-server.sock"; try bindSocket()
    }
    func replaceSocket() throws { if fd >= 0 { Darwin.close(fd); fd = -1 }; unlink(path); try bindSocket() }
    func removeSocket() { if fd >= 0 { Darwin.close(fd); fd = -1 }; unlink(path) }
    func cleanup() { if fd >= 0 { Darwin.close(fd) }; unlink(path); rmdir(directory) }
    private func bindSocket() throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { throw POSIXError(.ENFILE) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        _ = path.withCString { source in withUnsafeMutablePointer(to: &address.sun_path) { destination in strcpy(UnsafeMutableRawPointer(destination).assumingMemoryBound(to: CChar.self), source) } }
        let result = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0 else { throw POSIXError(.EADDRINUSE) }; chmod(path, 0o600)
    }
}
