import Foundation
import CoreGraphics

@MainActor
public final class MonitorPreferences: ObservableObject {
    @Published public var showOrb: Bool { didSet { defaults.set(showOrb, forKey: Keys.showOrb) } }
    @Published public var orbSize: CGFloat { didSet { let value = Self.clampedSize(orbSize); if value != orbSize { orbSize = value; return }; defaults.set(Double(value), forKey: Keys.orbSize) } }
    @Published public var showUsageMenu: Bool { didSet { defaults.set(showUsageMenu, forKey: Keys.showUsageMenu) } }
    @Published public var showSettingsMenu: Bool { didSet { defaults.set(showSettingsMenu, forKey: Keys.showSettingsMenu) } }
    @Published public var orbOrigin: CGPoint? { didSet { persistOrigin() } }

    private let defaults: UserDefaults
    private enum Keys { static let showOrb = "monitor.showOrb"; static let orbSize = "monitor.orbSize"; static let showUsageMenu = "monitor.showUsageMenu"; static let showSettingsMenu = "monitor.showSettingsMenu"; static let orbX = "monitor.orbX"; static let orbY = "monitor.orbY" }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showOrb = defaults.object(forKey: Keys.showOrb) as? Bool ?? true
        // A persisted user value is always preserved. 90 pt is only the
        // approved fresh-install default for the rebuilt Orb.
        orbSize = Self.clampedSize(CGFloat(defaults.object(forKey: Keys.orbSize) as? Double ?? FloatingOrbSurfaceConfiguration.freshInstallDefaultSize))
        showUsageMenu = defaults.object(forKey: Keys.showUsageMenu) as? Bool ?? true
        showSettingsMenu = defaults.object(forKey: Keys.showSettingsMenu) as? Bool ?? true
        if defaults.object(forKey: Keys.orbX) != nil, defaults.object(forKey: Keys.orbY) != nil {
            orbOrigin = CGPoint(x: defaults.double(forKey: Keys.orbX), y: defaults.double(forKey: Keys.orbY))
        } else { orbOrigin = nil }
    }

    public static func clampedSize(_ value: CGFloat) -> CGFloat { min(max(value, FloatingOrbSurfaceConfiguration.minimumSize), FloatingOrbSurfaceConfiguration.maximumSize) }
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

    public static func quickViewFrame(orbFrame: CGRect, desiredSize: CGSize, visibleFrame: CGRect, margin: CGFloat = 12) -> CGRect {
        let placeRight = orbFrame.midX <= visibleFrame.midX
        var x = placeRight ? orbFrame.maxX + margin : orbFrame.minX - desiredSize.width - margin
        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - desiredSize.width - margin)
        var y = orbFrame.midY - desiredSize.height / 2
        y = min(max(y, visibleFrame.minY + margin), visibleFrame.maxY - desiredSize.height - margin)
        return CGRect(origin: CGPoint(x: x, y: y), size: desiredSize)
    }
}
