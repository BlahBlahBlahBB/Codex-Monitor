import AppKit
import CryptoKit
import Foundation
import Security
import CodexMonitorContracts

/// The driver can keep this source injected for the whole app lifetime while
/// still treating it as absent until the user's setting has successfully
/// activated the app-owned observer.
final class AppManagedHookApprovalJournalSource: HookApprovalJournalSource, @unchecked Sendable {
    private let journalURL: URL
    private let lock = NSLock()
    private var active = false

    init(journalURL: URL) { self.journalURL = journalURL }

    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    func setActive(_ value: Bool) {
        lock.lock(); active = value; lock.unlock()
    }

    func readRecords() throws -> [Data] {
        guard isActive else { return [] }
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return [] }
        let data = try Data(contentsOf: journalURL)
        // A damaged or unexpectedly large app-owned journal must not consume
        // unbounded memory in the existing reader lane.
        guard data.count <= 4 * 1_024 * 1_024 else { throw ApprovalObserverIntegrationError.journalTooLarge }
        return data.split(whereSeparator: { $0 == UInt8(0x0A) }).map { Data($0) }
    }
}

/// The HMAC key is read only when the already-sanitized journal is being
/// correlated with the validated desktop rollout.  Raw Codex IDs never enter
/// this object’s persistent state.
final class AppManagedHookApprovalIdentityResolver: HookApprovalIdentityResolving, @unchecked Sendable {
    private let identityKeyURL: URL

    init(identityKeyURL: URL) { self.identityKeyURL = identityKeyURL }

    func owner(sourceRawID: String, sessionRawID: String, turnRawID: String) -> HookApprovalTurnOwner? {
        guard let keyMaterial = try? Data(contentsOf: identityKeyURL),
              let deriver = KeyedHookApprovalIdentityDeriver(keyMaterial: keyMaterial) else { return nil }
        return deriver.owner(sourceRawID: sourceRawID, sessionRawID: sessionRawID, turnRawID: turnRawID)
    }
}


// MARK: - Immutable release installer

struct AppOwnedApprovalObserverRelease: Sendable, Equatable {
    let version: String
    let directoryURL: URL
    let executableURL: URL
    let payloadURL: URL
    /// The shell-quoted command is what Codex executes; the underlying URL is
    /// retained separately so ownership matching never guesses from display text.
    let command: String
}

struct AppOwnedApprovalObserverReleaseInstaller: Sendable {
    let paths: AppOwnedApprovalObserverPaths
    let helperExecutableURL: URL?
    let signatureVerifier: @Sendable (URL) -> Bool

    init(
        paths: AppOwnedApprovalObserverPaths,
        helperExecutableURL: URL? = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/Helpers/ApprovalObserver"),
        signatureVerifier: @escaping @Sendable (URL) -> Bool = AppOwnedApprovalObserverReleaseInstaller.strictlyValidSignature
    ) {
        self.paths = paths
        self.helperExecutableURL = helperExecutableURL
        self.signatureVerifier = signatureVerifier
    }

    func ensureRelease() throws -> AppOwnedApprovalObserverRelease {
        guard let helperExecutableURL else {
            throw ApprovalObserverIntegrationError.releaseUnavailable
        }
        let executable = helperExecutableURL.resolvingSymlinksInPath().standardizedFileURL
        let values = try executable.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey])
        guard values.isRegularFile == true, values.isExecutable == true else {
            throw ApprovalObserverIntegrationError.releaseUnavailable
        }
        guard signatureVerifier(executable) else { throw ApprovalObserverIntegrationError.releaseSignatureInvalid }
        let payload = try Data(contentsOf: executable)
        guard !payload.isEmpty else { throw ApprovalObserverIntegrationError.releaseUnavailable }
        let payloadDigest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

        try ensureDirectory(paths.rootURL)
        try ensureDirectory(paths.versionsURL)
        try ensureDirectory(paths.journalURL.deletingLastPathComponent())
        try ensureIdentityKey()

        let releaseName = "observer-\(String(payloadDigest.prefix(32)))"
        let directory = paths.versionsURL.appendingPathComponent(releaseName, isDirectory: true)
        let payloadURL = directory.appendingPathComponent("ApprovalObserver")
        try ensureDirectory(directory)

        // The release owns an immutable copy of the observer payload.  The
        // installed command must never execute a future app binary through an
        // old trusted path.
        try ensureImmutableFile(payload, at: payloadURL, permissions: 0o700)
        guard signatureVerifier(payloadURL) else { throw ApprovalObserverIntegrationError.releaseSignatureInvalid }
        return AppOwnedApprovalObserverRelease(version: releaseName, directoryURL: directory, executableURL: payloadURL, payloadURL: payloadURL, command: shellQuote(payloadURL.path))
    }

    private static func strictlyValidSignature(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess
    }

    private func ensureImmutableFile(_ data: Data, at url: URL, permissions: Int) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == data else { throw ApprovalObserverIntegrationError.releaseCollision }
        } else {
            try data.write(to: url, options: .atomic)
        }
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private func ensureIdentityKey() throws {
        if FileManager.default.fileExists(atPath: paths.identityKeyURL.path) {
            guard try Data(contentsOf: paths.identityKeyURL).count >= 16 else { throw ApprovalObserverIntegrationError.identityKeyUnavailable }
            return
        }
        var key = Data(count: 32)
        let status = key.withUnsafeMutableBytes { rawBuffer in
            SecRandomCopyBytes(kSecRandomDefault, rawBuffer.count, rawBuffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw ApprovalObserverIntegrationError.identityKeyUnavailable }
        try key.write(to: paths.identityKeyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.identityKeyURL.path)
    }

    private func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}

private func shellQuote(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func unquotedShellPath(_ command: String) -> String? {
    guard command.first == "'", command.last == "'", command.count >= 2 else { return nil }
    let start = command.index(after: command.startIndex)
    let end = command.index(before: command.endIndex)
    return String(command[start..<end]).replacingOccurrences(of: "'\\''", with: "'")
}

// MARK: - Integration errors

enum ApprovalObserverIntegrationError: Error, Sendable, Equatable {
    case releaseUnavailable
    case releaseCollision
    case releaseSignatureInvalid
    case identityKeyUnavailable
    case malformedHooks
    case journalTooLarge
    case codexUnavailable
    case configurationConflict
    case trustWriteFailed
    case hooksNotReady
    case unsupportedCapability
    case superseded
}

// MARK: - Small app-server contract

enum ApprovalObserverHookEvent: CaseIterable, Sendable, Equatable {
    case permissionRequest
    case postToolUse
    case stop

    var configName: String {
        switch self {
        case .permissionRequest: "PermissionRequest"
        case .postToolUse: "PostToolUse"
        case .stop: "Stop"
        }
    }

    var appServerName: String {
        switch self {
        case .permissionRequest: "permissionRequest"
        case .postToolUse: "postToolUse"
        case .stop: "stop"
        }
    }
}

enum ApprovalObserverConfigMergeStrategy: String, Sendable, Equatable {
    case upsert
}

/// Builds only the three owned inline hook tables from the current effective
/// config returned by Codex.  The app-server applies these edits against the
/// caller's expected config version, so unrelated config and user handlers
/// remain under Codex's ownership and CAS boundary.
struct AppOwnedInlineHookConfigurationEditor: Sendable {
    let ownedCommands: Set<String>
    let ownedPathPrefix: String?

    init(ownedCommands: Set<String>, ownedPathPrefix: String? = nil) {
        self.ownedCommands = ownedCommands
        self.ownedPathPrefix = ownedPathPrefix
    }

    func installing(hooks: JSONValue, command: String, preserveExistingOwned: Bool = false) throws -> [ApprovalObserverConfigEdit] {
        let root = try hooksObject(from: hooks)
        var edits: [ApprovalObserverConfigEdit] = []
        for event in ApprovalObserverHookEvent.allCases {
            let existing = try groups(for: event.configName, in: root)
            let retained = try removingOwned(
                from: existing,
                exactCommands: preserveExistingOwned ? [command] : ownedCommands.union([command]),
                pathPrefix: preserveExistingOwned ? nil : ownedPathPrefix
            )
            var desired = retained
            desired.append(ownedGroup(command: command))
            let value = JSONValue.array(desired.map(JSONValue.object))
            if root[event.configName] != value {
                edits.append(ApprovalObserverConfigEdit(keyPath: "hooks.\(event.configName)", value: value))
            }
        }
        return edits
    }

    func removing(hooks: JSONValue, includeAllAppOwned: Bool = false) throws -> [ApprovalObserverConfigEdit] {
        let root = try hooksObject(from: hooks)
        var edits: [ApprovalObserverConfigEdit] = []
        for event in ApprovalObserverHookEvent.allCases {
            guard let current = root[event.configName] else { continue }
            let existing = try groups(for: event.configName, in: root)
            let retained = try removingOwned(
                from: existing,
                exactCommands: ownedCommands,
                pathPrefix: includeAllAppOwned ? ownedPathPrefix : nil
            )
            let value = JSONValue.array(retained.map(JSONValue.object))
            if current != value {
                edits.append(ApprovalObserverConfigEdit(keyPath: "hooks.\(event.configName)", value: value))
            }
        }
        return edits
    }

    private func hooksObject(from hooks: JSONValue) throws -> [String: JSONValue] {
        guard case .object(let value) = hooks else {
            throw ApprovalObserverIntegrationError.malformedHooks
        }
        return value
    }

    private func groups(for event: String, in hooks: [String: JSONValue]) throws -> [[String: JSONValue]] {
        guard let raw = hooks[event] else { return [] }
        guard case .array(let values) = raw else { throw ApprovalObserverIntegrationError.malformedHooks }
        return try values.map { value in
            guard case .object(let group) = value else { throw ApprovalObserverIntegrationError.malformedHooks }
            return group
        }
    }

    private func removingOwned(
        from groups: [[String: JSONValue]],
        exactCommands: Set<String>,
        pathPrefix: String?
    ) throws -> [[String: JSONValue]] {
        var result: [[String: JSONValue]] = []
        for original in groups {
            var group = original
            guard let rawHandlers = group["hooks"] else {
                result.append(group)
                continue
            }
            guard case .array(let handlers) = rawHandlers else {
                throw ApprovalObserverIntegrationError.malformedHooks
            }
            var retained: [JSONValue] = []
            var removedOwned = false
            for handlerValue in handlers {
                guard case .object(let handler) = handlerValue else {
                    throw ApprovalObserverIntegrationError.malformedHooks
                }
                let isCommand = handler["type"] == nil || handler["type"]?.stringValue == "command"
                if isCommand,
                   let command = handler["command"]?.stringValue,
                   isOwned(command, exactCommands: exactCommands, pathPrefix: pathPrefix) {
                    removedOwned = true
                } else {
                    retained.append(handlerValue)
                }
            }
            if !retained.isEmpty || !removedOwned || handlers.isEmpty {
                group["hooks"] = .array(retained)
                result.append(group)
            }
        }
        return result
    }

    private func isOwned(_ command: String, exactCommands: Set<String>, pathPrefix: String?) -> Bool {
        if exactCommands.contains(command) { return true }
        guard let path = unquotedShellPath(command) else { return false }
        if exactCommands.contains(shellQuote(path)) { return true }
        guard let pathPrefix else { return false }
        let normalizedPrefix = pathPrefix.hasSuffix("/") ? pathPrefix : pathPrefix + "/"
        return path.hasPrefix(normalizedPrefix)
    }

    private func ownedGroup(command: String) -> [String: JSONValue] {
        [
            "matcher": .string(".*"),
            "hooks": .array([
                .object([
                    "type": .string("command"),
                    "command": .string(command),
                    "timeout": .number(3)
                ])
            ])
        ]
    }
}

enum ApprovalObserverHookTrustStatus: Sendable, Equatable {
    case managed
    case untrusted
    case trusted
    case modified
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "managed": self = .managed
        case "untrusted": self = .untrusted
        case "trusted": self = .trusted
        case "modified": self = .modified
        default: self = .unknown(rawValue)
        }
    }
}

struct ApprovalObserverCodexConfig: Sendable, Equatable {
    let version: String
    let hooksEnabled: Bool
    let hooks: JSONValue
}

struct ApprovalObserverConfigEdit: Sendable, Equatable {
    let keyPath: String
    let mergeStrategy: ApprovalObserverConfigMergeStrategy
    let value: JSONValue

    init(
        keyPath: String,
        value: JSONValue,
        mergeStrategy: ApprovalObserverConfigMergeStrategy = .upsert
    ) {
        self.keyPath = keyPath
        self.mergeStrategy = mergeStrategy
        self.value = value
    }
}

struct ApprovalObserverCodexHook: Sendable, Equatable {
    let key: String
    let eventName: String
    let handlerType: String
    let command: String
    let sourcePath: String
    let source: String
    let enabled: Bool
    let currentHash: String
    let trustStatus: ApprovalObserverHookTrustStatus
}

protocol ApprovalObserverCodexAPI: Sendable {
    func readConfig() async throws -> ApprovalObserverCodexConfig
    @discardableResult func writeConfig(edits: [ApprovalObserverConfigEdit], expectedVersion: String) async throws -> String
    func listHooks(cwds: [String]) async throws -> [ApprovalObserverCodexHook]
    func close() async
}

/// Uses the already-existing bundled app-server transport.  It never accepts
/// PATH, a caller-provided executable, or the frozen R1 release as authority.
actor AppServerApprovalObserverCodexClient: ApprovalObserverCodexAPI {
    private let executableResolver: TrustedCodexBundledExecutableResolver
    private var client: JSONRPCClient?

    init(executableResolver: TrustedCodexBundledExecutableResolver = TrustedCodexBundledExecutableResolver()) {
        self.executableResolver = executableResolver
    }

    func readConfig() async throws -> ApprovalObserverCodexConfig {
        let result = try await request(method: "config/read", params: .object(["includeLayers": .bool(false)]))
        guard let object = result.objectValue,
              let config = object["config"]?.objectValue,
              let features = config["features"]?.objectValue,
              let hooksEnabled = features["hooks"].flatMap(boolValue),
              let origins = object["origins"]?.objectValue else {
            throw ApprovalObserverIntegrationError.codexUnavailable
        }
        let version = origins["user"]?.objectValue?["version"]?.stringValue
            ?? origins.values.compactMap({ $0.objectValue?["version"]?.stringValue }).first
        guard let version else { throw ApprovalObserverIntegrationError.codexUnavailable }
        let hooks = config["hooks"] ?? .object([:])
        guard hooks.objectValue != nil else { throw ApprovalObserverIntegrationError.malformedHooks }
        return ApprovalObserverCodexConfig(version: version, hooksEnabled: hooksEnabled, hooks: hooks)
    }

    @discardableResult
    func writeConfig(edits: [ApprovalObserverConfigEdit], expectedVersion: String) async throws -> String {
        let encodedEdits = edits.map { edit in
            JSONValue.object([
                "keyPath": .string(edit.keyPath),
                "mergeStrategy": .string(edit.mergeStrategy.rawValue),
                "value": edit.value
            ])
        }
        do {
            let result = try await request(
                method: "config/batchWrite",
                params: .object([
                    "edits": .array(encodedEdits),
                    "expectedVersion": .string(expectedVersion),
                    "reloadUserConfig": .bool(true)
                ])
            )
            guard let object = result.objectValue,
                  object["status"]?.stringValue == "ok",
                  let version = object["version"]?.stringValue else {
                throw ApprovalObserverIntegrationError.trustWriteFailed
            }
            return version
        } catch let error as JSONRPCTransportError {
            if case .protocolError = error { throw ApprovalObserverIntegrationError.configurationConflict }
            throw ApprovalObserverIntegrationError.codexUnavailable
        } catch let error as ApprovalObserverIntegrationError {
            throw error
        } catch {
            throw ApprovalObserverIntegrationError.codexUnavailable
        }
    }

    func listHooks(cwds: [String]) async throws -> [ApprovalObserverCodexHook] {
        let result = try await request(
            method: "hooks/list",
            params: .object(["cwds": .array(cwds.map(JSONValue.string))])
        )
        guard let data = result.objectValue?["data"]?.arrayValue else { throw ApprovalObserverIntegrationError.codexUnavailable }
        var hooks: [ApprovalObserverCodexHook] = []
        for value in data {
            guard let container = value.objectValue,
                  let rawHooks = container["hooks"]?.arrayValue else { throw ApprovalObserverIntegrationError.codexUnavailable }
            for rawHook in rawHooks {
                guard let object = rawHook.objectValue,
                      let key = object["key"]?.stringValue,
                      let eventName = object["eventName"]?.stringValue,
                      let handlerType = object["handlerType"]?.stringValue,
                      let command = object["command"]?.stringValue,
                      let sourcePath = object["sourcePath"]?.stringValue,
                      let source = object["source"]?.stringValue,
                      let enabled = object["enabled"].flatMap(boolValue),
                      let currentHash = object["currentHash"]?.stringValue,
                      let trustStatus = object["trustStatus"]?.stringValue else { throw ApprovalObserverIntegrationError.codexUnavailable }
                hooks.append(ApprovalObserverCodexHook(key: key, eventName: eventName, handlerType: handlerType, command: command, sourcePath: sourcePath, source: source, enabled: enabled, currentHash: currentHash, trustStatus: ApprovalObserverHookTrustStatus(rawValue: trustStatus)))
            }
        }
        return hooks
    }

    func close() async {
        let current = client
        client = nil
        await current?.close()
    }

    private func request(method: String, params: JSONValue?) async throws -> JSONValue {
        let client = try await connectedClient()
        do {
            return try await client.request(method: method, params: params)
        } catch let error as ApprovalObserverIntegrationError {
            throw error
        } catch let error as JSONRPCTransportError {
            if case .protocolError = error { throw error }
            throw ApprovalObserverIntegrationError.codexUnavailable
        } catch {
            throw ApprovalObserverIntegrationError.codexUnavailable
        }
    }

    private func connectedClient() async throws -> JSONRPCClient {
        if let client { return client }
        do {
            let executable = try executableResolver.resolve()
            let descriptor = AdapterDescriptor(
                adapterID: AdapterID("approval-observer-integration")!,
                adapterVersion: AdapterVersion("v1")!,
                sourceKind: .monitorOwnedRuntime,
                sourceID: SourceID("codex-approval-observer")!,
                capabilitySnapshot: CapabilitySnapshot([.ownedRuntimeProvenance: .snapshot]),
                evidenceMetadata: EvidenceMetadata(
                    evidenceRun: "appManagedApprovalObserver",
                    cliVersion: "installedCodex",
                    historicalTransportEvidenceLabel: "existingBundledStdio",
                    probeOrHarnessAvailability: "runtime",
                    sanitizerAvailability: "frozenJournalContract",
                    sanitizerVersion: "v1",
                    confidence: "internalOnly",
                    limitations: "appServerConfigAndHooksOnly",
                    forwardTransportDecision: "bundledStdio"
                )
            )
            let runtimeID = RuntimeInstanceID("approval-observer-integration")!
            let lifecycle = LifecycleEpoch(UUID().uuidString)!
            let rpc = JSONRPCClient(
                channel: BundledCodexStdioChannel(executableURL: executable),
                binding: try JSONRPCClientBinding(descriptor: descriptor, runtimeInstanceID: runtimeID, lifecycleEpoch: lifecycle),
                clientInfo: JSONRPCClientInfo(name: "codex_monitor_approval_observer", title: "Codex Monitor Approval Observer", version: "v1")
            )
            _ = try await rpc.connect()
            client = rpc
            return rpc
        } catch let error as ApprovalObserverIntegrationError {
            throw error
        } catch {
            throw ApprovalObserverIntegrationError.codexUnavailable
        }
    }
}

private func boolValue(_ value: JSONValue?) -> Bool? {
    guard case .bool(let value) = value else { return nil }
    return value
}

private extension JSONValue {
    var arrayValue: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
}

// MARK: - Integration lifecycle

enum ApprovalObserverIntegrationState: String, Sendable, Equatable {
    case inactive
    case active
    case unavailable
}

struct ApprovalObserverIntegrationHealth: Sendable, Equatable {
    let state: ApprovalObserverIntegrationState
    let reason: String?
    let ownedHandlerCount: Int
}

private struct AppOwnedApprovalObserverReceipt: Codable, Sendable, Equatable {
    let schema: Int
    let releaseCommand: String
    let ownedCommands: [String]
    let keys: [String: String]
    let hashes: [String: String]

    init(releaseCommand: String, ownedCommands: [String], keys: [String: String], hashes: [String: String]) {
        schema = 1
        self.releaseCommand = releaseCommand
        self.ownedCommands = ownedCommands.sorted()
        self.keys = keys
        self.hashes = hashes
    }
}

/// The sole app-managed boundary.  It owns only the minimum installation,
/// reconciliation, trust, and source-health operations needed by the existing
/// “等待授权通知” preference.  It never changes reducer/lifecycle semantics.
actor ApprovalObserverIntegration {
    let journalSource: AppManagedHookApprovalJournalSource
    let identityResolver: AppManagedHookApprovalIdentityResolver

    private let paths: AppOwnedApprovalObserverPaths
    private let installer: AppOwnedApprovalObserverReleaseInstaller
    private let codex: any ApprovalObserverCodexAPI
    private let onIntentRegistered: (@Sendable (Bool) -> Void)?
    private var currentRelease: AppOwnedApprovalObserverRelease?
    private var healthValue = ApprovalObserverIntegrationHealth(state: .inactive, reason: nil, ownedHandlerCount: 0)
    private var desiredEnabled = false
    private var intentGeneration: UInt64 = 0
    private var transitionTask: Task<Bool, Never>?

    init(
        paths: AppOwnedApprovalObserverPaths = .default,
        helperExecutableURL: URL? = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/Helpers/ApprovalObserver"),
        signatureVerifier: @escaping @Sendable (URL) -> Bool = { url in
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
                  let code else { return false }
            return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess
        },
        codex: (any ApprovalObserverCodexAPI)? = nil,
        journalSource: AppManagedHookApprovalJournalSource? = nil,
        identityResolver: AppManagedHookApprovalIdentityResolver? = nil,
        onIntentRegistered: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.paths = paths
        installer = AppOwnedApprovalObserverReleaseInstaller(paths: paths, helperExecutableURL: helperExecutableURL, signatureVerifier: signatureVerifier)
        self.codex = codex ?? AppServerApprovalObserverCodexClient()
        self.journalSource = journalSource ?? AppManagedHookApprovalJournalSource(journalURL: paths.journalURL)
        self.identityResolver = identityResolver ?? AppManagedHookApprovalIdentityResolver(identityKeyURL: paths.identityKeyURL)
        self.onIntentRegistered = onIntentRegistered
    }

    func inspect() async -> ApprovalObserverIntegrationHealth {
        do {
            let config = try await codex.readConfig()
            let hooks = try await codex.listHooks(cwds: [paths.codexHomeURL.path])
            await codex.close()
            let owned = ownedHooks(in: hooks, releaseCommand: currentRelease?.command)
            let complete = owned.count == ApprovalObserverHookEvent.allCases.count
                && Set(owned.map(\.eventName)) == Set(ApprovalObserverHookEvent.allCases.map(\.appServerName))
                && owned.allSatisfy { $0.enabled && $0.trustStatus == .trusted }
            healthValue = ApprovalObserverIntegrationHealth(state: config.hooksEnabled && complete ? .active : .inactive, reason: nil, ownedHandlerCount: owned.count)
            return healthValue
        } catch {
            await codex.close()
            healthValue = unavailableHealth(for: error)
            return healthValue
        }
    }

    @discardableResult
    func activate() async -> Bool {
        await reconcile(enabled: true)
    }

    @discardableResult
    private func performActivate(generation: UInt64) async -> Bool {
        var previousReceipt: AppOwnedApprovalObserverReceipt?
        do {
            try ensureCurrent(generation: generation, enabled: true)
            let installedRelease = try installer.ensureRelease()
            try ensureCurrent(generation: generation, enabled: true)
            currentRelease = installedRelease
            previousReceipt = try loadReceipt()
            let knownOwned = Set(previousReceipt?.ownedCommands ?? [])
            let isUpdate = previousReceipt.map { $0.releaseCommand != installedRelease.command } ?? false
            _ = try await writeConfigurationWithRetry(generation: generation, enabled: true) { config in
                var edits = try AppOwnedInlineHookConfigurationEditor(
                    ownedCommands: knownOwned.union([installedRelease.command]),
                    ownedPathPrefix: self.paths.versionsURL.standardizedFileURL.path
                ).installing(
                    hooks: config.hooks,
                    command: installedRelease.command,
                    preserveExistingOwned: isUpdate
                )
                if !config.hooksEnabled {
                    edits.append(ApprovalObserverConfigEdit(keyPath: "features.hooks", value: .bool(true)))
                }
                return edits
            }
            try ensureCurrent(generation: generation, enabled: true)

            let discovered = try await codex.listHooks(cwds: [paths.codexHomeURL.path])
            try ensureCurrent(generation: generation, enabled: true)
            _ = try requireOwnedHooks(discovered, releaseCommand: installedRelease.command)
            try await trustIfNeeded(releaseCommand: installedRelease.command, generation: generation)
            try ensureCurrent(generation: generation, enabled: true)

            let verifiedBeforeRetirement = try await codex.listHooks(cwds: [paths.codexHomeURL.path])
            try ensureCurrent(generation: generation, enabled: true)
            let trustedBeforeRetirement = try requireOwnedHooks(verifiedBeforeRetirement, releaseCommand: installedRelease.command)
            guard trustedBeforeRetirement.allSatisfy({ $0.enabled && $0.trustStatus == .trusted }) else {
                throw ApprovalObserverIntegrationError.hooksNotReady
            }
            if let previousReceipt, previousReceipt.releaseCommand != installedRelease.command {
                // Only after the new release is trusted do we retire the
                // previous command. The old immutable release file remains
                // untouched and can still support a safe future rollback.
                try ensureCurrent(generation: generation, enabled: true)
                _ = try await writeConfigurationWithRetry(generation: generation, enabled: true) { config in
                    try AppOwnedInlineHookConfigurationEditor(
                        ownedCommands: Set(previousReceipt.ownedCommands)
                    ).removing(hooks: config.hooks)
                }
            }
            // Removing an older group can change Codex's handler indexes and
            // therefore its generated key/current_hash. Re-list and re-trust
            // once more after retirement before declaring the installation
            // active.
            let afterRetirement = try await codex.listHooks(cwds: [paths.codexHomeURL.path])
            try ensureCurrent(generation: generation, enabled: true)
            _ = try requireOwnedHooks(afterRetirement, releaseCommand: installedRelease.command)
            try await trustIfNeeded(releaseCommand: installedRelease.command, generation: generation)
            try ensureCurrent(generation: generation, enabled: true)
            let verified = try await codex.listHooks(cwds: [paths.codexHomeURL.path])
            try ensureCurrent(generation: generation, enabled: true)
            let finalOwned = try requireOwnedHooks(verified, releaseCommand: installedRelease.command)
            guard finalOwned.allSatisfy({ $0.enabled && $0.trustStatus == .trusted }) else {
                throw ApprovalObserverIntegrationError.hooksNotReady
            }
            let newReceipt = AppOwnedApprovalObserverReceipt(
                releaseCommand: installedRelease.command,
                ownedCommands: [installedRelease.command],
                keys: Dictionary(uniqueKeysWithValues: finalOwned.map { ($0.eventName, $0.key) }),
                hashes: Dictionary(uniqueKeysWithValues: finalOwned.map { ($0.eventName, $0.currentHash) })
            )
            try ensureCurrent(generation: generation, enabled: true)
            try saveReceipt(newReceipt)
            try ensureCurrent(generation: generation, enabled: true)
            await codex.close()
            try ensureCurrent(generation: generation, enabled: true)
            journalSource.setActive(true)
            healthValue = ApprovalObserverIntegrationHealth(state: .active, reason: nil, ownedHandlerCount: finalOwned.count)
            return true
        } catch {
            journalSource.setActive(false)
            let wasSuperseded = (error as? ApprovalObserverIntegrationError) == .superseded
            let wasStale = wasSuperseded || generation != intentGeneration || !desiredEnabled
            await codex.close()
            guard !wasStale, generation == intentGeneration, desiredEnabled else { return false }
            healthValue = unavailableHealth(for: error)
            return false
        }
    }

    @discardableResult
    func deactivate() async -> Bool {
        await reconcile(enabled: false)
    }

    @discardableResult
    private func performDeactivate(generation: UInt64) async -> Bool {
        journalSource.setActive(false)
        do {
            try ensureCurrent(generation: generation, enabled: false)
            let knownOwnedCommands = Set(try loadReceipt()?.ownedCommands ?? [])
            _ = try await writeConfigurationWithRetry(generation: generation, enabled: false) { config in
                try AppOwnedInlineHookConfigurationEditor(
                    ownedCommands: knownOwnedCommands,
                    ownedPathPrefix: self.paths.versionsURL.standardizedFileURL.path
                ).removing(hooks: config.hooks, includeAllAppOwned: true)
            }
            try ensureCurrent(generation: generation, enabled: false)
            // The global feature is deliberately left alone.  A user-owned
            // Hook may depend on it, and C2 never disables unrelated behavior.
            healthValue = ApprovalObserverIntegrationHealth(state: .inactive, reason: nil, ownedHandlerCount: 0)
            return true
        } catch {
            if (error as? ApprovalObserverIntegrationError) == .superseded { return false }
            healthValue = unavailableHealth(for: error)
            return false
        }
    }

    @discardableResult
    func reconcile(enabled: Bool) async -> Bool {
        desiredEnabled = enabled
        intentGeneration &+= 1
        onIntentRegistered?(enabled)

        let task: Task<Bool, Never>
        if let transitionTask {
            task = transitionTask
        } else {
            let created = Task { [weak self] in
                guard let self else { return false }
                return await self.drainTransitions()
            }
            transitionTask = created
            task = created
        }
        return await task.value
    }

    func health() -> ApprovalObserverIntegrationHealth { healthValue }

    private func drainTransitions() async -> Bool {
        while true {
            let generation = intentGeneration
            let enabled = desiredEnabled
            let result = enabled
                ? await performActivate(generation: generation)
                : await performDeactivate(generation: generation)
            guard generation == intentGeneration, enabled == desiredEnabled else { continue }
            transitionTask = nil
            return result
        }
    }

    private func ensureCurrent(generation: UInt64, enabled: Bool) throws {
        guard generation == intentGeneration, desiredEnabled == enabled else {
            throw ApprovalObserverIntegrationError.superseded
        }
    }

    private func writeConfigurationWithRetry(
        generation: UInt64,
        enabled: Bool,
        editsFor: @Sendable (ApprovalObserverCodexConfig) throws -> [ApprovalObserverConfigEdit]
    ) async throws -> ApprovalObserverCodexConfig {
        for attempt in 0..<3 {
            try ensureCurrent(generation: generation, enabled: enabled)
            let current = try await codex.readConfig()
            try ensureCurrent(generation: generation, enabled: enabled)
            let edits = try editsFor(current)
            try ensureCurrent(generation: generation, enabled: enabled)
            guard !edits.isEmpty else { return current }
            do {
                _ = try await codex.writeConfig(edits: edits, expectedVersion: current.version)
            } catch let error as ApprovalObserverIntegrationError {
                guard error == .configurationConflict else { throw error }
                try ensureCurrent(generation: generation, enabled: enabled)
                if attempt == 2 { throw error }
                continue
            }
            try ensureCurrent(generation: generation, enabled: enabled)
            // The write response contains a new version on supported Codex
            // releases.  Read again nevertheless so the next mutation uses
            // both the authoritative version and the current merged content.
            let refreshed = try await codex.readConfig()
            try ensureCurrent(generation: generation, enabled: enabled)
            return refreshed
        }
        throw ApprovalObserverIntegrationError.configurationConflict
    }

    private func trustIfNeeded(releaseCommand: String, generation: UInt64) async throws {
        for attempt in 0..<3 {
            try ensureCurrent(generation: generation, enabled: true)
            let discovered = try await codex.listHooks(cwds: [paths.codexHomeURL.path])
            try ensureCurrent(generation: generation, enabled: true)
            let owned = try requireOwnedHooks(discovered, releaseCommand: releaseCommand)
            let pendingTrust = owned.filter { $0.trustStatus != .trusted }
            guard !pendingTrust.isEmpty else { return }

            let configForTrust = try await codex.readConfig()
            try ensureCurrent(generation: generation, enabled: true)
            let edits = pendingTrust.map { hook in
                ApprovalObserverConfigEdit(
                    keyPath: trustedHashKeyPath(for: hook.key),
                    value: .string(hook.currentHash)
                )
            }
            do {
                _ = try await codex.writeConfig(edits: edits, expectedVersion: configForTrust.version)
            } catch let error as ApprovalObserverIntegrationError {
                guard error == .configurationConflict else {
                    throw ApprovalObserverIntegrationError.trustWriteFailed
                }
                try ensureCurrent(generation: generation, enabled: true)
                if attempt == 2 { throw error }
                continue
            } catch {
                throw ApprovalObserverIntegrationError.trustWriteFailed
            }
            try ensureCurrent(generation: generation, enabled: true)
            // Establish the new version before any later trust or retirement
            // mutation.  The next loop also rediscovers keys/current hashes.
            _ = try await codex.readConfig()
            try ensureCurrent(generation: generation, enabled: true)
            return
        }
        throw ApprovalObserverIntegrationError.configurationConflict
    }

    private func requireOwnedHooks(_ hooks: [ApprovalObserverCodexHook], releaseCommand: String) throws -> [ApprovalObserverCodexHook] {
            let appOwned = ownedHooks(in: hooks, releaseCommand: releaseCommand).filter { $0.command == releaseCommand }
            guard appOwned.count == ApprovalObserverHookEvent.allCases.count,
              Set(appOwned.map(\.eventName)) == Set(ApprovalObserverHookEvent.allCases.map(\.appServerName)),
              appOwned.allSatisfy({ $0.command == releaseCommand && isOurHooksPath($0.sourcePath) && $0.source == "user" && $0.handlerType == "command" }),
              Set(appOwned.map(\.eventName)).count == ApprovalObserverHookEvent.allCases.count else {
            throw ApprovalObserverIntegrationError.hooksNotReady
        }
        return appOwned
    }

    private func ownedHooks(in hooks: [ApprovalObserverCodexHook], releaseCommand: String?) -> [ApprovalObserverCodexHook] {
        hooks.filter { hook in
            guard isOurHooksPath(hook.sourcePath),
                  hook.source == "user",
                  hook.handlerType == "command",
                  Set(ApprovalObserverHookEvent.allCases.map(\.appServerName)).contains(hook.eventName) else { return false }
            if let releaseCommand { return hook.command == releaseCommand || isAppOwnedCommand(hook.command) }
            return isAppOwnedCommand(hook.command)
        }
    }

    private func isOurHooksPath(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path == paths.codexHomeURL
            .appendingPathComponent("config.toml")
            .standardizedFileURL.path
    }

    private func isAppOwnedCommand(_ command: String) -> Bool {
        guard let path = unquotedShellPath(command) else { return false }
        let versionsPrefix = paths.versionsURL.standardizedFileURL.path + "/"
        return path.hasPrefix(versionsPrefix)
    }

    private func trustedHashKeyPath(for key: String) -> String {
        // Codex keys contain dots. Quoting the whole
        // dynamic table key is required for config/batchWrite to persist the
        // exact Codex-returned key rather than splitting it into TOML segments.
        let escaped = key
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "hooks.state.\"\(escaped)\".trusted_hash"
    }

    private func loadReceipt() throws -> AppOwnedApprovalObserverReceipt? {
        guard FileManager.default.fileExists(atPath: paths.receiptURL.path) else { return nil }
        return try JSONDecoder().decode(AppOwnedApprovalObserverReceipt.self, from: Data(contentsOf: paths.receiptURL))
    }

    private func saveReceipt(_ receipt: AppOwnedApprovalObserverReceipt) throws {
        let directory = paths.receiptURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(receipt)
        let temporary = directory.appendingPathComponent(".installation-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            if FileManager.default.fileExists(atPath: paths.receiptURL.path) {
                _ = try FileManager.default.replaceItemAt(paths.receiptURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: paths.receiptURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func unavailableHealth(for error: Error) -> ApprovalObserverIntegrationHealth {
        let reason: String
        switch error {
        case ApprovalObserverIntegrationError.malformedHooks: reason = "malformedHooks"
        case ApprovalObserverIntegrationError.configurationConflict: reason = "configurationConflict"
        case ApprovalObserverIntegrationError.trustWriteFailed: reason = "trustWriteFailed"
        case ApprovalObserverIntegrationError.releaseUnavailable, ApprovalObserverIntegrationError.releaseCollision: reason = "releaseUnavailable"
        case ApprovalObserverIntegrationError.hooksNotReady: reason = "hooksNotReady"
        case ApprovalObserverIntegrationError.unsupportedCapability: reason = "unsupportedCapability"
        default: reason = "codexUnavailable"
        }
        return ApprovalObserverIntegrationHealth(state: .unavailable, reason: reason, ownedHandlerCount: 0)
    }
}
