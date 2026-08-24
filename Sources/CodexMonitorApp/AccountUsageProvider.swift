import Foundation
import CodexMonitorContracts

/// Independent, short-lived account snapshot reader. It has no Desktop thread,
/// rollout, approval, or UI dependency. Each refresh opens the already
/// validated local control socket, performs only account reads, forwards one
/// admitted snapshot to `MonitorRuntimeStore`, then closes the socket.
public actor AccountUsageProvider {
    private let runtime: MonitorRuntimeStore
    private let refreshInterval: Duration
    private let retryDelay: Duration
    private let refreshCycle: @Sendable () async -> AccountRefreshCycleResult
    private let sleep: @Sendable (Duration) async throws -> Void
    private var loopTask: Task<Void, Never>?
    /// The provider remains one-shot refresh capable until its first explicit
    /// stop, preserving construction-time callers while ensuring no queued UI
    /// refresh can restart I/O during termination drain.
    private var acceptsRefreshes = true
    private var inFlightRefresh: InFlightRefresh?
    private var stoppingRefresh: InFlightRefresh?
    /// This is deliberately a whole admitted snapshot, never individual
    /// components. It is only used to decide whether a transient quota read
    /// can be held while one replacement cycle is attempted.
    private var lastCompleteSnapshot: AccountSnapshot?

    public init(runtime: MonitorRuntimeStore, refreshInterval: Duration = .seconds(60)) {
        self.runtime = runtime
        self.refreshInterval = refreshInterval
        self.retryDelay = .milliseconds(500)
        self.refreshCycle = Self.productionRefreshCycle
        self.sleep = Self.productionSleep
    }

    init(
        runtime: MonitorRuntimeStore,
        refreshInterval: Duration = .seconds(60),
        retryDelay: Duration = .milliseconds(500),
        refreshCycle: @escaping @Sendable () async -> AccountRefreshCycleResult,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) {
        self.runtime = runtime
        self.refreshInterval = refreshInterval
        self.retryDelay = retryDelay
        self.refreshCycle = refreshCycle
        self.sleep = sleep
    }

    public func start() {
        guard loopTask == nil else { return }
        acceptsRefreshes = true
        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshOnce()
                try? await Task.sleep(for: self.refreshInterval)
            }
        }
    }

    public func stop() async {
        // Close the lifecycle gate before awaiting cancellation so queued UI
        // tasks cannot create a replacement operation during the drain.
        acceptsRefreshes = false
        loopTask?.cancel()
        loopTask = nil
        let activeRefresh = inFlightRefresh
        inFlightRefresh = nil
        let alreadyStopping = stoppingRefresh
        if let activeRefresh {
            activeRefresh.task.cancel()
            if alreadyStopping == nil {
                stoppingRefresh = activeRefresh
            }
        }
        if let alreadyStopping {
            await alreadyStopping.task.value
            clearStoppingRefreshIfOwned(by: alreadyStopping.id)
        }
        if let activeRefresh {
            await activeRefresh.task.value
            clearStoppingRefreshIfOwned(by: activeRefresh.id)
        }
    }

    public func refreshOnce() async {
        guard acceptsRefreshes else { return }
        if let inFlightRefresh {
            Self.recordRefreshEvent("refreshCoalesced")
            await inFlightRefresh.task.value
            return
        }
        let operationID = UUID()
        let refresh = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(operationID: operationID)
        }
        inFlightRefresh = InFlightRefresh(id: operationID, task: refresh)
        await refresh.value
        clearInFlightRefreshIfOwned(by: operationID)
    }

    private func performRefresh(operationID: UUID) async {
        let initial = await refreshCycle()
        guard isCurrent(operationID) else { return }
        switch initial {
        case .connectionFailure(let diagnostics):
            Self.record(diagnostics)
            // A transient account refresh failure must not erase the last
            // authoritative Account/Plan/Usage/Quota snapshot. The runtime
            // keeps it visible and records refresh degradation internally.
            await markRefreshDegradedIfCurrent(operationID)
        case .connected(let assembled):
            Self.record(assembled.diagnostics)
            guard shouldHoldTransientQuotaPartial(assembled) else {
                await admit(assembled, operationID: operationID)
                return
            }

            // Hold the *entire* previous coherent snapshot. In particular,
            // do not admit the current account metadata with prior-cycle
            // quota while the one permitted replacement cycle is pending.
            Self.recordRefreshEvent("transientQuotaPartialHeld")
            await markRefreshDegradedIfCurrent(operationID)
            guard isCurrent(operationID) else { return }
            Self.recordRefreshEvent("boundedRetryStarted")
            do {
                try await sleep(retryDelay)
            } catch {
                return
            }
            guard isCurrent(operationID) else { return }

            let retry = await refreshCycle()
            guard isCurrent(operationID) else { return }
            switch retry {
            case .connectionFailure(let diagnostics):
                Self.record(diagnostics)
                // Keep the held snapshot under the established whole-
                // connection-failure behavior; the next normal cadence can
                // recover it without publishing an invented partial cycle.
                await markRefreshDegradedIfCurrent(operationID)
            case .connected(let retryAssembly):
                Self.record(retryAssembly.diagnostics)
                if retryAssembly.isComplete {
                    Self.recordRefreshEvent("boundedRetrySucceeded")
                } else {
                    Self.recordRefreshEvent("boundedRetryExhausted")
                }
                // Retry exhaustion is intentionally fail-closed: this admits
                // only the retry cycle's components, never a component merged
                // from the held snapshot.
                await admit(retryAssembly, operationID: operationID)
            }
        }
    }

    private func shouldHoldTransientQuotaPartial(_ assembled: AccountRefreshAssembly) -> Bool {
        assembled.snapshot != nil
            && assembled.diagnostics.rateLimits != .available
            && lastCompleteSnapshot != nil
    }

    private func admit(_ assembled: AccountRefreshAssembly, operationID: UUID) async {
        guard isCurrent(operationID) else { return }
        if let snapshot = assembled.snapshot {
            await runtime.ingest(account: snapshot, refreshDegraded: assembled.diagnostics.degraded)
            guard isCurrent(operationID) else { return }
            // This tracks the snapshot currently held by the runtime. Once a
            // normal partial cycle is admitted, an older complete snapshot is
            // no longer available to preserve as a coherent whole.
            lastCompleteSnapshot = assembled.isCompleteQuotaSnapshot ? snapshot : nil
        }
    }

    private func markRefreshDegradedIfCurrent(_ operationID: UUID) async {
        guard isCurrent(operationID) else { return }
        await runtime.markAccountRefreshDegraded()
    }

    private func isCurrent(_ operationID: UUID) -> Bool {
        !Task.isCancelled && inFlightRefresh?.id == operationID
    }

    private func clearInFlightRefreshIfOwned(by operationID: UUID) {
        guard inFlightRefresh?.id == operationID else { return }
        inFlightRefresh = nil
    }

    private func clearStoppingRefreshIfOwned(by operationID: UUID) {
        guard stoppingRefresh?.id == operationID else { return }
        stoppingRefresh = nil
    }

    private static func productionSleep(_ duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }

    private static func productionRefreshCycle() async -> AccountRefreshCycleResult {
        do {
            let resolver = OfficialSocketResolver()
            let endpoint = try UnixSocketWebSocketEndpoint(capability: resolver.resolve())
            let descriptor = Self.descriptor
            let client = JSONRPCClient(
                channel: UnixSocketWebSocketChannel(endpoint: endpoint),
                binding: try JSONRPCClientBinding(descriptor: descriptor),
                clientInfo: JSONRPCClientInfo(name: "codex_monitor_account", title: "Codex Monitor Account", version: "v1")
            )
            _ = try await client.connect()
            // The validated local read shape requires an explicit empty
            // params object; omission is a different request shape.
            async let account = Self.read(client, method: "account/read", params: .object([:]))
            async let limits = Self.read(client, method: "account/rateLimits/read")
            async let usage = Self.read(client, method: "account/usage/read")
            let assembled = Self.assemble(
                account: await account,
                rateLimits: await limits,
                usage: await usage,
                observedAt: Date()
            )
            await client.close()
            return .connected(assembled)
        } catch {
            return .connectionFailure(.wholeConnectionFailure(error))
        }
    }

    static let descriptor = AdapterDescriptor(
        adapterID: AdapterID("account-usage-provider")!,
        adapterVersion: AdapterVersion("v1")!,
        sourceKind: .account,
        sourceID: SourceID("codex-account-local")!,
        capabilitySnapshot: CapabilitySnapshot([
            .accountReturnedFields: .snapshot,
            .planAndAuthModeFields: .snapshot,
            .primaryRateLimitSnapshot: .snapshot,
            .secondaryRateLimitSnapshot: .snapshot,
            .usageResponsePresence: .snapshot,
            .resetCreditCount: .snapshot,
            .resetCreditDetails: .unvalidated,
            .authoritativeCost: .unsupported,
            .resetCreditConsume: .unvalidated,
            .sparseRateLimitUpdateMerge: .unvalidated,
            .stableLocalAccountDiscriminator: .unvalidated,
            .accountSwitching: .unsupported
        ]),
        evidenceMetadata: EvidenceMetadata(
            evidenceRun: "local account snapshot",
            cliVersion: "0.147.0",
            historicalTransportEvidenceLabel: "official local control socket",
            probeOrHarnessAvailability: "available",
            sanitizerAvailability: "runtime-only values",
            sanitizerVersion: "v1",
            confidence: "read-only snapshot",
            limitations: "no account switching, cost, reset detail, or reset mutation"
        )
    )

    /// Pure response mapping used by focused tests. It accepts only the
    /// previously validated read response shapes; any malformed mandatory root
    /// fails the whole refresh rather than inventing a partial account value.
    static func snapshot(accountResponse: JSONValue, rateLimitsResponse: JSONValue, usageResponse: JSONValue, observedAt: Date, calendar: Calendar = .autoupdatingCurrent) throws -> AccountSnapshot {
        let assembled = assemble(
            account: .success(accountResponse),
            rateLimits: .success(rateLimitsResponse),
            usage: .success(usageResponse),
            observedAt: observedAt,
            calendar: calendar
        )
        guard assembled.diagnostics.account != .responseIncompatible,
              assembled.diagnostics.rateLimits != .responseIncompatible,
              assembled.diagnostics.usage != .responseIncompatible,
              let snapshot = assembled.snapshot else {
            throw AccountUsageProviderError.malformedResponse
        }
        return snapshot
    }

    /// A successfully initialized connection can have uneven RPC capability.
    /// The resulting snapshot contains only components returned successfully
    /// in this refresh cycle. Without a validated account identity, a failed
    /// RPC must be absent rather than joined with a prior-cycle component.
    static func assemble(
        account: AccountRPCRead,
        rateLimits: AccountRPCRead,
        usage: AccountRPCRead,
        observedAt: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> AccountRefreshAssembly {
        var diagnostics = AccountRefreshDiagnostics(
            account: account.diagnostic,
            rateLimits: rateLimits.diagnostic,
            usage: usage.diagnostic
        )
        let accountValue = account.value.flatMap { value -> AccountMetadata? in
            do { return try accountMetadata(from: value) }
            catch { diagnostics.account = .responseIncompatible; return nil }
        }
        let limitsValue = rateLimits.value.flatMap { value -> RateLimitMetadata? in
            do { return try rateLimitMetadata(from: value) }
            catch { diagnostics.rateLimits = .responseIncompatible; return nil }
        }
        let usageValue = usage.value.flatMap { value -> UsagePresence? in
            do { return try usageMetadata(from: value, observedAt: observedAt, calendar: calendar) }
            catch { diagnostics.usage = .responseIncompatible; return nil }
        }

        // A successfully decoded account/read response may explicitly omit the
        // account object. This is not a transport error, but it must never be
        // presented as a fabricated account or plan.
        if account.value != nil, accountValue?.isAbsent == true {
            diagnostics.account = .accountDataAbsent
        }
        diagnostics.degraded = diagnostics.account != .available || diagnostics.rateLimits != .available || diagnostics.usage != .available

        guard accountValue != nil || limitsValue != nil || usageValue != nil else {
            return AccountRefreshAssembly(snapshot: nil, diagnostics: diagnostics)
        }
        let provenance = Provenance(
            sourceID: descriptor.sourceID,
            sourceKind: .account,
            adapterID: descriptor.adapterID,
            adapterVersion: descriptor.adapterVersion,
            observationMode: .snapshot,
            authority: .authoritative,
            observedAt: observedAt,
            freshness: Freshness(state: .fresh, assessedAt: observedAt, observedAt: observedAt),
            capability: .accountReturnedFields,
            evidence: descriptor.evidenceMetadata,
            origin: .adapter
        )!
        let snapshot = AccountSnapshot(
            provenance: provenance,
            email: accountValue?.email,
            planType: accountValue?.planType,
            authMode: accountValue?.authMode,
            primaryRateLimit: limitsValue?.primary,
            secondaryRateLimit: limitsValue?.secondary,
            usage: usageValue,
            resetCreditCount: limitsValue?.resetCreditCount
        )
        return AccountRefreshAssembly(snapshot: snapshot, diagnostics: diagnostics)
    }

    private static func read(_ client: JSONRPCClient, method: String, params: JSONValue? = nil) async -> AccountRPCRead {
        do { return .success(try await client.request(method: method, params: params)) }
        catch { return .failure(AccountRefreshDiagnosticCategory(error: error)) }
    }

    private static func accountMetadata(from response: JSONValue) throws -> AccountMetadata {
        guard let root = response.objectValue else { throw AccountUsageProviderError.malformedResponse }
        let account = root["account"]?.objectValue
        return AccountMetadata(email: account?["email"]?.stringValue, planType: account?["planType"]?.stringValue, authMode: account?["type"]?.stringValue, isAbsent: account == nil)
    }

    private static func rateLimitMetadata(from response: JSONValue) throws -> RateLimitMetadata {
        guard let root = response.objectValue else { throw AccountUsageProviderError.malformedResponse }
        let snapshots = rateLimitSnapshots(from: root)
        return RateLimitMetadata(
            primary: mostRestricted(snapshots.compactMap { rateLimitWindow($0["primary"]) }),
            secondary: mostRestricted(snapshots.compactMap { rateLimitWindow($0["secondary"]) }),
            resetCreditCount: integer(root["rateLimitResetCredits"]?.objectValue?["availableCount"])
        )
    }

    private static func usageMetadata(from response: JSONValue, observedAt: Date, calendar: Calendar) throws -> UsagePresence {
        guard let root = response.objectValue else { throw AccountUsageProviderError.malformedResponse }
        let daily = dailyBuckets(from: root["dailyUsageBuckets"], observedAt: observedAt, calendar: calendar)
        return UsagePresence(
            summaryAvailable: root["summary"]?.objectValue != nil,
            dailyBucketsAvailable: daily != nil,
            totalTokens: integer(root["summary"]?.objectValue?["lifetimeTokens"]),
            dailyBuckets: daily
        )
    }

    private static func record(_ diagnostics: AccountRefreshDiagnostics) {
        DiagnosticEvent.record(.state, diagnostics.fields)
    }

    private static func recordRefreshEvent(_ event: String) {
        DiagnosticEvent.record(.state, ["event": event])
    }

    private static func rateLimitSnapshots(from root: [String: JSONValue]) -> [[String: JSONValue]] {
        var values: [[String: JSONValue]] = []
        if let primary = root["rateLimits"]?.objectValue { values.append(primary) }
        if let keyed = root["rateLimitsByLimitId"]?.objectValue {
            values.append(contentsOf: keyed.values.compactMap(\.objectValue))
        }
        return values
    }

    private static func rateLimitWindow(_ value: JSONValue?) -> RateLimitWindow? {
        guard let value = value?.objectValue, let used = number(value["usedPercent"]), used.isFinite else { return nil }
        let reset = number(value["resetsAt"]).flatMap(normalizedUnixDate)
        return RateLimitWindow(usedPercent: min(max(used, 0), 100), windowDurationMinutes: integer(value["windowDurationMins"]), resetsAt: reset)
    }

    /// The validated account route has emitted Unix seconds (10 digits).
    /// Accept millisecond values only when their magnitude proves that unit;
    /// never unconditionally divide a valid seconds timestamp into 1970.
    private static func normalizedUnixDate(_ value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        let seconds = value >= 100_000_000_000 ? value / 1_000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    private static func mostRestricted(_ windows: [RateLimitWindow]) -> RateLimitWindow? {
        windows.max { ($0.usedPercent ?? -1) < ($1.usedPercent ?? -1) }
    }

    private static func dailyBuckets(from value: JSONValue?, observedAt: Date, calendar: Calendar) -> [AccountUsageDailyBucket]? {
        guard let value else { return nil }
        guard case let .array(raw) = value else { return nil }
        var supplied: [String: Int] = [:]
        for item in raw {
            guard let object = item.objectValue,
                  let date = object["startDate"]?.stringValue,
                  let tokens = integer(object["tokens"]) else { continue }
            let (sum, overflow) = (supplied[date] ?? 0).addingReportingOverflow(max(0, tokens))
            supplied[date] = overflow ? Int.max : sum
        }
        let today = calendar.startOfDay(for: observedAt)
        return (0..<30).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = LocalUsageDateKey.value(for: day, calendar: calendar)
            if let tokens = supplied[key] {
                return AccountUsageDailyBucket(startDate: key, tokens: tokens, isSourcePresent: true)
            }
            // Keep a zero-height chart coordinate without claiming that zero
            // was returned by the source for this calendar day.
            return AccountUsageDailyBucket(startDate: key, tokens: 0, isSourcePresent: false)
        }
    }

    private static func number(_ value: JSONValue?) -> Double? {
        if case let .number(number) = value { return number }
        if let string = value?.stringValue { return Double(string) }
        return nil
    }

    private static func integer(_ value: JSONValue?) -> Int? {
        guard let number = number(value), number.isFinite, number.rounded() == number,
              number >= 0, number <= Double(Int.max) else { return nil }
        return Int(number)
    }
}

enum AccountUsageProviderError: Error { case malformedResponse }

/// Safe, structural diagnostics only. These names never include a socket path,
/// server-provided message, request id, user identity, or payload.
enum AccountRefreshDiagnosticCategory: String, Sendable, Equatable {
    case available
    case socketRejected
    case transportUnavailable
    case rpcUnavailable
    case responseIncompatible
    case accountDataAbsent
    case unknown

    init(error: Error) {
        switch error {
        case let error as UnixSocketValidationError:
            self = error == .inaccessible ? .unknown : .socketRejected
        case let error as JSONRPCTransportError:
            switch error {
            case .endpointRejected(let validation):
                self = validation == .inaccessible ? .unknown : .socketRejected
            case .transportFailure, .webSocketClosed:
                self = .transportUnavailable
            case .protocolError, .requestTimedOut, .requestCancelled, .connectionClosed, .lifecycleUnavailable:
                self = .rpcUnavailable
            case .malformedMessage:
                self = .responseIncompatible
            case .sourceBindingRejected:
                self = .unknown
            }
        case is AccountUsageProviderError:
            self = .responseIncompatible
        default:
            self = .unknown
        }
    }
}

enum AccountRPCRead: Sendable {
    case success(JSONValue)
    case failure(AccountRefreshDiagnosticCategory)

    var value: JSONValue? {
        guard case let .success(value) = self else { return nil }
        return value
    }

    var diagnostic: AccountRefreshDiagnosticCategory {
        switch self {
        case .success: .available
        case .failure(let category): category
        }
    }
}

struct AccountRefreshDiagnostics: Sendable, Equatable {
    var account: AccountRefreshDiagnosticCategory
    var rateLimits: AccountRefreshDiagnosticCategory
    var usage: AccountRefreshDiagnosticCategory
    var degraded = false

    init(account: AccountRefreshDiagnosticCategory, rateLimits: AccountRefreshDiagnosticCategory, usage: AccountRefreshDiagnosticCategory) {
        self.account = account
        self.rateLimits = rateLimits
        self.usage = usage
    }

    static func wholeConnectionFailure(_ error: Error) -> Self {
        let category = AccountRefreshDiagnosticCategory(error: error)
        return Self(account: category, rateLimits: category, usage: category, degraded: true)
    }

    private init(account: AccountRefreshDiagnosticCategory, rateLimits: AccountRefreshDiagnosticCategory, usage: AccountRefreshDiagnosticCategory, degraded: Bool) {
        self.account = account
        self.rateLimits = rateLimits
        self.usage = usage
        self.degraded = degraded
    }

    var fields: [String: String] {
        [
            "event": "accountRefresh",
            "account": account.rawValue,
            "rateLimits": rateLimits.rawValue,
            "usage": usage.rawValue,
            "degraded": String(degraded)
        ]
    }
}

struct AccountRefreshAssembly: Sendable {
    let snapshot: AccountSnapshot?
    let diagnostics: AccountRefreshDiagnostics

    /// A complete refresh means all three RPC components decoded correctly.
    var isComplete: Bool {
        diagnostics.account == .available
            && diagnostics.rateLimits == .available
            && diagnostics.usage == .available
    }

    /// Only an already visible, complete snapshot with an authoritative
    /// primary quota can be held during a later transient quota failure. A
    /// successful rate-limits RPC that contains no primary quota remains an
    /// authoritative absence and is admitted normally instead.
    var isCompleteQuotaSnapshot: Bool {
        isComplete
            && snapshot?.primaryRateLimit != nil
    }
}

enum AccountRefreshCycleResult: Sendable {
    case connected(AccountRefreshAssembly)
    case connectionFailure(AccountRefreshDiagnostics)
}

private struct InFlightRefresh: Sendable {
    let id: UUID
    let task: Task<Void, Never>
}

private struct AccountMetadata: Sendable {
    let email: String?
    let planType: String?
    let authMode: String?
    let isAbsent: Bool

    init(email: String?, planType: String?, authMode: String?, isAbsent: Bool) {
        self.email = email
        self.planType = planType
        self.authMode = authMode
        self.isAbsent = isAbsent
    }

}

private struct RateLimitMetadata: Sendable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let resetCreditCount: Int?

    init(primary: RateLimitWindow?, secondary: RateLimitWindow?, resetCreditCount: Int?) {
        self.primary = primary
        self.secondary = secondary
        self.resetCreditCount = resetCreditCount
    }

}
