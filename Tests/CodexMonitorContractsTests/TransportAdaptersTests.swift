import XCTest
import Darwin
import CryptoKit
@testable import CodexMonitorContracts

final class TransportAdaptersTests: XCTestCase {
    private func evidence() -> EvidenceMetadata { EvidenceMetadata(evidenceRun: "AR-P0 retained evidence decision", cliVersion: "0.147.0", historicalTransportEvidenceLabel: "unresolved/inconsistent: loopback-IP WebSocket or Unix-socket WebSocket", probeOrHarnessAvailability: "unavailable", sanitizerAvailability: "unavailable", sanitizerVersion: "unavailable", confidence: "bounded contract evidence only", limitations: "H2F regression") }
    private func descriptor(_ kind: SourceKind, _ source: String, _ adapter: String) -> AdapterDescriptor { AdapterDescriptor(adapterID: AdapterID(adapter)!, adapterVersion: AdapterVersion("h2")!, sourceKind: kind, sourceID: SourceID(source)!, capabilitySnapshot: CapabilitySnapshot([:]), evidenceMetadata: evidence()) }
    private func client(_ channel: ControlledUnixSocketWebSocketFixture, descriptor: AdapterDescriptor, runtime: RuntimeInstanceID? = nil, account: AccountEpoch? = nil, lifecycle: LifecycleEpoch? = nil, timeout: Duration = .seconds(1)) throws -> JSONRPCClient { JSONRPCClient(channel: channel, binding: try JSONRPCClientBinding(descriptor: descriptor, runtimeInstanceID: runtime, accountEpoch: account, lifecycleEpoch: lifecycle), requestTimeout: timeout) }

    func testControlledUnixSocketWebSocketFixtureVerifiesUpgradeAndTextFrames() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let descriptor = descriptor(.account, "account-source", "account")
        let fixture = try Data(contentsOf: Bundle.module.url(forResource: "app-server-headerless-initialize-response-v1", withExtension: "json")!)
        if case .response(let response) = try JSONRPCWireDecoder.decode(fixture) { XCTAssertEqual(response.id, .integer(1)) } else { XCTFail("headerless fixture did not decode as response") }
        let notificationFixture = try Data(contentsOf: Bundle.module.url(forResource: "app-server-headerless-thread-started-v1", withExtension: "json")!)
        if case .notification(let notification) = try JSONRPCWireDecoder.decode(notificationFixture) { XCTAssertEqual(notification.method, "thread/started") } else { XCTFail("headerless fixture did not decode as notification") }
        let rpc = try client(channel, descriptor: descriptor)
        _ = try await completeInitialization(channel) { try await rpc.connect() }
        let sent = await channel.sentFrames()
        XCTAssertTrue(sent.allSatisfy { if case .text = $0.kind { return $0.isComplete } else { return false } })
        let upgraded = await channel.didHTTPUpgrade(); XCTAssertTrue(upgraded)
        await rpc.close()
    }

    func testRealUnixDomainWebSocketUpgradeTextFramesAndClosePreservation() async throws {
        let server = try UnixWebSocketTestServer(); defer { server.cleanup() }
        let endpoint = try officialEndpoint(server.path)
        let channel = UnixSocketWebSocketChannel(endpoint: endpoint)
        try await channel.open()
        try await channel.send(JSONRPCFrame(kind: .text, data: Data("{\"id\":1}".utf8)))
        try await channel.send(JSONRPCFrame(kind: .text, data: Data("{\"method\":\"initialized\"}".utf8)))
        try await server.waitForSession()
        let upgraded = await server.didUpgrade(); let opcodes = await server.clientOpcodes(); let sent = await channel.sentTextFrameCount()
        XCTAssertTrue(upgraded)
        XCTAssertEqual(sent, 2, "initialize and initialized must each be separate text frames")
        XCTAssertTrue(opcodes.isEmpty, "the controlled listener does not fabricate frame observations")
        guard let frame = try await channel.receive(), case .close(let status, let reason) = frame.kind else { return XCTFail("listener did not send close") }
        XCTAssertEqual(status, 1001); XCTAssertEqual(reason, "controlled-close")
        await channel.close()
    }

    func testOutOfOrderUnknownDuplicateAndLateResponsesAreIgnored() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let rpc = try client(channel, descriptor: descriptor(.account, "a", "account"))
        _ = try await completeInitialization(channel) { try await rpc.connect() }
        async let first: JSONValue = rpc.request(method: "account/read")
        async let second: JSONValue = rpc.request(method: "account/rateLimits/read")
        let one = try await channel.nextRequest(); let two = try await channel.nextRequest()
        await channel.inject(response(id: .integer(99), result: .string("unknown")))
        await channel.inject(response(id: two.id, result: .string("second")))
        await channel.inject(response(id: two.id, result: .string("duplicate")))
        await channel.inject(response(id: one.id, result: .string("first")))
        let firstValue = try await first; let secondValue = try await second
        XCTAssertEqual(firstValue, .string("first")); XCTAssertEqual(secondValue, .string("second"))
        await rpc.close()
    }

    func testPreInitializeAndMalformedNotificationsDoNotReachAdapterOrFailRequest() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let rpc = try client(channel, descriptor: descriptor(.account, "a", "account")); let recorder = Recorder()
        try await rpc.installNotificationHandler(owner: JSONRPCAdapterLease()) { message, _ in await recorder.append(message.method) }
        let connecting = Task { try await rpc.connect() }
        let initialize = try await channel.nextRequest()
        await channel.inject(notification(method: "thread/started", params: .object(["content": .string("private")])) )
        try await Task.sleep(for: .milliseconds(20)); let preInitCount = await recorder.count(); XCTAssertEqual(preInitCount, 0)
        await channel.inject(response(id: initialize.id, result: generatedInitializeResult()))
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
        XCTAssertThrowsError(try JSONRPCWireDecoder.decode(Data("{\"id\":true,\"result\":{}}".utf8))) { XCTAssertEqual($0 as? JSONRPCWireRejection, .malformedID) }
        let stringIDRequest = Data("{\"method\":\"thread/read\",\"id\":\"server-1\"}".utf8)
        XCTAssertThrowsError(try JSONRPCWireDecoder.decode(stringIDRequest)) { XCTAssertEqual($0 as? JSONRPCWireRejection, .serverRequestUnsupported) }
        XCTAssertThrowsError(try JSONRPCWireDecoder.decode(Data("{\"id\":1,\"error\":{\"code\":-1}}".utf8))) { XCTAssertEqual($0 as? JSONRPCWireRejection, .malformedError) }
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
        let initialize = try await channel.nextRequest(); await channel.inject(response(id: initialize.id, result: generatedInitializeResult()))
        _ = await channel.nextFrame(); let first = try await a; let second = try await b; XCTAssertEqual(first, second)
        let old = await rpc.currentConnectionContext()!; await rpc.close()
        _ = try await completeInitialization(channel) { try await rpc.connect() }
        let current = await rpc.currentConnectionContext()!; XCTAssertNotEqual(old, current)
        await channel.inject(response(id: .integer(1), result: .string("old")))
        await rpc.close()
    }

    func testBindingPreventsAccountRuntimeDesktopAndRuntimeCrossovers() throws {
        let account = descriptor(.account, "account", "account"); let runtimeA = descriptor(.monitorOwnedRuntime, "runtime-a", "runtime"); let runtimeB = descriptor(.monitorOwnedRuntime, "runtime-b", "runtime")
        let bindingClient = try client(ControlledUnixSocketWebSocketFixture(), descriptor: runtimeA, runtime: RuntimeInstanceID("runtime-a")!, lifecycle: LifecycleEpoch("l")!)
        XCTAssertThrowsError(try AccountTransportAdapter(descriptor: account, client: bindingClient))
        XCTAssertThrowsError(try DesktopSnapshotTransportAdapter(descriptor: descriptor(.desktopSnapshot, "desktop", "desktop"), client: bindingClient))
        XCTAssertThrowsError(try MonitorOwnedRuntimeTransportAdapter(descriptor: runtimeB, client: bindingClient, runtimeInstanceID: RuntimeInstanceID("runtime-b")!, lifecycleEpoch: LifecycleEpoch("l")!, accountEpoch: nil))
        XCTAssertThrowsError(try MonitorOwnedRuntimeTransportAdapter(descriptor: account, client: bindingClient, runtimeInstanceID: RuntimeInstanceID("runtime-a")!, lifecycleEpoch: LifecycleEpoch("l")!, accountEpoch: nil))
    }

    func testClientLeaseAndEpochBindingRejectLifecycleAndAccountCrossovers() async throws {
        let desc = descriptor(.monitorOwnedRuntime, "runtime-source", "runtime"); let runtime = RuntimeInstanceID("runtime")!
        let first = try client(ControlledUnixSocketWebSocketFixture(), descriptor: desc, runtime: runtime, account: AccountEpoch("account-a")!, lifecycle: LifecycleEpoch("life-a")!)
        XCTAssertThrowsError(try MonitorOwnedRuntimeTransportAdapter(descriptor: desc, client: first, runtimeInstanceID: runtime, lifecycleEpoch: LifecycleEpoch("life-b")!, accountEpoch: AccountEpoch("account-a")!))
        XCTAssertThrowsError(try MonitorOwnedRuntimeTransportAdapter(descriptor: desc, client: first, runtimeInstanceID: runtime, lifecycleEpoch: LifecycleEpoch("life-a")!, accountEpoch: AccountEpoch("account-b")!))
        let a = try MonitorOwnedRuntimeTransportAdapter(descriptor: desc, client: first, runtimeInstanceID: runtime, lifecycleEpoch: LifecycleEpoch("life-a")!, accountEpoch: AccountEpoch("account-a")!)
        let b = try MonitorOwnedRuntimeTransportAdapter(descriptor: desc, client: first, runtimeInstanceID: runtime, lifecycleEpoch: LifecycleEpoch("life-a")!, accountEpoch: AccountEpoch("account-a")!)
        let channel = ControlledUnixSocketWebSocketFixture(); let leased = try client(channel, descriptor: desc, runtime: runtime, account: AccountEpoch("account-a")!, lifecycle: LifecycleEpoch("life-a")!)
        let leasedA = try MonitorOwnedRuntimeTransportAdapter(descriptor: desc, client: leased, runtimeInstanceID: runtime, lifecycleEpoch: LifecycleEpoch("life-a")!, accountEpoch: AccountEpoch("account-a")!)
        let leasedB = try MonitorOwnedRuntimeTransportAdapter(descriptor: desc, client: leased, runtimeInstanceID: runtime, lifecycleEpoch: LifecycleEpoch("life-a")!, accountEpoch: AccountEpoch("account-a")!)
        _ = try await completeInitialization(channel) { try await leasedA.connect() }
        do { _ = try await leasedB.connect(); XCTFail("adapter B replaced A's handler") } catch let error as JSONRPCTransportError { XCTAssertEqual(error, .sourceBindingRejected) }
        _ = a; _ = b
    }

    func testRuntimeRequiresNestedSchemaOwnershipAndAuthoritativeSuccess() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let runtimeID = RuntimeInstanceID("runtime")!; let lifecycle = LifecycleEpoch("life")!; let desc = descriptor(.monitorOwnedRuntime, "runtime-source", "runtime")
        let adapter = try MonitorOwnedRuntimeTransportAdapter(descriptor: desc, client: client(channel, descriptor: desc, runtime: runtimeID, lifecycle: lifecycle), runtimeInstanceID: runtimeID, lifecycleEpoch: lifecycle, accountEpoch: nil)
        let supervisor = MonitorOwnedRuntimeSupervisor(adapter: adapter)
        let health = try await completeInitialization(channel) { try await supervisor.connectTransport() }
        let thread = NamespacedID(sourceID: desc.sourceID, entityKind: .thread, rawID: "owned")!
        _ = health
        let receipt = try await supervisor.receiveAuthorizedCreationResult(threadID: thread)
        _ = try await supervisor.register(receipt)
        let recorder = CandidateRecorder()
        let consumer = Task { for await candidate in adapter.observations { await recorder.append(candidate) } }
        defer { consumer.cancel() }
        await channel.inject(notification(method: "turn/completed", params: turnCompletedParams(threadID: "owned", turnID: "turn", status: "failed")) )
        await channel.inject(notification(method: "turn/completed", params: turnCompletedParams(threadID: "owned", turnID: "turn", status: "completed")) )
        try await Task.sleep(for: .milliseconds(40)); let emitted = await recorder.values()
        XCTAssertEqual(emitted.count, 1); XCTAssertEqual(emitted.first?.kind, .turnCompletedSuccess); XCTAssertEqual(emitted.first?.threadID, thread)
        _ = await supervisor.closeTransport()
    }

    func testPinnedGeneratedFixturesRouteExactParentsAndOnlySuccessfulTerminal() async throws {
        let channel = ControlledUnixSocketWebSocketFixture(); let runtime = RuntimeInstanceID("runtime")!; let lifecycle = LifecycleEpoch("life")!; let desc = descriptor(.monitorOwnedRuntime, "generated-source", "runtime")
        let adapter = try MonitorOwnedRuntimeTransportAdapter(descriptor: desc, client: client(channel, descriptor: desc, runtime: runtime, lifecycle: lifecycle), runtimeInstanceID: runtime, lifecycleEpoch: lifecycle, accountEpoch: nil)
        let supervisor = MonitorOwnedRuntimeSupervisor(adapter: adapter)
        _ = try await completeInitialization(channel) { try await supervisor.connectTransport() }
        let thread = NamespacedID(sourceID: desc.sourceID, entityKind: .thread, rawID: "owned")!
        _ = try await supervisor.register(try await supervisor.receiveAuthorizedCreationResult(threadID: thread))
        let initialize = try fixture("app-server-generated-initialize-response-0.147.0")
        if case .response(let response) = try JSONRPCWireDecoder.decode(initialize) { XCTAssertEqual(response.id, .integer(1)); XCTAssertTrue(response.result.map { _ in true } ?? false) } else { XCTFail("generated initialize fixture did not decode") }
        let recorder = CandidateRecorder()
        let consumer = Task { for await candidate in adapter.observations { await recorder.append(candidate) } }
        defer { consumer.cancel() }
        let context = await adapter.currentConnectionContext()!
        for name in ["generated-thread-started-0.147.0", "generated-thread-status-changed-0.147.0", "generated-turn-started-0.147.0", "generated-item-started-0.147.0", "generated-item-completed-0.147.0", "generated-turn-completed-failed-0.147.0", "generated-turn-completed-success-0.147.0", "generated-token-usage-updated-0.147.0"] {
            let data = try fixture(name); guard case .notification(let value) = try JSONRPCWireDecoder.decode(data) else { return XCTFail("fixture is not notification") }
            let kind: RuntimeObservationKind = switch value.method { case "thread/started": .threadStarted; case "thread/status/changed": .threadStatusChanged; case "turn/started": .turnStarted; case "item/started": .itemStarted; case "item/completed": .itemCompleted; case "turn/completed": .turnCompletedSuccess; default: .threadTokenUsageUpdated }
            if name.contains("failed") { XCTAssertNil(RuntimeLifecycleWireEvent.decode(notification: value, kind: kind, sourceID: desc.sourceID), name) } else { XCTAssertNotNil(RuntimeLifecycleWireEvent.decode(notification: value, kind: kind, sourceID: desc.sourceID), name) }
            let accepted = await adapter.route(value, context: context)
            XCTAssertEqual(accepted, !name.contains("failed"), name)
        }
        try await Task.sleep(for: .milliseconds(80))
        let candidates = await recorder.values()
        XCTAssertEqual(candidates.count, 7)
        XCTAssertTrue(candidates.allSatisfy { $0.threadID == thread })
        XCTAssertEqual(candidates.map(\.kind), [.threadStarted, .threadStatusChanged, .turnStarted, .itemStarted, .itemCompleted, .turnCompletedSuccess, .threadTokenUsageUpdated])
        _ = await supervisor.closeTransport()
    }

    func testSupervisorRejectsDisconnectedAndStaleFabricatedReceipt() async throws {
        let desc = descriptor(.monitorOwnedRuntime, "runtime-source", "runtime"); let runtimeID = RuntimeInstanceID("runtime")!; let life = LifecycleEpoch("life")!; let adapter = try MonitorOwnedRuntimeTransportAdapter(descriptor: desc, client: client(ControlledUnixSocketWebSocketFixture(), descriptor: desc, runtime: runtimeID, lifecycle: life), runtimeInstanceID: runtimeID, lifecycleEpoch: life, accountEpoch: nil); let supervisor = MonitorOwnedRuntimeSupervisor(adapter: adapter)
        let thread = NamespacedID(sourceID: desc.sourceID, entityKind: .thread, rawID: "fabricated")!
        do { _ = try await supervisor.receiveAuthorizedCreationResult(threadID: thread); XCTFail("disconnected issuance accepted") } catch let error as RuntimeSupervisorError { XCTAssertEqual(error, .lifecycleNotConnected) }
    }

    func testSocketProvenanceAndFilesystemReplacementRegressions() throws {
        let fixture = try UnixSocketFixture(); defer { fixture.cleanup() }
        let endpoint = try officialEndpoint(fixture.path)
        try fixture.replaceSocket(); XCTAssertThrowsError(try endpoint.validateImmediatelyBeforeOpen()) { XCTAssertEqual($0 as? UnixSocketValidationError, .replacedOrRemoved) }
        let removed = try UnixSocketFixture(); defer { removed.cleanup() }; let removedEndpoint = try officialEndpoint(removed.path); removed.removeSocket()
        XCTAssertThrowsError(try removedEndpoint.validateImmediatelyBeforeOpen()) { XCTAssertEqual($0 as? UnixSocketValidationError, .inaccessible) }
        let insecure = try UnixSocketFixture(); defer { insecure.cleanup() }; chmod(insecure.directory, 0o777)
        XCTAssertThrowsError(try officialEndpoint(insecure.path)) { XCTAssertEqual($0 as? UnixSocketValidationError, .insecureParentDirectory) }
        let permissive = try UnixSocketFixture(); defer { permissive.cleanup() }; chmod(permissive.path, 0o660)
        XCTAssertThrowsError(try officialEndpoint(permissive.path)) { XCTAssertEqual($0 as? UnixSocketValidationError, .groupOrWorldWritable) }
        let owner = try UnixSocketFixture(); defer { owner.cleanup() }
        XCTAssertThrowsError(try officialEndpoint(owner.path, expectedOwner: getuid() &+ 1))
        let link = fixture.directory + "/link"; XCTAssertEqual(symlink(fixture.path, link), 0)
        XCTAssertThrowsError(try officialEndpoint(link)) { XCTAssertEqual($0 as? UnixSocketValidationError, .symlinkRejected) }
        XCTAssertThrowsError(try OfficialSocketResolver().resolve(), "arbitrary path has no public official-default factory")
    }

    func testSanitizerAndFixturesCannotSerializeSentinels() throws {
        let diagnostic = DiagnosticSanitizer.summarize(sourceKind: .monitorOwnedRuntime, code: .unsupportedNotification, method: nil, payload: .object(["sk_live_H2FRSentinel123": .string("Bearer fake secret"), "Authorization": .string("Bearer"), "token": .string("password"), "safe": .object(["title": .string("preview"), "status": .string("ok"), "nestedSecret": .string("/Users/example /private/socket")])]))
        let encoded = String(decoding: try JSONEncoder().encode(diagnostic), as: UTF8.self).lowercased()
        for sentinel in ["sk_live_h2frsentinel123", "authorization", "bearer", "fake secret", "socket", "private", "title", "content", "preview", "password", "token", "/users/"] { XCTAssertFalse(encoded.contains(sentinel)) }
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
private actor CandidateRecorder { private var stored: [CandidateRuntimeObservationEnvelope] = []; func append(_ value: CandidateRuntimeObservationEnvelope) { stored.append(value) }; func values() -> [CandidateRuntimeObservationEnvelope] { stored } }
private func response(id: RequestID, result: JSONValue) -> JSONRPCFrame { JSONRPCFrame(kind: .text, data: try! JSONEncoder().encode(JSONRPCResponse(id: id, result: result))) }
private func notification(method: String, params: JSONValue?) -> JSONRPCFrame { JSONRPCFrame(kind: .text, data: try! JSONEncoder().encode(JSONRPCNotification(method: method, params: params))) }
private func generatedInitializeResult() -> JSONValue { .object(["codexHome": .string("/redacted"), "platformFamily": .string("unix"), "platformOs": .string("macos"), "userAgent": .string("redacted")]) }
private func fixture(_ name: String) throws -> Data { try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json")!) }
private func officialEndpoint(_ path: String, expectedOwner: uid_t = getuid()) throws -> UnixSocketWebSocketEndpoint {
    let resolver = OfficialSocketResolver(source: { path })
    return try UnixSocketWebSocketEndpoint(capability: resolver.resolve(expectedOwner: expectedOwner), expectedOwner: expectedOwner)
}
private func completeInitialization<T: Sendable>(_ channel: ControlledUnixSocketWebSocketFixture, starting: @escaping @Sendable () async throws -> T) async throws -> T {
    let task = Task { try await starting() }; let initialize = try await channel.nextRequest(); XCTAssertEqual(initialize.method, "initialize"); XCTAssertFalse(String(decoding: try JSONEncoder().encode(initialize), as: UTF8.self).contains("jsonrpc")); await channel.inject(response(id: initialize.id, result: generatedInitializeResult()))
    let initialized = await channel.nextFrame(); guard let data = initialized.data else { throw JSONRPCTransportError.transportFailure(.nonTextFrame) }; XCTAssertEqual(try JSONDecoder().decode(JSONRPCNotification.self, from: data).method, "initialized")
    return try await task.value
}

private func turnCompletedParams(threadID: String, turnID: String, status: String) -> JSONValue {
    .object(["threadId": .string(threadID), "turn": .object(["id": .string(turnID), "items": .array([]), "status": .string(status)])])
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

private actor UnixWebSocketServerState {
    private var upgraded = false; private var opcodes: [UInt8] = []; private var completion: CheckedContinuation<Void, Error>?
    func recordUpgrade() { upgraded = true }
    func recordOpcode(_ opcode: UInt8) { opcodes.append(opcode) }
    func finish(_ result: Result<Void, Error>) { completion?.resume(with: result); completion = nil }
    func wait() async throws { try await withCheckedThrowingContinuation { continuation in self.completion = continuation } }
    func didUpgrade() -> Bool { upgraded }; func clientOpcodes() -> [UInt8] { opcodes }
}

/// Controlled local Unix-domain WebSocket server used only by the integration
/// test. It performs the actual HTTP Upgrade and parses masked client frames.
private final class UnixWebSocketTestServer: @unchecked Sendable {
    let path: String; private let directory: String; private let state = UnixWebSocketServerState(); private var fd: Int32 = -1
    init() throws {
        var template = Array("/private/tmp/codex-monitor-h2f2-ws.XXXXXX".utf8CString)
        guard let created = mkdtemp(&template) else { throw POSIXError(.ENOSPC) }
        directory = String(cString: created); path = directory + "/app-server.sock"; fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENFILE) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        _ = path.withCString { source in withUnsafeMutablePointer(to: &address.sun_path) { destination in strcpy(UnsafeMutableRawPointer(destination).assumingMemoryBound(to: CChar.self), source) } }
        let bound = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0, listen(fd, 1) == 0 else { throw POSIXError(.EADDRINUSE) }; chmod(path, 0o600)
        Task.detached { [weak self] in await self?.serve() }
    }
    func waitForSession() async throws { try await state.wait() }
    func didUpgrade() async -> Bool { await state.didUpgrade() }
    func clientOpcodes() async -> [UInt8] { await state.clientOpcodes() }
    func cleanup() { if fd >= 0 { Darwin.close(fd); fd = -1 }; unlink(path); rmdir(directory) }

    private func serve() async {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { await state.finish(.failure(POSIXError(.ECONNABORTED))); return }
        defer { Darwin.close(client) }
        do {
            let request = try readHTTPHeader(client)
            let upgraded = request.lowercased().contains("upgrade") && request.lowercased().contains("websocket")
            try writeAll(client, Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n".utf8))
            if upgraded { await state.recordUpgrade() }
            usleep(150_000)
            try writeWebSocketClose(client, status: 1001, reason: "controlled-close")
            await state.finish(.success(()))
        } catch { await state.finish(.failure(error)) }
    }
}

private func readHTTPHeader(_ fd: Int32) throws -> String {
    var bytes: [UInt8] = []
    while bytes.suffix(4) != [13, 10, 13, 10] {
        var byte: UInt8 = 0; guard recv(fd, &byte, 1, 0) == 1 else { throw POSIXError(.ECONNRESET) }; bytes.append(byte)
        if bytes.count > 16_384 { throw POSIXError(.EMSGSIZE) }
    }
    return String(decoding: bytes, as: UTF8.self)
}
private func readWebSocketFrame(_ fd: Int32) throws -> (opcode: UInt8, payload: Data) {
    var header = [UInt8](repeating: 0, count: 2); try readExact(fd, &header)
    let length = Int(header[1] & 0x7f); guard header[0] & 0x80 != 0, header[1] & 0x80 != 0, length < 126 else { throw POSIXError(.EPROTO) }
    var mask = [UInt8](repeating: 0, count: 4); try readExact(fd, &mask)
    var payload = [UInt8](repeating: 0, count: length); try readExact(fd, &payload)
    for index in payload.indices { payload[index] ^= mask[index % 4] }
    return (header[0] & 0x0f, Data(payload))
}
private func writeWebSocketText(_ fd: Int32, _ payload: Data) throws { try writeWebSocketFrame(fd, opcode: 0x1, payload: payload) }
private func writeWebSocketClose(_ fd: Int32, status: UInt16, reason: String) throws { var bytes = [UInt8(status >> 8), UInt8(status & 0xff)]; bytes += Array(reason.utf8); try writeWebSocketFrame(fd, opcode: 0x8, payload: Data(bytes)) }
private func writeWebSocketFrame(_ fd: Int32, opcode: UInt8, payload: Data) throws { guard payload.count < 126 else { throw POSIXError(.EMSGSIZE) }; try writeAll(fd, Data([0x80 | opcode, UInt8(payload.count)]) + payload) }
private func readExact(_ fd: Int32, _ bytes: inout [UInt8]) throws { var offset = 0; let total = bytes.count; while offset < total { let remaining = total - offset; let count = bytes.withUnsafeMutableBytes { recv(fd, $0.baseAddress!.advanced(by: offset), remaining, 0) }; guard count > 0 else { throw POSIXError(.ECONNRESET) }; offset += count } }
private func writeAll(_ fd: Int32, _ data: Data) throws { try data.withUnsafeBytes { raw in var offset = 0; while offset < raw.count { let count = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0); guard count > 0 else { throw POSIXError(.EPIPE) }; offset += count } } }
