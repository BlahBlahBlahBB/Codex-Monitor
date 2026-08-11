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

enum UIInteractionContract {
    static let minimumActionRowHeight: CGFloat = 36
    static let actionRowCornerRadius: CGFloat = 8
    static let disabledOpacity: Double = 0.42
}

enum PopoverActionVisualState: Equatable {
    case rest, hover, pressed, keyboardFocus, disabled
}

enum PopoverActionFeedback {
    static func surfaceOpacity(for state: PopoverActionVisualState) -> Double {
        switch state {
        case .rest: 0
        case .hover: 0.09
        case .pressed: 0.16
        // Native keyboard focus owns its system focus indication. Do not add
        // a mouse-rest blue outline underneath it.
        case .keyboardFocus, .disabled: 0
        }
    }
}
