import CoreGraphics
import Foundation

struct LiquidOrbVector: Equatable {
    var x: Double
    var y: Double

    static let zero = Self(x: 0, y: 0)
    static func + (left: Self, right: Self) -> Self { Self(x: left.x + right.x, y: left.y + right.y) }
    static func - (left: Self, right: Self) -> Self { Self(x: left.x - right.x, y: left.y - right.y) }
    static prefix func - (value: Self) -> Self { Self(x: -value.x, y: -value.y) }
    static func * (value: Self, scalar: Double) -> Self { Self(x: value.x * scalar, y: value.y * scalar) }
    static func / (value: Self, scalar: Double) -> Self { Self(x: value.x / scalar, y: value.y / scalar) }

    var length: Double { hypot(x, y) }
    var isFinite: Bool { x.isFinite && y.isFinite }
    func dot(_ other: Self) -> Double { x * other.x + y * other.y }
    func normalized(or fallback: Self = .zero) -> Self { length > 1e-9 ? self / length : fallback }
    func clampedLength(_ maximum: Double) -> Self { length > maximum ? self * (maximum / length) : self }
}

struct LiquidOrbNodeState: Equatable {
    var displacement = LiquidOrbVector.zero
    var velocity = LiquidOrbVector.zero
}

struct LiquidOrbParameters: Equatable {
    let velocityDriveGain = 8.0
    let accelerationDriveGain = 0.080
    let tangentialDriveFraction = 0.0
    let restStiffness = 440.0
    let damping = 13.5
    let neighborCoupling = 280.0
    let edgeStiffness = 640.0
    let areaPressure = 7_200.0
    let maximumLocalDisplacement = 24.0
}

struct LiquidOrbContour: Equatable {
    let diameter: Double
    let points: [LiquidOrbVector]

    static func circle(diameter: Double) -> Self {
        let radius = diameter / 2
        return Self(diameter: diameter, points: (0..<LiquidOrbDynamics.nodeCount).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(LiquidOrbDynamics.nodeCount)
            return LiquidOrbVector(x: radius * cos(angle), y: radius * sin(angle))
        })
    }

    func scaled(_ factor: Double) -> Self {
        Self(diameter: diameter * factor, points: points.map { $0 * factor })
    }

    /// Creates the status-ring contour from this exact body node set. The
    /// winding selects the inward normal, so asymmetrical local displacement
    /// is retained instead of being attenuated by a center scale.
    func inwardOffset(by inset: Double) -> Self {
        guard points.count >= 3, inset.isFinite, inset >= 0 else { return self }
        let winding = Self.signedArea(points)
        guard winding.isFinite, abs(winding) > 1e-9 else { return self }
        let offsetPoints = points.indices.map { index -> LiquidOrbVector in
            let previous = points[(index - 1 + points.count) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let tangent = (next - previous).normalized()
            guard tangent.length > 1e-9 else { return current }
            // Counter-clockwise contours use the left normal as inward;
            // clockwise contours use the right normal.
            let inward = winding > 0
                ? LiquidOrbVector(x: -tangent.y, y: tangent.x)
                : LiquidOrbVector(x: tangent.y, y: -tangent.x)
            let candidate = current + inward * inset
            return candidate.isFinite ? candidate : current
        }
        return Self(diameter: diameter - inset * 2, points: offsetPoints)
    }

    var signedArea: Double { Self.signedArea(points) }

    func localPath() -> CGPath {
        guard !points.isEmpty else { return CGMutablePath() }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for index in points.indices {
            let previous = points[(index - 1 + points.count) % points.count]
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let next = points[(index + 2) % points.count]
            path.addCurve(
                to: CGPoint(x: end.x, y: end.y),
                control1: CGPoint(x: start.x + (end.x - previous.x) / 6, y: start.y + (end.y - previous.y) / 6),
                control2: CGPoint(x: end.x - (next.x - start.x) / 6, y: end.y - (next.y - start.y) / 6)
            )
        }
        path.closeSubpath()
        return path
    }

    private static func signedArea(_ points: [LiquidOrbVector]) -> Double {
        guard !points.isEmpty else { return 0 }
        return points.indices.reduce(0) { area, index in
            let next = points[(index + 1) % points.count]
            return area + points[index].x * next.y - next.x * points[index].y
        } * 0.5
    }
}

/// Liquid dynamics are canonical local x-right/y-up coordinates. AppKit's
/// default NSView coordinates are y-up, while SwiftUI local coordinates are
/// y-down. This is the sole rendering-boundary decision about vertical axis.
enum LiquidOrbRenderTransform {
    static func appKitPath(_ canonicalPath: CGPath, in bounds: CGRect) -> CGPath {
        transformed(canonicalPath, with: CGAffineTransform(translationX: bounds.midX, y: bounds.midY))
    }

    static func swiftUIPath(_ canonicalPath: CGPath, in bounds: CGRect) -> CGPath {
        transformed(canonicalPath, with: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: bounds.midX, ty: bounds.midY))
    }

    static func swiftUITranslation(_ canonical: CGSize) -> CGSize {
        CGSize(width: canonical.width, height: -canonical.height)
    }

    private static func transformed(_ path: CGPath, with transform: CGAffineTransform) -> CGPath {
        let result = CGMutablePath()
        result.addPath(path, transform: transform)
        return result
    }
}

struct LiquidOrbContentTransform: Equatable {
    var translation: CGSize = .zero
    var scale = 1.0
    var rotationDegrees = 0.0
}

/// CGPath is immutable after construction. This wrapper documents the safe
/// cross-layer handoff of one frame's prebuilt master path.
struct LiquidOrbPath: @unchecked Sendable {
    let cgPath: CGPath
}

struct LiquidOrbPresentation: Equatable {
    var contour: LiquidOrbContour
    var ringContour: LiquidOrbContour
    var contentTransform: LiquidOrbContentTransform
    let masterPath: LiquidOrbPath
    let ringPath: LiquidOrbPath

    init(contour: LiquidOrbContour, contentTransform: LiquidOrbContentTransform) {
        self.contour = contour
        ringContour = contour.inwardOffset(by: contour.diameter * 0.05)
        self.contentTransform = contentTransform
        masterPath = LiquidOrbPath(cgPath: contour.localPath())
        ringPath = LiquidOrbPath(cgPath: ringContour.localPath())
    }

    static func == (left: Self, right: Self) -> Bool {
        left.contour == right.contour
            && left.ringContour == right.ringContour
            && left.contentTransform == right.contentTransform
    }

    static func rest(diameter: Double) -> Self {
        let contour = LiquidOrbContour.circle(diameter: diameter)
        return Self(contour: contour, contentTransform: .init())
    }

}

/// Direct production port of the approved LiquidRingQA node equations.
struct LiquidOrbDynamics {
    static let nodeCount = 32
    static let maximumDrive = 10_000.0
    static let maximumExternalDelta = 1.0 / 15.0
    private static let substep = 1.0 / 240.0

    let parameters = LiquidOrbParameters()
    private let restPositions: [LiquidOrbVector]
    private let restEdgeLength: Double
    private let targetArea: Double
    private var nodes: [LiquidOrbNodeState]
    private var previousCenterVelocity = LiquidOrbVector.zero
    private let diameter: Double

    init(diameter: Double) {
        self.diameter = diameter
        let radius = diameter / 2
        let positions = (0..<Self.nodeCount).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(Self.nodeCount)
            return LiquidOrbVector(x: radius * cos(angle), y: radius * sin(angle))
        }
        restPositions = positions
        restEdgeLength = 2 * radius * sin(Double.pi / Double(Self.nodeCount))
        targetArea = Self.polygonArea(positions)
        nodes = Array(repeating: LiquidOrbNodeState(), count: Self.nodeCount)
    }

    var contour: LiquidOrbContour { LiquidOrbContour(diameter: diameter, points: points) }
    var isSettled: Bool { nodes.allSatisfy { $0.displacement.length < 0.025 && $0.velocity.length < 0.05 } }
    var nodeStatesForTesting: [LiquidOrbNodeState] { nodes }

    mutating func advance(centerVelocity: LiquidOrbVector, deltaTime rawDelta: Double) {
        guard centerVelocity.isFinite, rawDelta.isFinite, rawDelta > 0 else { return }
        let delta = min(rawDelta, Self.maximumExternalDelta)
        let acceleration = (centerVelocity - previousCenterVelocity) / delta
        previousCenterVelocity = centerVelocity
        let drive = (centerVelocity * parameters.velocityDriveGain + acceleration * parameters.accelerationDriveGain)
            .clampedLength(Self.maximumDrive)
        let steps = max(1, Int(ceil(delta / Self.substep)))
        let h = delta / Double(steps)
        for _ in 0..<steps { integrateSubstep(drive: drive, deltaTime: h) }
        if !nodes.allSatisfy({ $0.displacement.isFinite && $0.velocity.isFinite }) { reset() }
    }

    mutating func reset() {
        nodes = Array(repeating: LiquidOrbNodeState(), count: Self.nodeCount)
        previousCenterVelocity = .zero
    }

    private var points: [LiquidOrbVector] { zip(restPositions, nodes).map { $0 + $1.displacement } }

    private mutating func integrateSubstep(drive: LiquidOrbVector, deltaTime: Double) {
        let boundary = points
        let areaError = (targetArea - Self.polygonArea(boundary)) / targetArea
        var forces = Array(repeating: LiquidOrbVector.zero, count: Self.nodeCount)
        for index in boundary.indices {
            let previousIndex = (index - 1 + Self.nodeCount) % Self.nodeCount
            let nextIndex = (index + 1) % Self.nodeCount
            let previous = boundary[previousIndex]
            let current = boundary[index]
            let next = boundary[nextIndex]
            let tangent = (next - previous).normalized(or: LiquidOrbVector(x: 0, y: 1))
            let outward = LiquidOrbVector(x: tangent.y, y: -tangent.x)
            var force = -nodes[index].displacement * parameters.restStiffness
            force = force + (nodes[previousIndex].displacement + nodes[nextIndex].displacement - nodes[index].displacement * 2) * parameters.neighborCoupling
            force = force + edgeForce(from: current, to: previous) + edgeForce(from: current, to: next)
            force = force - nodes[index].velocity * parameters.damping
            force = force + outward * (parameters.areaPressure * areaError)
            force = force - outward * outward.dot(drive)
            force = force - tangent * (parameters.tangentialDriveFraction * tangent.dot(drive))
            forces[index] = force
        }
        for index in nodes.indices {
            nodes[index].velocity = nodes[index].velocity + forces[index] * deltaTime
            nodes[index].displacement = nodes[index].displacement + nodes[index].velocity * deltaTime
            clampNode(at: index)
        }
        removeCenterDrift()
        for index in nodes.indices { clampNode(at: index) }
    }

    private mutating func clampNode(at index: Int) {
        let magnitude = nodes[index].displacement.length
        guard magnitude > parameters.maximumLocalDisplacement else { return }
        let direction = nodes[index].displacement / magnitude
        nodes[index].displacement = direction * parameters.maximumLocalDisplacement
        let outwardVelocity = nodes[index].velocity.dot(direction)
        if outwardVelocity > 0 { nodes[index].velocity = nodes[index].velocity - direction * outwardVelocity }
    }

    private mutating func removeCenterDrift() {
        let count = Double(Self.nodeCount)
        let meanDisplacement = nodes.reduce(.zero) { $0 + $1.displacement } / count
        let meanVelocity = nodes.reduce(.zero) { $0 + $1.velocity } / count
        for index in nodes.indices {
            nodes[index].displacement = nodes[index].displacement - meanDisplacement
            nodes[index].velocity = nodes[index].velocity - meanVelocity
        }
    }

    private func edgeForce(from current: LiquidOrbVector, to neighbor: LiquidOrbVector) -> LiquidOrbVector {
        let delta = neighbor - current
        guard delta.length > 1e-9 else { return .zero }
        return delta / delta.length * (parameters.edgeStiffness * (delta.length - restEdgeLength))
    }

    private static func polygonArea(_ points: [LiquidOrbVector]) -> Double {
        abs(points.indices.reduce(0) { area, index in
            let next = points[(index + 1) % points.count]
            return area + points[index].x * next.y - next.x * points[index].y
        }) * 0.5
    }
}
