import XCTest
@testable import CodexMonitorApp

/// These are deterministic state-machine simulations, not AppKit input tests.
final class OrbDragLifecycleStateTests: XCTestCase {
    func testSimulatedClickThenCleanup() {
        var state = OrbDragLifecycleState()
        XCTAssertTrue(state.beginTracking())
        XCTAssertTrue(state.isTrackingClick)
        XCTAssertTrue(state.observeMouseUp())
        XCTAssertTrue(state.cleanup())
        XCTAssertFalse(state.isTracking)
    }

    func testSimulatedDragRemainsTrackedUntilMouseUp() {
        var state = OrbDragLifecycleState()
        XCTAssertTrue(state.beginTracking())
        XCTAssertTrue(state.beginNativeDrag())
        state.nativeDragReturned()
        XCTAssertTrue(state.isTracking)
        XCTAssertTrue(state.observeMouseUp())
        XCTAssertTrue(state.cleanup())
        XCTAssertFalse(state.isTracking)
    }

    func testSimulatedRepeatedClickDragSequences() {
        var state = OrbDragLifecycleState()
        for drag in [false, true, false, true] {
            XCTAssertTrue(state.beginTracking())
            if drag {
                XCTAssertTrue(state.beginNativeDrag())
                state.nativeDragReturned()
            }
            XCTAssertTrue(state.observeMouseUp())
            XCTAssertTrue(state.cleanup())
            XCTAssertFalse(state.isTracking)
        }
    }

    func testSimulatedMonitorInstallFailureCanRollBackTracking() {
        var state = OrbDragLifecycleState()
        XCTAssertTrue(state.beginTracking())
        XCTAssertTrue(state.cleanup())
        XCTAssertFalse(state.beginNativeDrag())
        XCTAssertFalse(state.isTracking)
    }

    func testSimulatedMissingMouseUpRecoversOnNextMouseDown() {
        var state = OrbDragLifecycleState()
        XCTAssertTrue(state.beginTracking())
        XCTAssertTrue(state.beginNativeDrag())
        state.nativeDragReturned()
        XCTAssertTrue(state.recoverForNewMouseDown())
        XCTAssertTrue(state.cleanup())
        XCTAssertTrue(state.beginTracking())
    }

    func testSimulatedCleanupIsIdempotent() {
        var state = OrbDragLifecycleState()
        XCTAssertTrue(state.beginTracking())
        XCTAssertTrue(state.cleanup())
        XCTAssertFalse(state.cleanup())
    }

    func testSimulatedNewMouseDownCannotReplaceNativeCallInProgress() {
        var state = OrbDragLifecycleState()
        XCTAssertTrue(state.beginTracking())
        XCTAssertTrue(state.beginNativeDrag())
        XCTAssertFalse(state.recoverForNewMouseDown())
        XCTAssertFalse(state.beginTracking())
    }

    func testSimulatedDetachOnlyCancelsWhenButtonReleasedAndNativeCallReturned() {
        var state = OrbDragLifecycleState()
        XCTAssertTrue(state.beginTracking())
        XCTAssertFalse(state.canCancelForDetach(leftButtonDown: true))
        XCTAssertTrue(state.canCancelForDetach(leftButtonDown: false))
        XCTAssertTrue(state.cleanup())

        XCTAssertTrue(state.beginTracking())
        XCTAssertTrue(state.beginNativeDrag())
        XCTAssertFalse(state.canCancelForDetach(leftButtonDown: false))
    }

    func testSimulatedMouseUpDuringNativeCallDefersCleanupUntilReturn() {
        var state = OrbDragLifecycleState()
        XCTAssertTrue(state.beginTracking())
        XCTAssertTrue(state.beginNativeDrag())
        XCTAssertFalse(state.observeMouseUp())
        XCTAssertTrue(state.cleanupPending)
        state.nativeDragReturned()
        XCTAssertTrue(state.cleanupPending)
        XCTAssertTrue(state.cleanup())
        XCTAssertFalse(state.isTracking)
    }
}
