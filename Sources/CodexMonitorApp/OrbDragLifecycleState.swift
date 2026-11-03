/// Small value state used by the QA drag coordinator and deterministic tests.
/// Tests of this type simulate transitions; they do not emulate AppKit delivery.
struct OrbDragLifecycleState {
    enum Phase: Equatable {
        case idle
        case trackingClick
        case nativeDragCall
        case awaitingMouseUp
    }

    private(set) var phase: Phase = .idle
    private(set) var cleanupPending = false
    var isTracking: Bool { phase != .idle }
    var isTrackingClick: Bool { phase == .trackingClick }

    mutating func beginTracking() -> Bool {
        guard phase == .idle else { return false }
        phase = .trackingClick
        cleanupPending = false
        return true
    }

    mutating func beginNativeDrag() -> Bool {
        guard phase == .trackingClick else { return false }
        phase = .nativeDragCall
        return true
    }

    mutating func nativeDragReturned() {
        guard phase == .nativeDragCall else { return }
        phase = .awaitingMouseUp
    }

    mutating func observeMouseUp() -> Bool {
        guard phase != .idle else { return false }
        guard phase != .nativeDragCall else {
            cleanupPending = true
            return false
        }
        return true
    }

    mutating func recoverForNewMouseDown() -> Bool {
        guard phase == .trackingClick || phase == .awaitingMouseUp else { return false }
        return true
    }

    mutating func canCancelForDetach(leftButtonDown: Bool) -> Bool {
        phase != .nativeDragCall && !leftButtonDown
    }

    @discardableResult
    mutating func cleanup() -> Bool {
        guard phase != .idle && phase != .nativeDragCall else { return false }
        phase = .idle
        cleanupPending = false
        return true
    }
}
