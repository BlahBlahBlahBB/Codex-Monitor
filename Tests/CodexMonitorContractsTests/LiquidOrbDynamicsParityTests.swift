import Foundation
import XCTest
@testable import CodexMonitorApp

/// Independent transcription of `Tools/LiquidRingQA/LiquidRingEngine.swift`
/// using the approved production damping (13.5). This keeps the parity oracle
/// separate from `LiquidOrbDynamics` while preserving the QA equations.
final class LiquidOrbDynamicsParityTests: XCTestCase {
    func testApprovedQASemanticsMatchEveryProductionNodeForMixedDragSequence() {
        var reference = ApprovedQAReference()
        var production = LiquidOrbDynamics(diameter: 90)
        let frames = sequence()

        for (frame, input) in frames.enumerated() {
            reference.advance(velocity: input.velocity, delta: input.delta)
            production.advance(centerVelocity: LiquidOrbVector(x: input.velocity.x, y: input.velocity.y), deltaTime: input.delta)
            let states = production.nodeStatesForTesting
            XCTAssertEqual(states.count, 32, "frame \(frame)")
            for node in 0..<32 {
                XCTAssertEqual(states[node].displacement.x, reference.nodes[node].displacement.x, accuracy: 1e-10, "frame \(frame), node \(node), displacement.x")
                XCTAssertEqual(states[node].displacement.y, reference.nodes[node].displacement.y, accuracy: 1e-10, "frame \(frame), node \(node), displacement.y")
                XCTAssertEqual(states[node].velocity.x, reference.nodes[node].velocity.x, accuracy: 1e-10, "frame \(frame), node \(node), velocity.x")
                XCTAssertEqual(states[node].velocity.y, reference.nodes[node].velocity.y, accuracy: 1e-10, "frame \(frame), node \(node), velocity.y")
            }
        }
    }

    private func sequence() -> [(velocity: ReferenceVector, delta: Double)] {
        let tick = 1.0 / 60.0
        var frames: [(ReferenceVector, Double)] = []
        // Constant speed, acceleration from rest, sudden stop, reversal,
        // changing direction, then a full settlement tail.
        frames += Array(repeating: (ReferenceVector(x: 900, y: 0), tick), count: 24)
        frames += [(ReferenceVector(x: 1_900, y: 0), tick), (ReferenceVector(x: 0, y: 0), tick)]
        frames += Array(repeating: (ReferenceVector(x: -1_200, y: 240), tick), count: 18)
        frames += (0..<36).map { index in
            let angle = Double(index) * .pi * 2 / 36
            return (ReferenceVector(x: 1_050 * cos(angle), y: 1_050 * sin(angle)), index.isMultiple(of: 7) ? 1.0 / 90.0 : tick)
        }
        frames += Array(repeating: (ReferenceVector.zero, tick), count: 360)
        return frames
    }
}

private struct ReferenceVector {
    var x: Double
    var y: Double
    static let zero = Self(x: 0, y: 0)
    static func + (left: Self, right: Self) -> Self { .init(x: left.x + right.x, y: left.y + right.y) }
    static func - (left: Self, right: Self) -> Self { .init(x: left.x - right.x, y: left.y - right.y) }
    static prefix func - (value: Self) -> Self { .init(x: -value.x, y: -value.y) }
    static func * (value: Self, scalar: Double) -> Self { .init(x: value.x * scalar, y: value.y * scalar) }
    static func / (value: Self, scalar: Double) -> Self { .init(x: value.x / scalar, y: value.y / scalar) }
    var length: Double { hypot(x, y) }
    func dot(_ other: Self) -> Double { x * other.x + y * other.y }
    func normalized(or fallback: Self = .zero) -> Self { length > 1e-9 ? self / length : fallback }
    func clampedLength(_ maximum: Double) -> Self { length > maximum ? self * (maximum / length) : self }
}

private struct ReferenceNode {
    var displacement = ReferenceVector.zero
    var velocity = ReferenceVector.zero
}

private struct ApprovedQAReference {
    private static let nodeCount = 32
    private static let radius = 45.0
    private static let maximumDrive = 10_000.0
    private static let maximumExternalDelta = 1.0 / 15.0
    private static let substep = 1.0 / 240.0

    private let restPositions: [ReferenceVector]
    private let restEdgeLength: Double
    private let targetArea: Double
    var nodes: [ReferenceNode]
    private var previousCenterVelocity = ReferenceVector.zero

    init() {
        let positions = (0..<Self.nodeCount).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(Self.nodeCount)
            return ReferenceVector(x: Self.radius * cos(angle), y: Self.radius * sin(angle))
        }
        restPositions = positions
        restEdgeLength = 2 * Self.radius * sin(Double.pi / Double(Self.nodeCount))
        targetArea = Self.polygonArea(positions)
        nodes = Array(repeating: ReferenceNode(), count: Self.nodeCount)
    }

    mutating func advance(velocity: ReferenceVector, delta rawDelta: Double) {
        let delta = min(rawDelta, Self.maximumExternalDelta)
        let acceleration = (velocity - previousCenterVelocity) / delta
        previousCenterVelocity = velocity
        let drive = (velocity * 8.0 + acceleration * 0.080).clampedLength(Self.maximumDrive)
        let steps = max(1, Int(ceil(delta / Self.substep)))
        let step = delta / Double(steps)
        for _ in 0..<steps { integrate(drive: drive, delta: step) }
    }

    private var points: [ReferenceVector] { zip(restPositions, nodes).map { $0 + $1.displacement } }

    private mutating func integrate(drive: ReferenceVector, delta: Double) {
        let boundary = points
        let areaError = (targetArea - Self.polygonArea(boundary)) / targetArea
        var forces = Array(repeating: ReferenceVector.zero, count: Self.nodeCount)
        for index in boundary.indices {
            let previousIndex = (index - 1 + Self.nodeCount) % Self.nodeCount
            let nextIndex = (index + 1) % Self.nodeCount
            let previous = boundary[previousIndex]
            let current = boundary[index]
            let next = boundary[nextIndex]
            let tangent = (next - previous).normalized(or: .init(x: 0, y: 1))
            let outward = ReferenceVector(x: tangent.y, y: -tangent.x)
            var force = -nodes[index].displacement * 440.0
            force = force + (nodes[previousIndex].displacement + nodes[nextIndex].displacement - nodes[index].displacement * 2) * 280.0
            force = force + edgeForce(from: current, to: previous) + edgeForce(from: current, to: next)
            force = force - nodes[index].velocity * 13.5
            force = force + outward * (7_200.0 * areaError)
            force = force - outward * outward.dot(drive)
            force = force - tangent * (0.0 * tangent.dot(drive))
            forces[index] = force
        }
        for index in nodes.indices {
            nodes[index].velocity = nodes[index].velocity + forces[index] * delta
            nodes[index].displacement = nodes[index].displacement + nodes[index].velocity * delta
            clamp(index)
        }
        removeCenterDrift()
        for index in nodes.indices { clamp(index) }
    }

    private mutating func clamp(_ index: Int) {
        let magnitude = nodes[index].displacement.length
        guard magnitude > 24.0 else { return }
        let direction = nodes[index].displacement / magnitude
        nodes[index].displacement = direction * 24.0
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

    private func edgeForce(from current: ReferenceVector, to neighbor: ReferenceVector) -> ReferenceVector {
        let delta = neighbor - current
        guard delta.length > 1e-9 else { return .zero }
        return delta / delta.length * (640.0 * (delta.length - restEdgeLength))
    }

    private static func polygonArea(_ points: [ReferenceVector]) -> Double {
        abs(points.indices.reduce(0) { area, index in
            let next = points[(index + 1) % points.count]
            return area + points[index].x * next.y - next.x * points[index].y
        }) * 0.5
    }
}
