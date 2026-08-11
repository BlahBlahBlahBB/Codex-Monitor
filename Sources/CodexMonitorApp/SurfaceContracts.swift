import AppKit
import Foundation

/// Small, presentation-only ownership guard. A surface remains owned while its
/// reusable controller exists, including when its native window is hidden.
@MainActor
final class MonitorSurfaceOwnership {
    enum Surface: Hashable { case statusItem, orb, usage, settings, diagnostics }
    private var owned: Set<Surface> = []

    func acquire(_ surface: Surface) -> Bool {
        owned.insert(surface).inserted
    }

    func owns(_ surface: Surface) -> Bool { owned.contains(surface) }
    func reset() { owned.removeAll() }
}

enum FloatingOrbSurfaceConfiguration {
    static let freshInstallDefaultSize: CGFloat = 90
    static let minimumSize: CGFloat = 72
    static let maximumSize: CGFloat = 180
    static let isOpaque = false
    static let hasPanelShadow = false
    static let quickViewSize = CGSize(width: 350, height: 214)
}
