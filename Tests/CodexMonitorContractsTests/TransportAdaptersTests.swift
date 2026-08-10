import XCTest
@testable import CodexMonitorContracts

final class TransportAdaptersTests: XCTestCase {
    private func evidence() -> EvidenceMetadata {
        EvidenceMetadata(
            evidenceRun: "AR-P0 retained evidence decision",
            cliVersion: "0.147.0",
            historicalTransportEvidenceLabel: "unresolved/inconsistent: loopback-IP WebSocket or Unix-socket WebSocket",
            probeOrHarnessAvailability: "unavailable; harness/digest was not retained",
            sanitizerAvailability: "unavailable",
            sanitizerVersion: "unavailable; retained evidence did not record a version",
            confidence: "bounded contract evidence only",
            limitations: "H2 synthetic transport fixture"
        )
    }

    private func descriptor(kind: SourceKind, source: String, adapter: String) -> AdapterDescriptor {
        AdapterDescriptor(
            adapterID: AdapterID(adapter)!, adapterVersion: AdapterVersion("h2")!,
            sourceKind: kind, sourceID: SourceID(source)!,
            capabilitySnapshot: CapabilitySnapshot([:]), evidenceMetadata: evidence()
        )
    }

    func testJSONRPCRequestResponseCorrelationRoutesOutOfOrderReplies() async throws {
        let channel = FixtureChannel()
        let client = JSONRPCClient(channel: channel)
        _ = try await completeInitialization(channel: channel) { try await client.connect() }

        async let first: JSONValue = client.request(method: "account/read")
        async let second: JSONValue = client.request(method: "thread/list")
        let request1 = try await channel.nextSentRequest()
        let request2 = try await channel.nextSentRequest()
        XCTAssertEqual(Set([request1.method, request2.method]), ["account/read", "thread/list"])

        await channel.inject(response(id: request2.id, result: .string("second")))
        await channel.inject(response(id: request1.id, result: .string("first")))
        let firstValue = try await first
        let secondValue = try await second
        XCTAssertEqual(firstValue, .string("first"))
        XCTAssertEqual(secondValue, .string("second"))
        await client.close()
    }

    func testNotificationRoutingUsesOnlyTheRegisteredHandler() async throws {
        let channel = FixtureChannel()
        let client = JSONRPCClient(channel: channel)
        let recorder = NotificationRecorder()
        await client.setNotificationHandler { notification in await recorder.append(notification.method) }
        _ = try await completeInitialization(channel: channel) { try await client.connect() }
        await channel.inject(notification(method: "thread/started", params: .object(["threadId": .string("synthetic")])) )
        let delivered = await recorder.next()
        XCTAssertEqual(delivered, "thread/started")
        await client.close()
    }

    func testRuntimeAdapterMaintainsUnvalidatedCandidateAndSourceHealthIndependence() async throws {
        let channel = FixtureChannel()
        let client = JSONRPCClient(channel: channel)
        let runtime = MonitorOwnedRuntimeTransportAdapter(
            descriptor: descriptor(kind: .monitorOwnedRuntime, source: "runtime-source", adapter: "monitor-runtime"),
            client: client, runtimeInstanceID: RuntimeInstanceID("runtime-h2")!,
            lifecycleEpoch: LifecycleEpoch("lifecycle-h2")!, accountEpoch: AccountEpoch("account-h2")!
        )
        let health = try await completeInitialization(channel: channel) { try await runtime.connect() }
        XCTAssertEqual(health.state, .connected)
        XCTAssertNil(H1LiveBoundary.candidate(from: .sourceHealth(health)))

        var iterator = runtime.observations.makeAsyncIterator()
        await runtime.route(JSONRPCNotification(jsonrpc: "2.0", method: "item/started", params: .object([
            "threadId": .string("thread-synthetic"), "turnId": .string("turn-synthetic"),
            "itemId": .string("item-synthetic"), "itemKind": .string("reasoning"), "text": .string("must-not-be-retained")
        ])))
        let candidate = await iterator.next()
        XCTAssertEqual(candidate?.kind, .itemStarted)
        XCTAssertEqual(candidate?.provenance.capability, .itemLifecycleObservation)
        XCTAssertEqual(candidate?.provenance.authority, .partial)
        XCTAssertNotEqual(candidate?.provenance.capability, .approvalLifecycle)
        XCTAssertNil(candidate?.opaqueStatus)
        _ = await runtime.close()
    }

    func testAccountAdapterUsesOnlyItsTransportRouteAndDiscardsRawResponse() async throws {
        let channel = FixtureChannel()
        let adapter = AccountTransportAdapter(descriptor: descriptor(kind: .account, source: "account-source", adapter: "account"), client: JSONRPCClient(channel: channel))
        _ = try await completeInitialization(channel: channel) { try await adapter.connect() }
        async let diagnostic = adapter.verifyAccountReadRoute()
        let request = try await channel.nextSentRequest()
        XCTAssertEqual(request.method, "account/read")
        await channel.inject(response(id: request.id, result: .object(["email": .string("never-normalized-in-h2")])) )
        let resolvedDiagnostic = try await diagnostic
        XCTAssertEqual(resolvedDiagnostic, SanitizedDiagnostic(sourceKind: .account, code: "accountReadResponseDiscarded", method: "account/read"))
        _ = await adapter.close()
    }

    func testSupervisorRecordsOnlyMonitorCreatedNamespaceAndRejectsDesktopIdentity() async throws {
        let source = SourceID("runtime-source")!
        let adapterID = AdapterID("monitor-runtime")!
        let adapterVersion = AdapterVersion("h2")!
        let runtimeID = RuntimeInstanceID("runtime-h2")!
        let lifecycle = LifecycleEpoch("lifecycle-h2")!
        let now = Date(timeIntervalSince1970: 1_728_000_000)
        let provenance = Provenance(sourceID: source, sourceKind: .monitorOwnedRuntime, adapterID: adapterID, adapterVersion: adapterVersion, runtimeInstanceID: runtimeID, observationMode: .live, authority: .partial, observedAt: now, freshness: Freshness(state: .fresh, assessedAt: now, observedAt: now), accountEpoch: nil, connectionEpoch: ConnectionEpoch("connection-h2")!, lifecycleEpoch: lifecycle, capability: .threadStartObservation, evidence: evidence(), origin: .adapter)!
        let adapter = MonitorOwnedRuntimeTransportAdapter(descriptor: AdapterDescriptor(adapterID: adapterID, adapterVersion: adapterVersion, sourceKind: .monitorOwnedRuntime, sourceID: source, capabilitySnapshot: CapabilitySnapshot([.threadStartObservation: .unvalidated]), evidenceMetadata: evidence()), client: JSONRPCClient(channel: FixtureChannel()), runtimeInstanceID: runtimeID, lifecycleEpoch: lifecycle, accountEpoch: nil)
        let supervisor = MonitorOwnedRuntimeSupervisor(adapter: adapter)
        let owned = NamespacedID(sourceID: source, entityKind: .thread, rawID: "monitor-created")!
        let record = try await supervisor.register(MonitorCreatedThreadReceipt(threadID: owned, creationProvenance: provenance))
        XCTAssertEqual(record.namespacedThreadID, owned)

        let desktop = NamespacedID(sourceID: SourceID("desktop-source")!, entityKind: .thread, rawID: "desktop-thread")!
        do {
            _ = try await supervisor.register(MonitorCreatedThreadReceipt(threadID: desktop, creationProvenance: provenance))
            XCTFail("Desktop identity was accepted as Monitor-owned")
        } catch let error as RuntimeSupervisorError {
            XCTAssertEqual(error, .desktopOrForeignThreadRejected)
        }
    }

    func testDesktopAllowlistContainsOnlyReadOperationsAndRejectsForeignIdentity() async throws {
        XCTAssertEqual(Set(DesktopReadOperation.allCases.map(\.rawValue)), ["thread/loaded/list", "thread/list", "thread/read"])
        let channel = FixtureChannel()
        let adapter = DesktopSnapshotTransportAdapter(descriptor: descriptor(kind: .desktopSnapshot, source: "desktop-source", adapter: "desktop"), client: JSONRPCClient(channel: channel))
        let foreign = NamespacedID(sourceID: SourceID("runtime-source")!, entityKind: .thread, rawID: "synthetic")!
        do {
            _ = try await adapter.read(threadID: foreign)
            XCTFail("Desktop adapter accepted a non-Desktop identity")
        } catch let error as DesktopTransportError {
            XCTAssertEqual(error, .foreignThreadIdentity)
        }
    }

    func testFutureObserverStillHasNoDataOrHealthTransport() {
        let descriptor = H1Baseline.futureObserverDescriptor(sourceID: SourceID("future-source")!, evidence: evidence())
        let observer = FutureObserverAdapter(descriptor: descriptor)!
        XCTAssertTrue(observer.outputs.isEmpty)
        XCTAssertEqual(observer.descriptor.capabilitySnapshot.allStates.values.filter { $0 != .unsupported }.count, 0)
    }

    func testSanitizerDropsPrivateFieldsAndSocketPaths() {
        let diagnostic = DiagnosticSanitizer.summarize(
            sourceKind: .monitorOwnedRuntime, code: "fixture", method: "thread/started",
            payload: .object(["threadId": .string("synthetic"), "content": .string("private"), "token": .string("secret"), "socketPath": .string("/private/socket"), "status": .string("active")]),
            transport: TransportProvenance(kind: .unixSocketWebSocket)
        )
        XCTAssertEqual(diagnostic.safeFieldNames, ["status", "threadId"])
        XCTAssertEqual(diagnostic.transport?.kind, .unixSocketWebSocket)
        XCTAssertFalse(String(describing: diagnostic).contains("/private/socket"))
        XCTAssertFalse(String(describing: diagnostic).contains("private\""))
    }

    func testTransportProvenanceIsForwardUnixSocketOnlyWithoutHistoricalRewrite() {
        let provenance = TransportProvenance(kind: .unixSocketWebSocket)
        XCTAssertEqual(provenance.kind.rawValue, "Unix-socket WebSocket")
        XCTAssertTrue(provenance.localOnly)
        XCTAssertFalse(provenance.historicalEvidenceRewritten)
    }
}

private actor FixtureChannel: JSONRPCByteChannel {
    private var inbound: [Data] = []
    private var receiveWaiter: CheckedContinuation<Data?, Never>?
    private var sent: [Data] = []
    private var sentWaiter: CheckedContinuation<Data, Never>?

    func open() async throws {}

    func send(_ data: Data) async throws {
        if let sentWaiter {
            self.sentWaiter = nil
            sentWaiter.resume(returning: data)
        } else {
            sent.append(data)
        }
    }

    func receive() async throws -> Data? {
        if !inbound.isEmpty { return inbound.removeFirst() }
        return await withCheckedContinuation { receiveWaiter = $0 }
    }

    func close() async {
        receiveWaiter?.resume(returning: nil)
        receiveWaiter = nil
    }

    func inject(_ data: Data) {
        if let receiveWaiter {
            self.receiveWaiter = nil
            receiveWaiter.resume(returning: data)
        } else {
            inbound.append(data)
        }
    }

    func nextSentData() async -> Data {
        let data: Data
        if !sent.isEmpty { data = sent.removeFirst() }
        else { data = await withCheckedContinuation { sentWaiter = $0 } }
        return data
    }

    func nextSentRequest() async throws -> JSONRPCRequest {
        let data = await nextSentData()
        return try JSONDecoder().decode(JSONRPCRequest.self, from: data)
    }

    private func response(id: Int, result: JSONValue) -> Data {
        try! JSONEncoder().encode(JSONRPCResponse(jsonrpc: "2.0", id: id, result: result, error: nil))
    }

    private func notification(method: String, params: JSONValue?) -> Data {
        try! JSONEncoder().encode(JSONRPCNotification(jsonrpc: "2.0", method: method, params: params))
    }
}

private actor NotificationRecorder {
    private var values: [String] = []
    private var waiter: CheckedContinuation<String, Never>?

    func append(_ value: String) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: value)
        } else { values.append(value) }
    }

    func next() async -> String {
        if !values.isEmpty { return values.removeFirst() }
        return await withCheckedContinuation { waiter = $0 }
    }
}

private func response(id: Int, result: JSONValue) -> Data {
    try! JSONEncoder().encode(JSONRPCResponse(jsonrpc: "2.0", id: id, result: result, error: nil))
}

private func notification(method: String, params: JSONValue?) -> Data {
    try! JSONEncoder().encode(JSONRPCNotification(jsonrpc: "2.0", method: method, params: params))
}

private func completeInitialization<T: Sendable>(channel: FixtureChannel, starting: @escaping @Sendable () async throws -> T) async throws -> T {
    async let connected = starting()
    let initializeData = await channel.nextSentData()
    let initialize = try JSONDecoder().decode(JSONRPCRequest.self, from: initializeData)
    XCTAssertEqual(initialize.method, "initialize")
    XCTAssertEqual(initialize.params?.objectValue?["clientInfo"]?.objectValue?["name"], .string("codex_monitor_h2"))
    await channel.inject(response(id: initialize.id, result: .object([:])))
    let initializedData = await channel.nextSentData()
    let initialized = try JSONDecoder().decode(JSONRPCNotification.self, from: initializedData)
    XCTAssertEqual(initialized.method, "initialized")
    return try await connected
}
