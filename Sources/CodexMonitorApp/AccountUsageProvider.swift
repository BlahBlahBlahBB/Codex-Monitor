import Foundation
import CodexMonitorContracts

/// Independent, short-lived account snapshot reader. It has no Desktop thread,
/// rollout, approval, or UI dependency. Each refresh opens the already
/// validated local control socket, performs only account reads, forwards one
/// admitted snapshot to `MonitorRuntimeStore`, then closes the socket.
public actor AccountUsageProvider {
    private let runtime: MonitorRuntimeStore
    private let refreshInterval: Duration
    private var loopTask: Task<Void, Never>?

    public init(runtime: MonitorRuntimeStore, refreshInterval: Duration = .seconds(60)) {
        self.runtime = runtime
        self.refreshInterval = refreshInterval
    }

    public func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshOnce()
                try? await Task.sleep(for: self.refreshInterval)
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    public func refreshOnce() async {
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
            do {
                // The validated local read shape requires an explicit empty
                // params object; omission is a different request shape.
                async let account = client.request(method: "account/read", params: .object([:]))
                async let limits = client.request(method: "account/rateLimits/read")
                async let usage = client.request(method: "account/usage/read")
                let snapshot = try Self.snapshot(
                    accountResponse: try await account,
                    rateLimitsResponse: try await limits,
                    usageResponse: try await usage,
                    observedAt: Date()
                )
                await runtime.ingest(account: snapshot)
                await client.close()
            } catch {
                await client.close()
                throw error
            }
        } catch {
            // A failed short-lived account session cannot leave a previous
            // quota/usage value looking current.
            await runtime.markSourceUnavailable(.account)
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
        guard let accountRoot = accountResponse.objectValue,
              let limitsRoot = rateLimitsResponse.objectValue,
              let usageRoot = usageResponse.objectValue else {
            throw AccountUsageProviderError.malformedResponse
        }

        let account = accountRoot["account"]?.objectValue
        let kind = account?["type"]?.stringValue
        let plan = account?["planType"]?.stringValue
        let email = account?["email"]?.stringValue
        let snapshots = rateLimitSnapshots(from: limitsRoot)
        let primary = mostRestricted(snapshots.compactMap { rateLimitWindow($0["primary"]) })
        let secondary = mostRestricted(snapshots.compactMap { rateLimitWindow($0["secondary"]) })
        let resetCount = integer(limitsRoot["rateLimitResetCredits"]?.objectValue?["availableCount"])
        let daily = dailyBuckets(from: usageRoot["dailyUsageBuckets"], observedAt: observedAt, calendar: calendar)
        let lifetime = integer(usageRoot["summary"]?.objectValue?["lifetimeTokens"])
        let usage = UsagePresence(
            summaryAvailable: usageRoot["summary"]?.objectValue != nil,
            dailyBucketsAvailable: daily != nil,
            totalTokens: lifetime,
            dailyBuckets: daily
        )
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
        guard let snapshot = AccountSnapshot(
            provenance: provenance,
            email: email,
            planType: plan,
            authMode: kind,
            primaryRateLimit: primary,
            secondaryRateLimit: secondary,
            usage: usage,
            resetCreditCount: resetCount
        ) else { throw AccountUsageProviderError.malformedResponse }
        return snapshot
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
        let reset = number(value["resetsAt"]).map { Date(timeIntervalSince1970: $0 / 1_000) }
        return RateLimitWindow(usedPercent: min(max(used, 0), 100), windowDurationMinutes: integer(value["windowDurationMins"]), resetsAt: reset)
    }

    private static func mostRestricted(_ windows: [RateLimitWindow]) -> RateLimitWindow? {
        windows.max { ($0.usedPercent ?? -1) < ($1.usedPercent ?? -1) }
    }

    private static func dailyBuckets(from value: JSONValue?, observedAt: Date, calendar: Calendar) -> [AccountUsageDailyBucket]? {
        guard let value else { return nil }
        guard case let .array(raw) = value else { return nil }
        let supplied = Dictionary(uniqueKeysWithValues: raw.compactMap { item -> (String, Int)? in
            guard let object = item.objectValue,
                  let date = object["startDate"]?.stringValue,
                  let tokens = integer(object["tokens"]) else { return nil }
            return (date, max(0, tokens))
        })
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = calendar.startOfDay(for: observedAt)
        return (0..<30).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = formatter.string(from: day)
            return AccountUsageDailyBucket(startDate: key, tokens: supplied[key] ?? 0)
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
