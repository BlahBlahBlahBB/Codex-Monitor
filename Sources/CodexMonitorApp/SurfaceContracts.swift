import AppKit
import Foundation
import CodexMonitorContracts

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

enum MenuLightTone: Equatable {
    case green, yellow, red, inactive
}

struct MenuLightPresentation: Equatable {
    let tone: MenuLightTone
    let breathes: Bool

    static let inactive = Self(tone: .inactive, breathes: false)
    static let idle = Self(tone: .green, breathes: false)

    static func dots(for state: MonitorRuntimeState?, desktopAvailable: Bool) -> [Self] {
        guard desktopAvailable, let state else { return Array(repeating: inactive, count: 3) }
        switch state {
        case .idle, .completed:
            return Array(repeating: idle, count: 3)
        case .working, .thinking:
            return [Self(tone: .green, breathes: true), inactive, inactive]
        case .waitingApproval:
            return [inactive, Self(tone: .yellow, breathes: true), inactive]
        case .failed, .interrupted, .systemError:
            return [inactive, inactive, Self(tone: .red, breathes: false)]
        case .disconnected, .paused:
            return Array(repeating: inactive, count: 3)
        }
    }
}
