import Combine
import Foundation
import ServiceManagement
import UserNotifications
import CodexMonitorContracts

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
        guard snapshot.sourceHealth[.desktopLocal]?.availability == .available,
              let previous = lastState,
              previous != snapshot.currentState else { return }
        if snapshot.currentState == .waitingApproval, preferences.waitingApprovalNotifications {
            deliver(title: L10n.tr("state.waitingApproval"), body: L10n.tr("activity.waitingConfirmation"))
        } else if snapshot.currentState == .completed, preferences.taskCompletedNotifications {
            deliver(title: L10n.tr("state.completed"), body: MonitorDisplayValue.taskTitle(snapshot))
        }
    }

    private func deliver(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum NotificationPreference {
    case waitingApproval
    case taskCompleted
}
