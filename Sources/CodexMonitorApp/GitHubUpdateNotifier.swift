import AppKit
import Foundation

/// A strict, display-only version value. A GitHub release tag may carry an
/// explicit build as `1.2.3+45`; an absent build deliberately stays absent.
/// In particular, the Releases API does not provide the app bundle build.
struct GitHubUpdateVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let components: [Int]
    let build: Int?

    init?(marketing: String, build: String? = nil) {
        let trimmed = marketing.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionText = trimmed.first == "v" || trimmed.first == "V" ? String(trimmed.dropFirst()) : trimmed
        let parts = versionText.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ Self.decimal($0) != nil }) else { return nil }
        let parsedBuild = build.flatMap { Self.decimal(Substring($0)) }
        guard build == nil || parsedBuild != nil else { return nil }
        self.components = parts.map { Self.decimal($0)! }
        self.build = parsedBuild
    }

    init?(releaseTag: String) {
        let fields = releaseTag.split(separator: "+", omittingEmptySubsequences: false)
        guard fields.count <= 2 else { return nil }
        self.init(marketing: String(fields[0]), build: fields.count == 2 ? String(fields[1]) : nil)
    }

    private static func decimal(_ value: Substring) -> Int? {
        guard !value.isEmpty, value.allSatisfy(\.isNumber), let number = Int(value), number >= 0 else { return nil }
        return number
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        // Unknown builds are not ordered. This preserves the invariant that a
        // release must state a build before build-only updates can be offered.
        guard let left = lhs.build, let right = rhs.build else { return false }
        return left < right
    }

    var description: String {
        let marketing = components.map(String.init).joined(separator: ".")
        return build.map { "\(marketing) (\($0))" } ?? marketing
    }
}

struct GitHubReleaseRecord: Decodable, Equatable, Sendable {
    let tagName: String
    let prerelease: Bool
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case prerelease
        case draft
    }

    var version: GitHubUpdateVersion? { GitHubUpdateVersion(releaseTag: tagName) }
    var isStable: Bool { !draft && !prerelease }
}

enum GitHubUpdateEvaluation: Equatable, Sendable {
    case update(GitHubReleaseRecord)
    case notNewer
    case ignored

    static func evaluate(release: GitHubReleaseRecord, current: GitHubUpdateVersion) -> Self {
        guard release.isStable, let remote = release.version else { return .ignored }
        return remote > current ? .update(release) : .notNewer
    }
}

struct GitHubUpdateReminderPolicy {
    static func shouldPrompt(lastTag: String?, lastPrompt: Date?, candidateTag: String, now: Date, interval: TimeInterval) -> Bool {
        guard lastTag == candidateTag, let lastPrompt else { return true }
        return now.timeIntervalSince(lastPrompt) >= interval
    }
}

struct GitHubReleaseHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

protocol GitHubReleaseFetching: Sendable {
    func latestRelease() async throws -> GitHubReleaseRecord
}

struct GitHubReleaseAPIClient: GitHubReleaseFetching {
    static let repository = "BlahBlahBlahBB/Codex-Monitor"
    static let latestEndpoint = URL(string: "https://api.github.com/repos/BlahBlahBlahBB/Codex-Monitor/releases/latest")!

    private let transport: @Sendable (URLRequest) async throws -> GitHubReleaseHTTPResponse

    init(transport: @escaping @Sendable (URLRequest) async throws -> GitHubReleaseHTTPResponse = Self.urlSessionTransport) {
        self.transport = transport
    }

    func latestRelease() async throws -> GitHubReleaseRecord {
        var request = URLRequest(url: Self.latestEndpoint, timeoutInterval: 12)
        request.setValue("Codex-Monitor-update-notifier", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let response = try await transport(request)
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(GitHubReleaseRecord.self, from: response.data)
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> GitHubReleaseHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return GitHubReleaseHTTPResponse(data: data, statusCode: http.statusCode)
    }
}

/// A deterministic ownership gate used by the notifier and tests. A cancelled
/// owner cannot finish later and present an alert during app termination.
actor GitHubUpdateCheckGate {
    private var activeToken: UInt64?
    private var nextToken: UInt64 = 0

    func begin() -> UInt64? {
        guard activeToken == nil else { return nil }
        nextToken &+= 1
        activeToken = nextToken
        return nextToken
    }

    func finish(_ token: UInt64) -> Bool {
        guard activeToken == token else { return false }
        activeToken = nil
        return true
    }

    func cancel() {
        activeToken = nil
    }
}

@MainActor
final class GitHubUpdateNotifier {
    nonisolated static let repository = GitHubReleaseAPIClient.repository
    nonisolated static let automaticInterval: TimeInterval = 24 * 60 * 60
    nonisolated static let startupDelay: Duration = .seconds(8)

    private enum DefaultsKey {
        static let lastAutomaticCheck = "githubUpdate.lastAutomaticCheck"
        static let lastPromptedTag = "githubUpdate.lastPromptedTag"
        static let lastPromptedAt = "githubUpdate.lastPromptedAt"
    }

    private let client: any GitHubReleaseFetching
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let gate = GitHubUpdateCheckGate()
    private var scheduleTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var isTerminating = false

    init(
        client: any GitHubReleaseFetching = GitHubReleaseAPIClient(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.defaults = defaults
        self.now = now
    }

    func scheduleStartupCheck(after delay: Duration = GitHubUpdateNotifier.startupDelay) {
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self, !self.isTerminating else { return }
            self.runAutomaticCheckIfDue()
            self.scheduleNextAutomaticCheck()
        }
    }

    /// Manual checks bypass the 24-hour cadence, but never create a second
    /// network request while a prior check owns the gate.
    func check(interactive: Bool) {
        guard !isTerminating else { return }
        guard requestTask == nil else {
            if interactive { showChecking() }
            return
        }

        let current = Self.currentVersion()
        guard let current else {
            if interactive { showUnavailable() }
            return
        }
        if !interactive { defaults.set(now(), forKey: DefaultsKey.lastAutomaticCheck) }

        let client = client
        requestTask = Task { [weak self] in
            guard let token = await self?.gate.begin() else { return }
            let result: Result<GitHubReleaseRecord, Error>
            do {
                result = .success(try await client.latestRelease())
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, let self, await self.gate.finish(token) else { return }
            self.finishCheck(result, current: current, interactive: interactive)
        }
    }

    func cancel() {
        isTerminating = true
        scheduleTask?.cancel()
        requestTask?.cancel()
        scheduleTask = nil
        requestTask = nil
        Task { await gate.cancel() }
    }

    private func runAutomaticCheckIfDue() {
        let last = defaults.object(forKey: DefaultsKey.lastAutomaticCheck) as? Date
        guard last.map({ now().timeIntervalSince($0) >= Self.automaticInterval }) ?? true else { return }
        check(interactive: false)
    }

    private func scheduleNextAutomaticCheck() {
        guard !isTerminating else { return }
        scheduleTask?.cancel()
        let last = defaults.object(forKey: DefaultsKey.lastAutomaticCheck) as? Date
        let elapsed = last.map { now().timeIntervalSince($0) } ?? Self.automaticInterval
        let delay = max(0, Self.automaticInterval - elapsed)
        scheduleTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled, let self, !self.isTerminating else { return }
            self.runAutomaticCheckIfDue()
            self.scheduleNextAutomaticCheck()
        }
    }

    private func finishCheck(_ result: Result<GitHubReleaseRecord, Error>, current: GitHubUpdateVersion, interactive: Bool) {
        requestTask = nil
        guard !isTerminating else { return }
        switch result {
        case .failure:
            if interactive { showUnavailable() }
        case .success(let release):
            switch GitHubUpdateEvaluation.evaluate(release: release, current: current) {
            case .update(let update):
                if interactive || shouldPrompt(for: update.tagName) {
                    showUpdate(current: current, release: update)
                }
            case .notNewer:
                if interactive { showNoUpdate(current) }
            case .ignored:
                if interactive { showUnavailable() }
            }
        }
    }

    private func shouldPrompt(for tag: String) -> Bool {
        GitHubUpdateReminderPolicy.shouldPrompt(
            lastTag: defaults.string(forKey: DefaultsKey.lastPromptedTag),
            lastPrompt: defaults.object(forKey: DefaultsKey.lastPromptedAt) as? Date,
            candidateTag: tag,
            now: now(),
            interval: Self.automaticInterval
        )
    }

    private static func currentVersion() -> GitHubUpdateVersion? {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return GitHubUpdateVersion(marketing: marketing, build: build)
    }

    nonisolated static func officialReleasePage(for tag: String) -> URL? {
        // Never consume an API-provided URL. Parsing the tag first also keeps
        // this path free of injected separators, hosts, or query strings.
        guard GitHubUpdateVersion(releaseTag: tag) != nil else { return nil }
        return URL(string: "https://github.com/BlahBlahBlahBB/Codex-Monitor/releases/tag/\(tag)")
    }

    private func showChecking() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("update.checking")
        alert.informativeText = L10n.tr("update.checkingDescription")
        alert.addButton(withTitle: L10n.tr("update.ok"))
        alert.runModal()
    }

    private func showNoUpdate(_ current: GitHubUpdateVersion) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("update.upToDate")
        alert.informativeText = String(format: L10n.tr("update.currentVersion"), current.description)
        alert.addButton(withTitle: L10n.tr("update.ok"))
        alert.runModal()
    }

    private func showUnavailable() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("update.unavailable")
        alert.informativeText = L10n.tr("update.unavailableDescription")
        alert.addButton(withTitle: L10n.tr("update.ok"))
        alert.runModal()
    }

    private func showUpdate(current: GitHubUpdateVersion, release: GitHubReleaseRecord) {
        guard let page = Self.officialReleasePage(for: release.tagName) else { return }
        let alert = NSAlert()
        alert.messageText = L10n.tr("update.available")
        alert.informativeText = String(
            format: L10n.tr("update.availableDescription"),
            current.description,
            release.version?.description ?? release.tagName
        )
        alert.addButton(withTitle: L10n.tr("update.releaseNotes"))
        alert.addButton(withTitle: L10n.tr("update.downloadGitHub"))
        alert.addButton(withTitle: L10n.tr("update.remindLater"))
        let response = alert.runModal()
        defaults.set(release.tagName, forKey: DefaultsKey.lastPromptedTag)
        defaults.set(now(), forKey: DefaultsKey.lastPromptedAt)
        if response != .alertThirdButtonReturn { NSWorkspace.shared.open(page) }
    }
}
