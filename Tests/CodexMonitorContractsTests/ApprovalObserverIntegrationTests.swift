import CryptoKit
import Foundation
import XCTest
@testable import CodexMonitorApp
@testable import CodexMonitorContracts

final class ApprovalObserverIntegrationTests: XCTestCase {
    func testActivationUsesInlineCASInstallsExactlyThreeHandlersAndTrustsOnlyThem() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        await fixture.fake.seedTrust(key: "unrelated.user.hook", hash: "sha256:unrelated")
        await fixture.fake.seedUserHooks(command: "/usr/local/bin/user-approval")

        let activated = await fixture.integration().activate()
        XCTAssertTrue(activated)
        let hooksEnabled = await fixture.fake.hooksEnabled()
        XCTAssertTrue(hooksEnabled)

        let hooks = try await fixture.fake.listHooks(cwds: [fixture.paths.codexHomeURL.path])
        let owned = hooks.filter { $0.command.contains("ApprovalObserver") }
        XCTAssertEqual(owned.count, 3)
        XCTAssertEqual(Set(owned.map(\.eventName)), Set(ApprovalObserverHookEvent.allCases.map(\.appServerName)))
        XCTAssertTrue(owned.allSatisfy { $0.enabled && $0.trustStatus == .trusted })
        XCTAssertTrue(hooks.contains { $0.command == "/usr/local/bin/user-approval" })
        let trustedHashes = await fixture.fake.trustedHashes()
        XCTAssertEqual(trustedHashes["unrelated.user.hook"], "sha256:unrelated")
        let rejectedWriteCount = await fixture.fake.rejectedWriteCount()
        XCTAssertEqual(rejectedWriteCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.codexHomeURL.appendingPathComponent("hooks.json").path))

        let writes = await fixture.fake.successfulWrites()
        XCTAssertGreaterThanOrEqual(writes.count, 2)
        XCTAssertEqual(writes[0].expectedVersion, "v1")
        XCTAssertTrue(writes[0].edits.contains { $0.keyPath == "hooks.PermissionRequest" })
        XCTAssertTrue(writes[0].edits.contains { $0.keyPath == "hooks.PostToolUse" })
        XCTAssertTrue(writes[0].edits.contains { $0.keyPath == "hooks.Stop" })
        XCTAssertTrue(writes[1].edits.allSatisfy { $0.keyPath.hasPrefix("hooks.state.\"") })
        XCTAssertEqual(writes[1].expectedVersion, "v2")
    }

    func testActivationConflictIsRejectedBeforeMutationThenRereadsAndRetries() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        await fixture.fake.scheduleConflictAddingUserHook(command: "/user/added-between-read-and-write", revision: "user-v2")

        let activated = await fixture.integration().activate()
        XCTAssertTrue(activated)
        let rejectedWriteCount = await fixture.fake.rejectedWriteCount()
        XCTAssertGreaterThan(rejectedWriteCount, 0)
        let rejectedWithoutOwnedHandlers = await fixture.fake.lastRejectedSnapshotContainsNoOwnedHandlers()
        XCTAssertTrue(rejectedWithoutOwnedHandlers)

        let hooks = try await fixture.fake.listHooks(cwds: [fixture.paths.codexHomeURL.path])
        XCTAssertTrue(hooks.contains { $0.command == "/user/added-between-read-and-write" })
        XCTAssertEqual(hooks.filter { $0.command.contains("ApprovalObserver") }.count, 3)
        let externalRevision = await fixture.fake.externalRevision()
        XCTAssertEqual(externalRevision, "user-v2")
        let ownedCount = await fixture.fake.countOwnedHandlers()
        XCTAssertEqual(ownedCount, 3)
    }

    func testTrustUsesFreshVersionAfterInstallAndOnlyCodexReturnedMetadata() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        await fixture.fake.seedUserHooks(command: "/user/untrusted")

        let activated = await fixture.integration().activate()
        XCTAssertTrue(activated)
        let writes = await fixture.fake.successfulWrites()
        XCTAssertGreaterThanOrEqual(writes.count, 2)
        XCTAssertEqual(writes[0].expectedVersion, "v1")
        XCTAssertEqual(writes[1].expectedVersion, "v2")
        XCTAssertTrue(writes[1].edits.allSatisfy { $0.keyPath.hasPrefix("hooks.state.\"") && $0.value.stringValue?.hasPrefix("sha256:") == true })

        let hooks = try await fixture.fake.listHooks(cwds: [fixture.paths.codexHomeURL.path])
        XCTAssertEqual(hooks.first(where: { $0.command == "/user/untrusted" })?.trustStatus, .untrusted)
        XCTAssertTrue(hooks.filter { $0.command.contains("ApprovalObserver") }.allSatisfy { $0.trustStatus == .trusted })
    }

    func testRepeatedActivationIsIdempotentWithoutDuplicateOwnedHandlers() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let integration = fixture.integration()

        let activated = await integration.activate()
        XCTAssertTrue(activated)
        let firstWrites = await fixture.fake.successfulWrites().count
        let reconciled = await integration.reconcile(enabled: true)
        XCTAssertTrue(reconciled)
        let secondWrites = await fixture.fake.successfulWrites().count
        XCTAssertEqual(secondWrites, firstWrites)
        let ownedCount = await fixture.fake.countOwnedHandlers()
        XCTAssertEqual(ownedCount, 3)
    }

    func testDeactivationUsesCASRemovesOnlyOwnedInlineHandlersAndPreservesUserConfig() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        await fixture.fake.seedUserHooks(command: "/user/permission")
        let activated = await fixture.integration().activate()
        XCTAssertTrue(activated)

        await fixture.fake.scheduleConflictAddingUserHook(command: "/user/modified-during-deactivation", revision: "user-deactivate-v2")
        let deactivated = await fixture.integration().deactivate()
        XCTAssertTrue(deactivated)
        let rejectedWriteCount = await fixture.fake.rejectedWriteCount()
        XCTAssertGreaterThan(rejectedWriteCount, 0)

        let hooks = try await fixture.fake.listHooks(cwds: [fixture.paths.codexHomeURL.path])
        XCTAssertFalse(hooks.contains { $0.command.contains("ApprovalObserver") })
        XCTAssertTrue(hooks.contains { $0.command == "/user/permission" })
        XCTAssertTrue(hooks.contains { $0.command == "/user/modified-during-deactivation" })
        let externalRevision = await fixture.fake.externalRevision()
        XCTAssertEqual(externalRevision, "user-deactivate-v2")
        let unrelatedValue = await fixture.fake.unrelatedValue()
        XCTAssertEqual(unrelatedValue, .object(["keep": .bool(true)]))
        let hooksEnabled = await fixture.fake.hooksEnabled()
        XCTAssertTrue(hooksEnabled)
        XCTAssertFalse(fixture.source.isActive)
    }

    func testStartupReconcileMergesCurrentExternalConfigInsteadOfOverwritingIt() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        await fixture.fake.seedUserHooks(command: "/user/before-launch")
        await fixture.fake.setUnrelatedValue(.object(["nested": .bool(true)]))

        let reconciled = await fixture.integration().reconcile(enabled: true)
        XCTAssertTrue(reconciled)
        let hooks = try await fixture.fake.listHooks(cwds: [fixture.paths.codexHomeURL.path])
        XCTAssertTrue(hooks.contains { $0.command == "/user/before-launch" })
        let unrelatedValue = await fixture.fake.unrelatedValue()
        XCTAssertEqual(unrelatedValue, .object(["nested": .bool(true)]))
        let ownedCount = await fixture.fake.countOwnedHandlers()
        XCTAssertEqual(ownedCount, 3)
    }

    func testObserverPayloadUpdateUsesNewInlinePathAndRequiresNewTrust() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let installer = AppOwnedApprovalObserverReleaseInstaller(paths: fixture.paths, helperExecutableURL: fixture.executable, signatureVerifier: { _ in true })

        let activated = await fixture.integration().activate()
        XCTAssertTrue(activated)
        let v1 = try installer.ensureRelease()
        let v1Hooks = try await fixture.fake.listHooks(cwds: [fixture.paths.codexHomeURL.path])
        let v1Command = try XCTUnwrap(v1Hooks.first(where: { $0.eventName == "permissionRequest" })?.command)
        let writesAfterV1 = await fixture.fake.successfulWrites().count

        try Data("#!/bin/sh\n# changed observer payload\nexit 0\n".utf8).write(to: fixture.executable, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.executable.path)
        let v2 = try installer.ensureRelease()
        XCTAssertNotEqual(v1.version, v2.version)
        XCTAssertNotEqual(v1.command, v2.command)

        let updated = await fixture.integration().activate()
        XCTAssertTrue(updated)
        let v2Hooks = try await fixture.fake.listHooks(cwds: [fixture.paths.codexHomeURL.path])
        let v2Owned = v2Hooks.filter { $0.command.contains("ApprovalObserver") }
        XCTAssertFalse(v2Owned.contains { $0.command == v1Command })
        XCTAssertEqual(v2Owned.count, 3)
        XCTAssertTrue(v2Owned.allSatisfy { $0.command == v2.command && $0.trustStatus == .trusted })
        let writesAfterV2 = await fixture.fake.successfulWrites().count
        XCTAssertGreaterThan(writesAfterV2, writesAfterV1)
    }

    func testReleaseInstallerCopiesDedicatedHelperDirectlyWithoutWrapper() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let helperBytes = try Data(contentsOf: fixture.executable)
        let installer = AppOwnedApprovalObserverReleaseInstaller(paths: fixture.paths, helperExecutableURL: fixture.executable, signatureVerifier: { _ in true })

        let release = try installer.ensureRelease()

        XCTAssertEqual(release.executableURL, release.payloadURL)
        XCTAssertEqual(try Data(contentsOf: release.payloadURL), helperBytes)
        XCTAssertEqual(release.command, "'\(release.payloadURL.path)'")
        XCTAssertFalse(release.command.contains(".sh"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: release.directoryURL.appendingPathComponent("observer.sh").path))
    }

    func testReleaseInstallerRejectsHelperWithoutStrictSignature() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let installer = AppOwnedApprovalObserverReleaseInstaller(paths: fixture.paths, helperExecutableURL: fixture.executable, signatureVerifier: { _ in false })

        XCTAssertThrowsError(try installer.ensureRelease()) { error in
            XCTAssertEqual(error as? ApprovalObserverIntegrationError, .releaseSignatureInvalid)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.versionsURL.path))
    }

    func testOnThenImmediateOffWhileActivationIsSuspendedLeavesObserverOff() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let gate = AsyncGate()
        let probe = IntentProbe()
        await fixture.fake.setReadConfigGate(gate)
        let integration = fixture.integration(onIntentRegistered: { enabled in
            Task { await probe.record(enabled) }
        })

        let onTask = Task { await integration.reconcile(enabled: true) }
        await gate.waitUntilEntered()
        let offTask = Task { await integration.reconcile(enabled: false) }
        await probe.waitFor(false)
        await gate.release()

        let onResult = await onTask.value
        let offResult = await offTask.value
        XCTAssertTrue(onResult)
        XCTAssertTrue(offResult)
        XCTAssertFalse(fixture.source.isActive)
        let health = await integration.health()
        XCTAssertEqual(health.state, .inactive)
        let ownedCount = await fixture.fake.countOwnedHandlers()
        XCTAssertEqual(ownedCount, 0)
    }

    func testOnOffOnRapidlyFinalOnIntentWins() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let gate = AsyncGate()
        let probe = IntentProbe()
        await fixture.fake.setReadConfigGate(gate)
        let integration = fixture.integration(onIntentRegistered: { enabled in
            Task { await probe.record(enabled) }
        })

        let firstOn = Task { await integration.reconcile(enabled: true) }
        await gate.waitUntilEntered()
        let off = Task { await integration.reconcile(enabled: false) }
        await probe.waitFor(false)
        let finalOn = Task { await integration.reconcile(enabled: true) }
        await probe.waitFor(true, occurrence: 2)
        await gate.release()

        let firstOnResult = await firstOn.value
        let offResult = await off.value
        let finalOnResult = await finalOn.value
        XCTAssertTrue(firstOnResult)
        XCTAssertTrue(offResult)
        XCTAssertTrue(finalOnResult)
        XCTAssertTrue(fixture.source.isActive)
        let ownedCount = await fixture.fake.countOwnedHandlers()
        XCTAssertEqual(ownedCount, 3)
        let hooks = try await fixture.fake.listHooks(cwds: [fixture.paths.codexHomeURL.path])
        XCTAssertTrue(hooks.filter { $0.command.contains("ApprovalObserver") }.allSatisfy { $0.trustStatus == .trusted })
    }

    func testStaleStartupReconcileFollowedByOffCannotResurrectObserver() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let gate = AsyncGate()
        let probe = IntentProbe()
        await fixture.fake.setReadConfigGate(gate)
        let integration = fixture.integration(onIntentRegistered: { enabled in
            Task { await probe.record(enabled) }
        })

        let startup = Task { await integration.reconcile(enabled: true) }
        await gate.waitUntilEntered()
        let off = Task { await integration.reconcile(enabled: false) }
        await probe.waitFor(false)
        await gate.release()

        _ = await startup.value
        _ = await off.value
        XCTAssertFalse(fixture.source.isActive)
        let health = await integration.health()
        XCTAssertEqual(health.state, .inactive)
        let ownedCount = await fixture.fake.countOwnedHandlers()
        XCTAssertEqual(ownedCount, 0)
    }

    func testMalformedInlineHooksAndTrustFailureNeverShowActive() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        await fixture.fake.setHooksValue(.string("not-an-inline-hook-object"))
        let malformedIntegration = fixture.integration()
        let malformedActivated = await malformedIntegration.activate()
        XCTAssertFalse(malformedActivated)
        let malformedHealth = await malformedIntegration.health()
        XCTAssertEqual(malformedHealth.state, .unavailable)
        XCTAssertFalse(fixture.source.isActive)

        await fixture.fake.setHooksValue(.object([:]))
        await fixture.fake.setFailTrustWrites(true)
        let trustFailure = fixture.integration()
        let trustActivated = await trustFailure.activate()
        XCTAssertFalse(trustActivated)
        let trustHealth = await trustFailure.health()
        XCTAssertEqual(trustHealth.reason, "trustWriteFailed")
        XCTAssertFalse(fixture.source.isActive)
    }

    func testOversizedObserverPayloadFailsOpenWithoutWriting() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        fixture.source.setActive(true)
        let oversized = Data(repeating: 0x78, count: ApprovalObserverHookRunner.maximumInputBytes + 1)

        XCTAssertFalse(ApprovalObserverHookRunner.run(input: oversized, paths: fixture.paths, keyMaterial: Data("test-key-material".utf8)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
    }

    func testAppOwnedJournalFeedsFrozenHookReaderAndRejectsPreToolUse() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        fixture.source.setActive(true)
        let key = Data("test-observer-key".utf8)
        let input = Data("{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"raw-session-123\",\"turn_id\":\"raw-turn-456\",\"prompt\":\"must-not-persist\"}".utf8)

        XCTAssertTrue(ApprovalObserverHookRunner.run(input: input, paths: fixture.paths, keyMaterial: key))
        XCTAssertFalse(ApprovalObserverHookRunner.run(input: Data("{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"raw-session-123\",\"turn_id\":\"raw-turn-456\"}".utf8), paths: fixture.paths, keyMaterial: key))

        let records = try fixture.source.readRecords()
        XCTAssertEqual(records.count, 1)
        let journalText = String(decoding: records[0], as: UTF8.self)
        XCTAssertFalse(journalText.contains("raw-session-123"))
        XCTAssertFalse(journalText.contains("raw-turn-456"))
        XCTAssertFalse(journalText.contains("must-not-persist"))
        let diagnostics = try String(contentsOf: fixture.paths.diagnosticURL)
        XCTAssertTrue(diagnostics.contains("event_appended"))
        XCTAssertFalse(diagnostics.contains("raw-session-123"))
        XCTAssertFalse(diagnostics.contains("raw-turn-456"))
        XCTAssertFalse(diagnostics.contains("must-not-persist"))
        XCTAssertEqual(HookApprovalJournalReader().ingest(records).events.count, 1)
    }

    private struct Fixture {
        let root: URL
        let paths: AppOwnedApprovalObserverPaths
        let executable: URL
        let fake: FakeApprovalObserverAPI
        let source: AppManagedHookApprovalJournalSource

        func integration(onIntentRegistered: (@Sendable (Bool) -> Void)? = nil) -> ApprovalObserverIntegration {
            ApprovalObserverIntegration(
                paths: paths,
                helperExecutableURL: executable,
                signatureVerifier: { _ in true },
                codex: fake,
                journalSource: source,
                onIntentRegistered: onIntentRegistered
            )
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    private actor AsyncGate {
        private var blocked = true
        private var entered = false
        private var entryWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if !entered {
                entered = true
                let waiters = entryWaiters
                entryWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
            guard blocked else { return }
            await withCheckedContinuation { releaseWaiters.append($0) }
        }

        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { entryWaiters.append($0) }
        }

        func release() {
            blocked = false
            let waiters = releaseWaiters
            releaseWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    private actor IntentProbe {
        private var values: [Bool] = []
        private var waiters: [(Bool, Int, CheckedContinuation<Void, Never>)] = []

        func record(_ value: Bool) {
            values.append(value)
            let matching = waiters.filter { value == $0.0 && values.filter { $0 == value }.count >= $0.1 }
            waiters.removeAll { value == $0.0 && values.filter { $0 == value }.count >= $0.1 }
            matching.forEach { $0.2.resume() }
        }

        func waitFor(_ value: Bool, occurrence: Int = 1) async {
            if values.filter({ $0 == value }).count >= occurrence { return }
            await withCheckedContinuation { waiters.append((value, occurrence, $0)) }
        }
    }

    private actor FakeApprovalObserverAPI: ApprovalObserverCodexAPI {
        struct RecordedWrite: Sendable, Equatable {
            let expectedVersion: String
            let edits: [ApprovalObserverConfigEdit]
        }

        private enum Failure: Error { case trustWrite }
        private struct PendingConflict: Sendable {
            let command: String
            let revision: String
        }

        private let paths: AppOwnedApprovalObserverPaths
        private var versionNumber = 1
        private var configVersion = "v1"
        private var configuration: JSONValue = .object([
            "features": .object(["hooks": .bool(false)]),
            "hooks": .object([:]),
            "userSetting": .string("preserve-me"),
            "unrelated": .object(["keep": .bool(true)])
        ])
        private var trustByKey: [String: String] = [:]
        private var writes: [RecordedWrite] = []
        private var rejectedSnapshots: [JSONValue] = []
        private var failTrust = false
        private var unsupported = false
        private var pendingConflict: PendingConflict?
        private var readConfigGate: AsyncGate?

        init(paths: AppOwnedApprovalObserverPaths) { self.paths = paths }

        func readConfig() async throws -> ApprovalObserverCodexConfig {
            if let readConfigGate { await readConfigGate.wait() }
            if unsupported { throw ApprovalObserverIntegrationError.unsupportedCapability }
            guard let root = configuration.objectValue,
                  let features = root["features"]?.objectValue,
                  let enabled = features["hooks"].flatMap(jsonBoolValue),
                  let hooks = root["hooks"], hooks.objectValue != nil else {
                throw ApprovalObserverIntegrationError.malformedHooks
            }
            return ApprovalObserverCodexConfig(version: configVersion, hooksEnabled: enabled, hooks: hooks)
        }

        @discardableResult
        func writeConfig(edits: [ApprovalObserverConfigEdit], expectedVersion: String) async throws -> String {
            if let pendingConflict {
                self.pendingConflict = nil
                applyExternalChange(pendingConflict)
            }
            guard expectedVersion == configVersion else {
                rejectedSnapshots.append(configuration)
                throw ApprovalObserverIntegrationError.configurationConflict
            }
            if failTrust && edits.contains(where: { $0.keyPath.hasPrefix("hooks.state.") }) {
                throw Failure.trustWrite
            }
            for edit in edits { try apply(edit) }
            writes.append(RecordedWrite(expectedVersion: expectedVersion, edits: edits))
            advanceVersion()
            return configVersion
        }

        func listHooks(cwds: [String]) async throws -> [ApprovalObserverCodexHook] {
            guard let root = configuration.objectValue,
                  let enabled = root["features"]?.objectValue?["hooks"].flatMap(jsonBoolValue),
                  enabled,
                  let hooks = root["hooks"]?.objectValue else { return [] }
            var result: [ApprovalObserverCodexHook] = []
            for configName in hooks.keys.sorted() {
                guard let rawGroups = hooks[configName]?.arrayValue else { continue }
                let eventName = ApprovalObserverHookEvent.allCases.first(where: { $0.configName == configName })?.appServerName
                    ?? (configName.isEmpty ? configName : configName.prefix(1).lowercased() + configName.dropFirst())
                for (groupIndex, rawGroup) in rawGroups.enumerated() {
                    guard let group = rawGroup.objectValue,
                          let rawHandlers = group["hooks"]?.arrayValue else { continue }
                    for (handlerIndex, rawHandler) in rawHandlers.enumerated() {
                        guard let handler = rawHandler.objectValue,
                              let command = handler["command"]?.stringValue else { continue }
                        let key = "\(eventName)-\(groupIndex)-\(handlerIndex)-\(command)"
                        let currentHash = hash(for: command + "\n" + eventName)
                        result.append(ApprovalObserverCodexHook(
                            key: key,
                            eventName: eventName,
                            handlerType: handler["type"]?.stringValue ?? "command",
                            command: command,
                            sourcePath: paths.codexHomeURL.appendingPathComponent("config.toml").path,
                            source: "user",
                            enabled: handler["enabled"].flatMap(jsonBoolValue) ?? true,
                            currentHash: currentHash,
                            trustStatus: trustByKey[key] == currentHash ? .trusted : .untrusted
                        ))
                    }
                }
            }
            return result
        }

        func close() async {}

        func seedTrust(key: String, hash: String) { trustByKey[key] = hash }
        func seedUserHooks(command: String) {
            var root = configuration.objectValue ?? [:]
            var hooks = root["hooks"]?.objectValue ?? [:]
            hooks["PermissionRequest"] = .array((hooks["PermissionRequest"]?.arrayValue ?? []) + [userGroup(command: command)])
            root["hooks"] = .object(hooks)
            configuration = .object(root)
        }
        func scheduleConflictAddingUserHook(command: String, revision: String) { pendingConflict = PendingConflict(command: command, revision: revision) }
        func setFailTrustWrites(_ value: Bool) { failTrust = value }
        func setUnsupported(_ value: Bool) { unsupported = value }
        func setHooksValue(_ value: JSONValue) {
            var root = configuration.objectValue ?? [:]
            root["hooks"] = value
            configuration = .object(root)
        }
        func setUnrelatedValue(_ value: JSONValue) {
            var root = configuration.objectValue ?? [:]
            root["unrelated"] = value
            configuration = .object(root)
        }
        func setReadConfigGate(_ gate: AsyncGate?) { readConfigGate = gate }
        func hooksEnabled() -> Bool { configuration.objectValue?["features"]?.objectValue?["hooks"].flatMap(jsonBoolValue) ?? false }
        func successfulWrites() -> [RecordedWrite] { writes }
        func rejectedWriteCount() -> Int { rejectedSnapshots.count }
        func lastRejectedSnapshotContainsNoOwnedHandlers() -> Bool {
            guard let snapshot = rejectedSnapshots.last,
                  let hooks = snapshot.objectValue?["hooks"]?.objectValue else { return true }
            return hooks.values.flatMap { $0.arrayValue ?? [] }.flatMap { $0.objectValue?["hooks"]?.arrayValue ?? [] }.allSatisfy {
                guard let command = $0.objectValue?["command"]?.stringValue else { return true }
                return !command.contains("ApprovalObserver")
            }
        }
        func countOwnedHandlers() -> Int {
            guard let hooks = configuration.objectValue?["hooks"]?.objectValue else { return 0 }
            return hooks.values.flatMap { $0.arrayValue ?? [] }.flatMap { $0.objectValue?["hooks"]?.arrayValue ?? [] }.filter {
                $0.objectValue?["command"]?.stringValue?.contains("ApprovalObserver") == true
            }.count
        }
        func trustedHashes() -> [String: String] { trustByKey }
        func externalRevision() -> String? { configuration.objectValue?["externalRevision"]?.stringValue }
        func unrelatedValue() -> JSONValue? { configuration.objectValue?["unrelated"] }

        private func apply(_ edit: ApprovalObserverConfigEdit) throws {
            guard var root = configuration.objectValue else { throw ApprovalObserverIntegrationError.malformedHooks }
            if edit.keyPath == "features.hooks" {
                guard case .bool = edit.value else { throw ApprovalObserverIntegrationError.malformedHooks }
                var features = root["features"]?.objectValue ?? [:]
                features["hooks"] = edit.value
                root["features"] = .object(features)
            } else if edit.keyPath.hasPrefix("hooks.state.") {
                guard let key = trustedKey(from: edit.keyPath), let hash = edit.value.stringValue else {
                    throw ApprovalObserverIntegrationError.malformedHooks
                }
                trustByKey[key] = hash
            } else if edit.keyPath.hasPrefix("hooks.") {
                let event = String(edit.keyPath.dropFirst("hooks.".count))
                guard ApprovalObserverHookEvent.allCases.contains(where: { $0.configName == event }), edit.value.arrayValue != nil else {
                    throw ApprovalObserverIntegrationError.malformedHooks
                }
                var hooks = root["hooks"]?.objectValue ?? [:]
                hooks[event] = edit.value
                root["hooks"] = .object(hooks)
            } else {
                throw ApprovalObserverIntegrationError.malformedHooks
            }
            configuration = .object(root)
        }

        private func applyExternalChange(_ change: PendingConflict) {
            var root = configuration.objectValue ?? [:]
            root["externalRevision"] = .string(change.revision)
            var hooks = root["hooks"]?.objectValue ?? [:]
            hooks["PermissionRequest"] = .array((hooks["PermissionRequest"]?.arrayValue ?? []) + [userGroup(command: change.command)])
            root["hooks"] = .object(hooks)
            configuration = .object(root)
            advanceVersion()
        }

        private func advanceVersion() {
            versionNumber += 1
            configVersion = "v\(versionNumber)"
        }

        private func userGroup(command: String) -> JSONValue {
            .object(["matcher": .string(".*"), "hooks": .array([.object(["type": .string("command"), "command": .string(command)])])])
        }

        private func trustedKey(from keyPath: String) -> String? {
            let prefix = "hooks.state.\""
            let suffix = "\".trusted_hash"
            guard keyPath.hasPrefix(prefix), keyPath.hasSuffix(suffix) else { return nil }
            let start = keyPath.index(keyPath.startIndex, offsetBy: prefix.count)
            let end = keyPath.index(keyPath.endIndex, offsetBy: -suffix.count)
            return String(keyPath[start..<end]).replacingOccurrences(of: "\\\"", with: "\"")
        }

        private func hash(for value: String) -> String {
            "sha256:" + SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ApprovalObserverIntegration-\(UUID().uuidString)", isDirectory: true)
        let appSupport = root.appendingPathComponent("Application Support/Codex Monitor/ApprovalObserver", isDirectory: true)
        let codexHome = root.appendingPathComponent("codex-home", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("ApprovalObserver")
        FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let paths = AppOwnedApprovalObserverPaths(rootURL: appSupport, codexHomeURL: codexHome)
        let fake = FakeApprovalObserverAPI(paths: paths)
        let source = AppManagedHookApprovalJournalSource(journalURL: paths.journalURL)
        return Fixture(root: root, paths: paths, executable: executable, fake: fake, source: source)
    }
}

private extension JSONValue {
    var arrayValue: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
}

private func jsonBoolValue(_ value: JSONValue?) -> Bool? {
    guard case .bool(let value) = value else { return nil }
    return value
}
