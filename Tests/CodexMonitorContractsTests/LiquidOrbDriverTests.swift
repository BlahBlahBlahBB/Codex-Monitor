import AppKit
import XCTest
@testable import CodexMonitorApp

@MainActor
final class LiquidOrbDriverTests: XCTestCase {
    func testQAEquivalentMouseDeltaInputIgnoresPanelNotificationCadence() {
        let fixture = makeFixture()
        fixture.mouse = .init(location: .zero, isLeftButtonDown: true)
        fixture.driver.beginUserDrag()
        fixture.driver.panelDidMove()
        fixture.driver.panelDidMove()
        fixture.mouse = .init(location: CGPoint(x: 30, y: -10), isLeftButtonDown: true)
        fixture.clock.fire(at: 0)

        XCTAssertEqual(fixture.driver.lastInputVelocityForTesting.x, 1_800, accuracy: 1e-10)
        XCTAssertEqual(fixture.driver.lastInputVelocityForTesting.y, -600, accuracy: 1e-10)
    }

    func testFirstUserDragFrameStartsWithZeroVirtualVelocityAndNoImpulse() {
        let fixture = makeFixture()
        fixture.mouse = .init(location: .zero, isLeftButtonDown: true)
        fixture.driver.beginUserDrag()
        fixture.clock.fire(at: 0)

        XCTAssertEqual(fixture.driver.lastInputVelocityForTesting, .zero)
        XCTAssertTrue(fixture.driver.nodeStatesForTesting.allSatisfy {
            $0.displacement == .zero && $0.velocity == .zero
        })
    }

    func testResizeImmediatelyPublishesNewCircularRestGeometryWithoutInputImpulse() {
        let fixture = makeFixture()
        fixture.mouse = .init(location: .zero, isLeftButtonDown: true)
        fixture.driver.beginUserDrag()
        fixture.mouse = .init(location: CGPoint(x: 24, y: 0), isLeftButtonDown: true)
        fixture.clock.fire(at: 0)

        fixture.driver.resetForDiameterIfNeeded(180)

        XCTAssertEqual(fixture.driver.diameterForTesting, 180)
        XCTAssertEqual(fixture.driver.lastInputVelocityForTesting, .zero)
        XCTAssertFalse(fixture.driver.isUserDraggingForTesting)
        XCTAssertTrue(fixture.driver.nodeStatesForTesting.allSatisfy {
            $0.displacement == .zero && $0.velocity == .zero
        })
        XCTAssertEqual(fixture.presentation?.contour.diameter, 180)
        XCTAssertEqual(fixture.presentation?.ringContour.diameter, 162)
        XCTAssertEqual(fixture.presentation?.contentTransform, .init())
    }

    private func makeFixture() -> Fixture {
        let fixture = Fixture()
        fixture.driver = LiquidOrbDriver(
            clock: fixture.clock,
            reduceMotion: { false },
            centerProvider: { fixture.center },
            mouseProvider: { fixture.mouse },
            onPresentation: { fixture.presentation = $0 }
        )
        fixture.driver.attach(diameter: 90)
        return fixture
    }
}

@MainActor
private final class Fixture {
    let clock = ManualLiquidOrbFrameClock()
    var center = CGPoint(x: 300, y: 200)
    var mouse = LiquidOrbMouseSample(location: .zero, isLeftButtonDown: false)
    var presentation: LiquidOrbPresentation?
    var driver: LiquidOrbDriver!
}

@MainActor
private final class ManualLiquidOrbFrameClock: LiquidOrbFrameClock {
    private var tick: (@MainActor () -> Void)?
    private(set) var nowMilliseconds = 0.0
    private let cancellation = Cancellation()

    func start(_ tick: @escaping @MainActor () -> Void) -> any LiquidOrbFrameCancellation {
        self.tick = tick
        return cancellation
    }

    func fire(at milliseconds: Double) {
        guard !cancellation.cancelled else { return }
        nowMilliseconds = milliseconds
        tick?()
    }
}

@MainActor
private final class Cancellation: LiquidOrbFrameCancellation {
    private(set) var cancelled = false
    func cancel() { cancelled = true }
}
