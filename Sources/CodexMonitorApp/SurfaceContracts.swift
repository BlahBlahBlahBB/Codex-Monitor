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
    /// Transparent drawing room around the visible Orb. This belongs to the
    /// host only; the persisted/user-selected Orb diameter is unchanged.
    static let shadowInset: CGFloat = 10
    static let quickViewSize = CGSize(width: 350, height: 214)

    static func hostSize(forOrbSize orbSize: CGFloat) -> CGSize {
        CGSize(width: orbSize + shadowInset * 2, height: orbSize + shadowInset * 2)
    }
}

/// Interaction timing is explicit so the reusable native Quick View panel can
/// retain its lifecycle while its user-facing dismissal interval remains easy
/// to verify independently.
enum QuickViewInteractionContract {
    static let automaticDismissDelay: Duration = .seconds(2)
}

enum MonitorOrbVisualContract {
    /// The Orb is intentionally a three-layer visual: one circular glass
    /// body, one runtime state ring, and one quota text value.
    static let glassBodyCount = 1
    static let runtimeRingCount = 1
    static let quotaTextCount = 1
    static let secondaryCircularStrokeCount = 0
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

/// Persisted quota warnings use this intentionally non-uniform set rather
/// than a regular step interval, so invalid values such as 35% and 45% can
/// never become effective settings.
enum QuotaWarningThreshold {
    static let allowedValues: [Double] = [5, 10, 15, 20, 25, 30, 40, 50]
    static let defaultValue: Double = 20

    /// Equal-distance ties choose the lower threshold. This is deterministic
    /// and keeps the effective warning conservative with the slider position.
    static func snap(_ value: Double) -> Double {
        allowedValues.min { lhs, rhs in
            let leftDistance = abs(lhs - value)
            let rightDistance = abs(rhs - value)
            return leftDistance == rightDistance ? lhs < rhs : leftDistance < rightDistance
        } ?? defaultValue
    }
}

enum QuotaCapsuleHealth: Equatable {
    case sufficient, warning, exhausted, unknown

    static func resolve(snapshot: MonitorRuntimeSnapshot?, warningEnabled: Bool, threshold: Double) -> Self {
        guard let remaining = MonitorDisplayValue.selectedQuotaWindow(snapshot)?.remaining else { return .unknown }
        if remaining == 0 { return .exhausted }
        if warningEnabled && remaining <= QuotaWarningThreshold.snap(threshold) { return .warning }
        return .sufficient
    }
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

    static func forSnapshot(
        _ snapshot: MonitorRuntimeSnapshot?,
        quotaWarningEnabled: Bool = true,
        quotaWarningThreshold: Double = QuotaWarningThreshold.defaultValue,
        experimentalApprovalYellowEnabled: Bool = false
    ) -> Self {
        guard let snapshot else {
            return unavailable
        }
        let desktop = snapshot.sourceHealth[.desktopLocal]
        if desktop?.reason == .codexProcessNotRunning {
            return forState(.disconnected)
        }
        guard desktop?.availability == .available else { return unavailable }

        var presentation = forState(snapshot.currentState)
        // Existing terminal/disconnected behavior is deliberately untouched.
        guard ![.failed, .interrupted, .systemError, .disconnected, .paused].contains(snapshot.currentState) else {
            return presentation
        }

        switch QuotaCapsuleHealth.resolve(
            snapshot: snapshot,
            warningEnabled: quotaWarningEnabled,
            threshold: quotaWarningThreshold
        ) {
        case .exhausted:
            presentation = Self(dots: [.inactive, .inactive, .init(tone: .red, breathes: false)], orbTone: presentation.orbTone, breathes: presentation.breathes, stateTextKey: presentation.stateTextKey)
        case .warning:
            if [.thinking, .working, .waitingApproval].contains(snapshot.currentState) {
                presentation = Self(dots: [.init(tone: .green, breathes: true), .init(tone: .yellow, breathes: false), .inactive], orbTone: presentation.orbTone, breathes: presentation.breathes, stateTextKey: presentation.stateTextKey)
            } else {
                presentation = Self(dots: [.green, .init(tone: .yellow, breathes: false), .green], orbTone: presentation.orbTone, breathes: presentation.breathes, stateTextKey: presentation.stateTextKey)
            }
        case .sufficient, .unknown:
            break
        }

        // Approval Beta has no capsule effect. It is intentionally applied
        // after quota rendering so the two dimensions cannot leak together.
        if experimentalApprovalYellowEnabled && snapshot.approvalRequestObserved {
            presentation = Self(dots: presentation.dots, orbTone: .yellow, breathes: true, stateTextKey: presentation.stateTextKey)
        }
        return presentation
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
            // Compatibility-only enum case. V1 has no reliable waiting
            // lifecycle, so presentation must never select a yellow orb.
            return Self(dots: [.init(tone: .green, breathes: true), .inactive, .inactive], orbTone: .blue, breathes: true, stateTextKey: "state.thinking")
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
