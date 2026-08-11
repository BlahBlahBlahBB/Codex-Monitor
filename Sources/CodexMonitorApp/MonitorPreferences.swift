import Foundation
import CoreGraphics

public enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    public var id: String { rawValue }
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        }
    }
}

@MainActor
public final class MonitorPreferences: ObservableObject {
    @Published public var showOrb: Bool { didSet { defaults.set(showOrb, forKey: Keys.showOrb) } }
    @Published public var orbSize: CGFloat { didSet { let value = Self.clampedSize(orbSize); if value != orbSize { orbSize = value; return }; scheduleOrbSizePersistence(value) } }
    @Published public var showUsageMenu: Bool { didSet { defaults.set(showUsageMenu, forKey: Keys.showUsageMenu) } }
    @Published public var showSettingsMenu: Bool { didSet { defaults.set(showSettingsMenu, forKey: Keys.showSettingsMenu) } }
    @Published public var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) } }
    @Published public var lockPosition: Bool { didSet { defaults.set(lockPosition, forKey: Keys.lockPosition) } }
    @Published public var pauseMonitoring: Bool { didSet { defaults.set(pauseMonitoring, forKey: Keys.pauseMonitoring) } }
    @Published public var waitingApprovalNotifications: Bool { didSet { defaults.set(waitingApprovalNotifications, forKey: Keys.waitingApprovalNotifications) } }
    @Published public var taskCompletedNotifications: Bool { didSet { defaults.set(taskCompletedNotifications, forKey: Keys.taskCompletedNotifications) } }
    @Published public var hideAccountInfo: Bool { didSet { defaults.set(hideAccountInfo, forKey: Keys.hideAccountInfo) } }
    @Published public var interfaceLanguage: InterfaceLanguage { didSet { defaults.set(interfaceLanguage.rawValue, forKey: Keys.interfaceLanguage) } }
    @Published public var orbOrigin: CGPoint? { didSet { persistOrigin() } }

    private let defaults: UserDefaults
    private var pendingSizePersistence: DispatchWorkItem?
    private enum Keys {
        static let showOrb = "monitor.showOrb"
        static let orbSize = "monitor.orbSize"
        static let showUsageMenu = "monitor.showUsageMenu"
        static let showSettingsMenu = "monitor.showSettingsMenu"
        static let alwaysOnTop = "monitor.alwaysOnTop"
        static let lockPosition = "monitor.lockPosition"
        static let pauseMonitoring = "monitor.pauseMonitoring"
        static let waitingApprovalNotifications = "monitor.waitingApprovalNotifications"
        static let taskCompletedNotifications = "monitor.taskCompletedNotifications"
        static let hideAccountInfo = "monitor.hideAccountInfo"
        static let interfaceLanguage = "monitor.interfaceLanguage"
        static let orbX = "monitor.orbX"
        static let orbY = "monitor.orbY"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showOrb = defaults.object(forKey: Keys.showOrb) as? Bool ?? true
        // A persisted user value is always preserved. 90 pt is only the
        // approved fresh-install default for the rebuilt Orb.
        orbSize = Self.clampedSize(CGFloat(defaults.object(forKey: Keys.orbSize) as? Double ?? FloatingOrbSurfaceConfiguration.freshInstallDefaultSize))
        showUsageMenu = defaults.object(forKey: Keys.showUsageMenu) as? Bool ?? true
        showSettingsMenu = defaults.object(forKey: Keys.showSettingsMenu) as? Bool ?? true
        alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        lockPosition = defaults.object(forKey: Keys.lockPosition) as? Bool ?? false
        pauseMonitoring = defaults.object(forKey: Keys.pauseMonitoring) as? Bool ?? false
        waitingApprovalNotifications = defaults.object(forKey: Keys.waitingApprovalNotifications) as? Bool ?? false
        taskCompletedNotifications = defaults.object(forKey: Keys.taskCompletedNotifications) as? Bool ?? false
        hideAccountInfo = defaults.object(forKey: Keys.hideAccountInfo) as? Bool ?? false
        interfaceLanguage = InterfaceLanguage(rawValue: defaults.string(forKey: Keys.interfaceLanguage) ?? "") ?? .system
        if defaults.object(forKey: Keys.orbX) != nil, defaults.object(forKey: Keys.orbY) != nil {
            orbOrigin = CGPoint(x: defaults.double(forKey: Keys.orbX), y: defaults.double(forKey: Keys.orbY))
        } else { orbOrigin = nil }
    }

    public static func clampedSize(_ value: CGFloat) -> CGFloat { min(max(value, FloatingOrbSurfaceConfiguration.minimumSize), FloatingOrbSurfaceConfiguration.maximumSize) }
    public func flushPersistence() {
        pendingSizePersistence?.cancel()
        pendingSizePersistence = nil
        defaults.set(Double(orbSize), forKey: Keys.orbSize)
    }

    private func scheduleOrbSizePersistence(_ value: CGFloat) {
        pendingSizePersistence?.cancel()
        let defaults = defaults
        let item = DispatchWorkItem { defaults.set(Double(value), forKey: Keys.orbSize) }
        pendingSizePersistence = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }
    private func persistOrigin() {
        guard let orbOrigin else { defaults.removeObject(forKey: Keys.orbX); defaults.removeObject(forKey: Keys.orbY); return }
        defaults.set(Double(orbOrigin.x), forKey: Keys.orbX); defaults.set(Double(orbOrigin.y), forKey: Keys.orbY)
    }
}

public enum FloatingPanelLayout {
    public static func clampedOrigin(_ requested: CGPoint, size: CGSize, screens: [CGRect], margin: CGFloat = 12) -> CGPoint {
        guard let screen = screens.first(where: { $0.intersects(CGRect(origin: requested, size: size)) }) ?? screens.first else { return requested }
        return CGPoint(x: min(max(requested.x, screen.minX + margin), screen.maxX - size.width - margin), y: min(max(requested.y, screen.minY + margin), screen.maxY - size.height - margin))
    }

    /// Preserves the visual centre whenever the square orb changes size, then
    /// applies the same multi-display safety constraint used for drag restore.
    public static func centerPreservingOrigin(center: CGPoint, size: CGSize, screens: [CGRect], margin: CGFloat = 12) -> CGPoint {
        clampedOrigin(
            CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            size: size,
            screens: screens,
            margin: margin
        )
    }

    public static func quickViewFrame(orbFrame: CGRect, desiredSize: CGSize, visibleFrame: CGRect, margin: CGFloat = 12) -> CGRect {
        let placeRight = orbFrame.midX <= visibleFrame.midX
        var x = placeRight ? orbFrame.maxX + margin : orbFrame.minX - desiredSize.width - margin
        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - desiredSize.width - margin)
        var y = orbFrame.midY - desiredSize.height / 2
        y = min(max(y, visibleFrame.minY + margin), visibleFrame.maxY - desiredSize.height - margin)
        return CGRect(origin: CGPoint(x: x, y: y), size: desiredSize)
    }
}
