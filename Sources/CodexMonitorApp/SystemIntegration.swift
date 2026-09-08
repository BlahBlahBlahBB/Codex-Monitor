import Combine
import Foundation
import AppKit
import ServiceManagement
import UserNotifications
import CodexMonitorContracts

enum MonitorNotificationAppName {
    static func resolve(info: [String: Any]) -> String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let value = info[key] as? String {
                let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
            }
        }
        return "Codex Monitor"
    }

    static func current() -> String {
        resolve(info: Bundle.main.infoDictionary ?? [:])
    }
}

struct MonitorNotificationContent: Equatable {
    let title: String
    let subtitle: String
    let body: String

    static func waitingApproval(taskTitle: String, languageCode: String? = nil, appDisplayName: String? = nil) -> Self {
        Self(
            title: appDisplayName ?? MonitorNotificationAppName.current(),
            subtitle: L10n.tr("state.waitingApproval", languageCode: languageCode),
            body: taskTitle
        )
    }

    static func completed(snapshot: MonitorRuntimeSnapshot?, languageCode: String? = nil, appDisplayName: String? = nil) -> Self {
        // The body deliberately reuses the sole approved conversation-name
        // presentation chain. It admits only threads.name and its safe,
        // localized fallback; it never reads raw thread title or runtime metadata.
        Self(
            title: appDisplayName ?? MonitorNotificationAppName.current(),
            subtitle: L10n.tr("state.completed", languageCode: languageCode),
            body: MonitorDisplayValue.resolvedConversationDisplayTitle(snapshot, languageCode: languageCode)
        )
    }

    static func forTransition(
        from previous: MonitorRuntimeState?,
        to current: MonitorRuntimeState,
        snapshot: MonitorRuntimeSnapshot,
        desktopSourceAvailable: Bool,
        waitingApprovalEnabled: Bool,
        taskCompletedEnabled: Bool
    ) -> Self? {
        guard desktopSourceAvailable,
              let previous,
              previous != current else { return nil }
        // Approval notifications intentionally do not originate from a
        // snapshot transition. A repeated reconciliation snapshot has no
        // event identity and must never become a delivery authority.
        _ = waitingApprovalEnabled
        if current == .completed, taskCompletedEnabled {
            return completed(snapshot: snapshot)
        }
        return nil
    }
}

/// The result of reconciling one durable outbox intent with Notification
/// Center. `confirmed` means it was successfully added or already existed;
/// `retry` leaves the durable intent untouched for a later cycle.
public enum ApprovalNotificationDeliveryDisposition: Sendable, Equatable {
    case confirmed
    case retry
    case suppressed
}

enum MonitorTaskNotificationKind: String, Sendable {
    case waitingApproval
    case completed
}

struct MonitorTaskNotification: Equatable {
    static let categoryIdentifier = "com.codexmonitor.task"
    static let kindUserInfoKey = "codexMonitorTaskNotificationKind"

    let identifier: String
    let kind: MonitorTaskNotificationKind
    let content: MonitorNotificationContent
}

struct MonitorTaskNotificationResponse: Equatable {
    let categoryIdentifier: String
    let kindRawValue: String?
    let actionIdentifier: String

    var isCodexMonitorTaskClick: Bool {
        categoryIdentifier == MonitorTaskNotification.categoryIdentifier &&
        MonitorTaskNotificationKind(rawValue: kindRawValue ?? "") != nil &&
        actionIdentifier == UNNotificationDefaultActionIdentifier
    }
}

@MainActor
protocol MonitorNotificationDelivering: AnyObject {
    func deliver(_ notification: MonitorTaskNotification) async -> Bool
    func containsNotification(identifier: String) async -> Bool
}

@MainActor
final class UserNotificationCenterDelivery: MonitorNotificationDelivering {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func deliver(_ notification: MonitorTaskNotification) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = notification.content.title
        content.subtitle = notification.content.subtitle
        content.body = notification.content.body
        content.categoryIdentifier = MonitorTaskNotification.categoryIdentifier
        content.userInfo = [MonitorTaskNotification.kindUserInfoKey: notification.kind.rawValue]
        return await withCheckedContinuation { continuation in
            center.add(UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    func containsNotification(identifier: String) async -> Bool {
        let pendingIdentifiers: Set<String> = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: Set(requests.map(\.identifier)))
            }
        }
        if pendingIdentifiers.contains(identifier) { return true }
        let deliveredIdentifiers: Set<String> = await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: Set(notifications.map { $0.request.identifier }))
            }
        }
        return deliveredIdentifiers.contains(identifier)
    }
}

/// A small injectable façade keeps notification interaction tests from
/// launching the real Codex app while production uses bundle identity only.
@MainActor
struct CodexDesktopApplicationActivator {
    static let bundleIdentifier = CodexProcessLiveness.bundleIdentifier

    private let activateRunning: () -> Bool
    private let resolvedApplicationURL: () -> URL?
    private let launch: (URL) -> Void

    init(
        activateRunning: @escaping () -> Bool,
        resolvedApplicationURL: @escaping () -> URL?,
        launch: @escaping (URL) -> Void
    ) {
        self.activateRunning = activateRunning
        self.resolvedApplicationURL = resolvedApplicationURL
        self.launch = launch
    }

    static func live() -> Self {
        let workspace = NSWorkspace.shared
        return Self(
            activateRunning: {
                guard let application = workspace.runningApplications.first(where: {
                    $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
                }) else { return false }
                return application.activate(options: [.activateIgnoringOtherApps])
            },
            resolvedApplicationURL: {
                workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
            },
            launch: { url in
                workspace.openApplication(at: url, configuration: .init())
            }
        )
    }

    func activateOrLaunch() {
        guard !activateRunning() else { return }
        guard let url = resolvedApplicationURL() else { return }
        launch(url)
    }
}

/// The one notification-center response path. Unknown categories, stale
/// identifiers, dismissals, missing Codex, and launch failures all fail safe.
final class MonitorTaskNotificationResponseHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let activateCodex: @Sendable () -> Void

    init(activateCodex: @escaping @Sendable () -> Void) {
        self.activateCodex = activateCodex
    }

    func handle(_ response: MonitorTaskNotificationResponse) {
        guard response.isCodexMonitorTaskClick else { return }
        activateCodex()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handle(MonitorTaskNotificationResponse(
            categoryIdentifier: response.notification.request.content.categoryIdentifier,
            kindRawValue: response.notification.request.content.userInfo[MonitorTaskNotification.kindUserInfoKey] as? String,
            actionIdentifier: response.actionIdentifier
        ))
        completionHandler()
    }
}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled = false

    init() { reconcile() }

    func reconcile() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// The setting is authoritative only after macOS confirms the requested
    /// registration state. A failed operation leaves the control reconciled to
    /// the system rather than visually pretending it succeeded.
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        reconcile()
    }
}

@MainActor
final class MonitorNotificationController {
    private var snapshotObserver: AnyCancellable?
    private var lastState: MonitorRuntimeState?
    private let delivery: any MonitorNotificationDelivering
    private let responseHandler: MonitorTaskNotificationResponseHandler
    private let installResponseHandler: () -> Void

    init(
        delivery: (any MonitorNotificationDelivering)? = nil,
        activateCodex: @escaping @Sendable () -> Void = {
            Task { @MainActor in CodexDesktopApplicationActivator.live().activateOrLaunch() }
        },
        responseHandlerInstaller: (() -> Void)? = nil
    ) {
        self.delivery = delivery ?? UserNotificationCenterDelivery()
        let responseHandler = MonitorTaskNotificationResponseHandler(activateCodex: activateCodex)
        self.responseHandler = responseHandler
        installResponseHandler = responseHandlerInstaller ?? {
            UNUserNotificationCenter.current().delegate = responseHandler
        }
    }

    func start(model: MonitorAppModel, preferences: MonitorPreferences) {
        snapshotObserver?.cancel()
        installResponseHandler()
        snapshotObserver = model.$snapshot.sink { [weak self, weak preferences] snapshot in
            guard let self, let preferences, let snapshot else { return }
            Task { @MainActor [weak self, weak preferences] in
                guard let self, let preferences else { return }
                await self.receive(snapshot: snapshot, preferences: preferences)
            }
        }
    }

    func stop() {
        snapshotObserver?.cancel()
        snapshotObserver = nil
    }

    func requestPermissionThenEnable(_ kind: NotificationPreference, preferences: MonitorPreferences) {
        // Approval monitoring is a real-time lifecycle feature, not a proxy
        // for Notification Center authorization. Turn it on immediately so a
        // denied/unavailable system notification permission can never block
        // the frozen Hook and yellow-Orb paths.
        if notificationPreferenceEnablement(for: kind) == .beforeAuthorization {
            preferences.waitingApprovalNotifications = true
        }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch notificationAuthorizationDisposition(for: settings.authorizationStatus) {
            case .enableImmediately:
                break
            case .requestThenEnable:
                guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            case .doNotEnable:
                return
            }
            guard notificationPreferenceEnablement(for: kind) == .afterAuthorization else { return }
            switch kind {
            case .waitingApproval:
                // The prior branch has already enabled this product feature.
                return
            case .taskCompleted:
                preferences.taskCompletedNotifications = true
            }
        }
    }

    func receive(snapshot: MonitorRuntimeSnapshot, preferences: MonitorPreferences) async {
        defer { lastState = snapshot.currentState }
        guard let notification = MonitorNotificationContent.forTransition(
            from: lastState,
            to: snapshot.currentState,
            snapshot: snapshot,
            desktopSourceAvailable: snapshot.sourceHealth[.desktopLocal]?.availability == .available,
            waitingApprovalEnabled: preferences.waitingApprovalNotifications,
            taskCompletedEnabled: preferences.taskCompletedNotifications
        ) else { return }
        _ = await delivery.deliver(MonitorTaskNotification(identifier: UUID().uuidString, kind: .completed, content: notification))
    }

    /// Reconciles one durable approval intent. Notification Center is queried
    /// before a retry so a crash after `add` but before local acknowledgement
    /// cannot create another notification for the deterministic request ID.
    func deliverApprovalOutboxIntent(_ intent: ApprovalNotificationOutboxIntent, preferences: MonitorPreferences) async -> ApprovalNotificationDeliveryDisposition {
        guard preferences.waitingApprovalNotifications else { return .suppressed }
        if await delivery.containsNotification(identifier: intent.requestIdentifier) { return .confirmed }
        let notification = MonitorTaskNotification(
            identifier: intent.requestIdentifier,
            kind: .waitingApproval,
            content: MonitorNotificationContent.waitingApproval(taskTitle: intent.taskTitle)
        )
        return await delivery.deliver(notification) ? .confirmed : .retry
    }
}

enum NotificationPreference {
    case waitingApproval
    case taskCompleted
}

enum NotificationPreferenceEnablement: Equatable {
    case beforeAuthorization
    case afterAuthorization
}

func notificationPreferenceEnablement(for preference: NotificationPreference) -> NotificationPreferenceEnablement {
    switch preference {
    case .waitingApproval: .beforeAuthorization
    case .taskCompleted: .afterAuthorization
    }
}

enum NotificationAuthorizationDisposition: Equatable {
    case requestThenEnable
    case enableImmediately
    case doNotEnable
}

func notificationAuthorizationDisposition(for status: UNAuthorizationStatus) -> NotificationAuthorizationDisposition {
    switch status {
    case .notDetermined:
        .requestThenEnable
    case .authorized:
        .enableImmediately
    case .denied, .provisional, .ephemeral:
        .doNotEnable
    @unknown default:
        .doNotEnable
    }
}
