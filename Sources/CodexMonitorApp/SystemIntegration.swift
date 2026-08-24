import Combine
import Foundation
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

    static func waitingApproval() -> Self {
        Self(title: L10n.tr("state.waitingApproval"), subtitle: "", body: L10n.tr("activity.waitingConfirmation"))
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
        if current == .waitingApproval, waitingApprovalEnabled {
            return waitingApproval()
        }
        if current == .completed, taskCompletedEnabled {
            return completed(snapshot: snapshot)
        }
        return nil
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

    func start(model: MonitorAppModel, preferences: MonitorPreferences) {
        snapshotObserver?.cancel()
        snapshotObserver = model.$snapshot.sink { [weak self, weak preferences] snapshot in
            guard let self, let preferences, let snapshot else { return }
            self.handle(snapshot: snapshot, preferences: preferences)
        }
    }

    func stop() { snapshotObserver?.cancel(); snapshotObserver = nil }

    func requestPermissionThenEnable(_ kind: NotificationPreference, preferences: MonitorPreferences) {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            switch kind {
            case .waitingApproval: preferences.waitingApprovalNotifications = true
            case .taskCompleted: preferences.taskCompletedNotifications = true
            }
        }
    }

    private func handle(snapshot: MonitorRuntimeSnapshot, preferences: MonitorPreferences) {
        defer { lastState = snapshot.currentState }
        guard let notification = MonitorNotificationContent.forTransition(
            from: lastState,
            to: snapshot.currentState,
            snapshot: snapshot,
            desktopSourceAvailable: snapshot.sourceHealth[.desktopLocal]?.availability == .available,
            waitingApprovalEnabled: preferences.waitingApprovalNotifications,
            taskCompletedEnabled: preferences.taskCompletedNotifications
        ) else { return }
        deliver(notification)
    }

    private func deliver(_ notification: MonitorNotificationContent) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.subtitle
        content.body = notification.body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum NotificationPreference {
    case waitingApproval
    case taskCompleted
}
