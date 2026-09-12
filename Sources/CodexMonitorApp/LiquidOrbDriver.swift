import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class LiquidOrbPresentationStore: ObservableObject {
    @Published private(set) var presentation: LiquidOrbPresentation

    init(diameter: CGFloat) { presentation = .rest(diameter: Double(diameter)) }

    func update(_ presentation: LiquidOrbPresentation) {
        guard self.presentation != presentation else { return }
        self.presentation = presentation
    }
}

struct LiquidOrbMouseSample {
    let location: CGPoint
    let isLeftButtonDown: Bool
}

/// Passive observer of real AppKit panel movement. It never receives mouse
/// events and never mutates the NSPanel frame.
@MainActor
final class LiquidOrbDriver {
    private let clock: any LiquidOrbFrameClock
    private let reduceMotion: () -> Bool
    private let centerProvider: () -> CGPoint
    private let mouseProvider: () -> LiquidOrbMouseSample
    private let onPresentation: (LiquidOrbPresentation) -> Void
    private var cancellation: (any LiquidOrbFrameCancellation)?
    private var dynamics: LiquidOrbDynamics?
    private var dragStartMouse = CGPoint.zero
    private var dragStartVisibleOrbCenter = CGPoint.zero
    private var lastPhysicsInputCenter = CGPoint.zero
    private var lastFrameMilliseconds: Double?
    private var diameter = CGFloat.zero
    private var isUserDragging = false
    private(set) var lastInputVelocityForTesting = LiquidOrbVector.zero

    init(
        clock: any LiquidOrbFrameClock = LiquidOrbRunLoopFrameClock(),
        reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
        centerProvider: @escaping () -> CGPoint,
        mouseProvider: @escaping () -> LiquidOrbMouseSample = {
            LiquidOrbMouseSample(location: NSEvent.mouseLocation, isLeftButtonDown: NSEvent.pressedMouseButtons & 1 != 0)
        },
        onPresentation: @escaping (LiquidOrbPresentation) -> Void
    ) {
        self.clock = clock
        self.reduceMotion = reduceMotion
        self.centerProvider = centerProvider
        self.mouseProvider = mouseProvider
        self.onPresentation = onPresentation
    }

    deinit { MainActor.assumeIsolated { cancellation?.cancel() } }

    func attach(diameter: CGFloat) {
        let center = centerProvider()
        guard Self.valid(center: center, diameter: diameter) else { return }
        stopClock()
        self.diameter = diameter
        dragStartVisibleOrbCenter = center
        lastPhysicsInputCenter = center
        lastFrameMilliseconds = nil
        isUserDragging = false
        lastInputVelocityForTesting = .zero
        dynamics = LiquidOrbDynamics(diameter: Double(diameter))
        onPresentation(.rest(diameter: Double(diameter)))
    }

    /// Records the same origin point as QA's mouseDown, but never consumes an
    /// event or moves the native panel. The physics clock samples later.
    func beginUserDrag() {
        let mouse = mouseProvider()
        guard mouse.isLeftButtonDown, let dynamics else { return }
        let center = centerProvider()
        guard Self.valid(center: center, diameter: diameter) else { return }
        self.dynamics = dynamics
        dragStartMouse = mouse.location
        dragStartVisibleOrbCenter = center
        lastPhysicsInputCenter = center
        lastInputVelocityForTesting = .zero
        isUserDragging = true
        startClockIfNeeded()
    }

    /// Window movement remains a product concern. It deliberately has no
    /// velocity calculation, preventing notification cadence from becoming a
    /// competing physics input during native dragging.
    func panelDidMove() {}

    /// A preference-driven diameter update is an immediate static geometry
    /// reset, never a drag sample or source of velocity.
    func resetForDiameterIfNeeded(_ diameter: CGFloat) {
        guard Self.valid(center: centerProvider(), diameter: diameter) else { return }
        guard abs(self.diameter - diameter) > 0.001 else { return }
        attach(diameter: diameter)
    }

    func shutdown() {
        stopClock()
        dynamics = nil
    }

    var isClockRunningForTesting: Bool { cancellation != nil }

    private func advanceFrame(at nowMilliseconds: Double) {
        guard var dynamics else { return }
        guard !reduceMotion() else {
            dynamics.reset()
            self.dynamics = dynamics
            stopClock()
            onPresentation(.rest(diameter: Double(diameter)))
            return
        }
        let delta = Self.frameDelta(now: nowMilliseconds, previous: lastFrameMilliseconds)
        lastFrameMilliseconds = nowMilliseconds
        let velocity = nextQAEquivalentVelocity(delta: delta)
        lastInputVelocityForTesting = velocity
        dynamics.advance(centerVelocity: velocity, deltaTime: delta)
        if velocity.length < 0.01, dynamics.isSettled {
            dynamics.reset()
            self.dynamics = dynamics
            stopClock()
            onPresentation(.rest(diameter: Double(diameter)))
            return
        }
        self.dynamics = dynamics
        let contour = dynamics.contour
        let average = contour.points.reduce(.zero, +) / Double(contour.points.count)
        let maxRadius = contour.points.map(\.length).max() ?? Double(diameter) / 2
        let baseRadius = Double(diameter) / 2
        let transform = LiquidOrbContentTransform(
            translation: CGSize(width: max(-2.5, min(2.5, average.x * 0.18)), height: max(-2.5, min(2.5, average.y * 0.18))),
            scale: max(0.97, min(1.03, maxRadius / baseRadius)),
            rotationDegrees: 0
        )
        onPresentation(.init(contour: contour, contentTransform: transform))
    }

    private func startClockIfNeeded() {
        guard cancellation == nil else { return }
        // Match the QA wake contract: establish a coherent real panel center
        // before the first tick, preventing a synthetic first-frame impulse.
        lastFrameMilliseconds = nil
        cancellation = clock.start { [weak self] in
            guard let self else { return }
            self.advanceFrame(at: self.clock.nowMilliseconds)
        }
    }

    private func stopClock() {
        cancellation?.cancel()
        cancellation = nil
        lastFrameMilliseconds = nil
    }

    private func nextQAEquivalentVelocity(delta: Double) -> LiquidOrbVector {
        guard isUserDragging else { return .zero }
        let mouse = mouseProvider()
        guard mouse.isLeftButtonDown else {
            isUserDragging = false
            return .zero
        }
        let currentInputCenter = CGPoint(
            x: dragStartVisibleOrbCenter.x + mouse.location.x - dragStartMouse.x,
            y: dragStartVisibleOrbCenter.y + mouse.location.y - dragStartMouse.y
        )
        let velocity = LiquidOrbVector(
            x: Double(currentInputCenter.x - lastPhysicsInputCenter.x) / delta,
            y: Double(currentInputCenter.y - lastPhysicsInputCenter.y) / delta
        )
        lastPhysicsInputCenter = currentInputCenter
        return velocity
    }

    private static func frameDelta(now: Double, previous: Double?) -> Double {
        guard let previous else { return 1.0 / 60.0 }
        return min(max((now - previous) / 1_000, 1.0 / 240.0), LiquidOrbDynamics.maximumExternalDelta)
    }

    private static func valid(center: CGPoint, diameter: CGFloat) -> Bool {
        center.x.isFinite && center.y.isFinite && diameter.isFinite && diameter > 0
    }

    var nodeStatesForTesting: [LiquidOrbNodeState] { dynamics?.nodeStatesForTesting ?? [] }
    var diameterForTesting: CGFloat { diameter }
    var isUserDraggingForTesting: Bool { isUserDragging }
}
