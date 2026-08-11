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

enum SettingsLayoutContract {
    /// The size row is one native Slider plus its value label. It has no
    /// custom track, tick, dashed line, Canvas, or decoration beneath it.
    static let hasCustomSliderDecoration = false
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

/// The only runtime-to-visual mapping used by the capsule, Orb, and textual
/// state labels. Keeping this small value type independent from SwiftUI makes
/// the frozen state grammar straightforward to regression-test.
enum VisualStateTone: Equatable {
    case green, blue, yellow, red, gray, inactive
}

struct VisualStateDot: Equatable {
    let tone: VisualStateTone
    let breathes: Bool

    static let inactive = Self(tone: .inactive, breathes: false)
    static let green = Self(tone: .green, breathes: false)
}

struct VisualStatePresentation: Equatable {
    let dots: [VisualStateDot]
    let orbTone: VisualStateTone
    let breathes: Bool
    let stateTextKey: String

    static func forSnapshot(_ snapshot: MonitorRuntimeSnapshot?) -> Self {
        guard let snapshot,
              snapshot.sourceHealth[.desktopLocal]?.availability == .available else {
            return unavailable
        }
        return forState(snapshot.currentState)
    }

    static func forState(_ state: MonitorRuntimeState) -> Self {
        switch state {
        case .idle:
            return Self(dots: [.green, .green, .green], orbTone: .green, breathes: false, stateTextKey: "state.idle")
        case .completed:
            return Self(dots: [.green, .green, .green], orbTone: .green, breathes: false, stateTextKey: "state.completed")
        case .thinking:
            return Self(dots: [.init(tone: .green, breathes: true), .inactive, .inactive], orbTone: .blue, breathes: true, stateTextKey: "state.thinking")
        case .working:
            return Self(dots: [.init(tone: .green, breathes: true), .inactive, .inactive], orbTone: .blue, breathes: true, stateTextKey: "state.working")
        case .waitingApproval:
            return Self(dots: [.inactive, .init(tone: .yellow, breathes: true), .inactive], orbTone: .yellow, breathes: true, stateTextKey: "state.waitingApproval")
        case .failed:
            return Self(dots: [.inactive, .inactive, .init(tone: .red, breathes: false)], orbTone: .red, breathes: false, stateTextKey: "state.failed")
        case .interrupted:
            return Self(dots: [.inactive, .inactive, .init(tone: .red, breathes: false)], orbTone: .red, breathes: false, stateTextKey: "state.interrupted")
        case .systemError:
            return Self(dots: [.inactive, .inactive, .init(tone: .red, breathes: false)], orbTone: .red, breathes: false, stateTextKey: "state.systemError")
        case .disconnected:
            return Self(dots: Array(repeating: .init(tone: .gray, breathes: false), count: 3), orbTone: .gray, breathes: false, stateTextKey: "state.codexUnavailable")
        case .paused:
            return Self(dots: Array(repeating: .init(tone: .gray, breathes: false), count: 3), orbTone: .gray, breathes: false, stateTextKey: "state.paused")
        }
    }

    static let unavailable = Self(
        dots: Array(repeating: .init(tone: .gray, breathes: false), count: 3),
        orbTone: .gray,
        breathes: false,
        stateTextKey: "state.sourceUnavailable"
    )
}
