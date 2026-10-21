import Foundation
import XCTest
@testable import CodexMonitorApp

final class LiquidOrbRingGeometryTests: XCTestCase {
    func testRestRingMatchesTheExistingNinetyPercentCircleRelationship() {
        let body = LiquidOrbContour.circle(diameter: 90)
        let ring = body.inwardOffset(by: 4.5)

        XCTAssertEqual(ring.diameter, 81, accuracy: 1e-12)
        for index in body.points.indices {
            XCTAssertEqual(ring.points[index].x, body.points[index].x * 0.90, accuracy: 1e-10)
            XCTAssertEqual(ring.points[index].y, body.points[index].y * 0.90, accuracy: 1e-10)
        }
    }

    func testOffsetRingRetainsLocalDeformationInsteadOfScalingIt() {
        let rest = LiquidOrbContour.circle(diameter: 90)
        var deformedPoints = rest.points
        deformedPoints[0].x += 15
        let body = LiquidOrbContour(diameter: 90, points: deformedPoints)
        let ring = body.inwardOffset(by: 4.5)

        let ringRestX = rest.points[0].x - 4.5
        XCTAssertEqual(ring.points[0].x - ringRestX, 15, accuracy: 1e-10)
        XCTAssertNotEqual(ring.points[0].x - ringRestX, 13.5, accuracy: 1e-6)
    }

    func testRingIsInsideBodyForRepresentativeApprovedStrongMotion() {
        var dynamics = LiquidOrbDynamics(diameter: 90)
        let sequence = [
            LiquidOrbVector(x: 1_800, y: 0),
            LiquidOrbVector(x: 0, y: -1_600),
            LiquidOrbVector(x: -1_800, y: 200),
            LiquidOrbVector(x: 400, y: 1_700)
        ]
        for velocity in sequence {
            for _ in 0..<18 { dynamics.advance(centerVelocity: velocity, deltaTime: 1.0 / 60.0) }
        }

        let body = dynamics.contour
        let ring = body.inwardOffset(by: body.diameter * 0.05)
        let bodyPath = body.localPath()
        for point in ring.points {
            XCTAssertTrue(bodyPath.contains(CGPoint(x: point.x, y: point.y), using: .winding, transform: .identity))
        }
    }

    func testFivePercentInsetScalesAcrossSupportedOrbSizes() {
        for diameter in [90.0, 113.0, 180.0] {
            let body = LiquidOrbContour.circle(diameter: diameter)
            let ring = body.inwardOffset(by: diameter * 0.05)
            XCTAssertEqual(body.points[0].length - ring.points[0].length, diameter * 0.05, accuracy: 1e-10)
            XCTAssertEqual(ring.diameter, diameter * 0.90, accuracy: 1e-10)
        }
    }

    func testStrongOffsetRingPathIsFiniteAndClosed() {
        var points = LiquidOrbContour.circle(diameter: 90).points
        for index in points.indices { points[index] = points[index] + LiquidOrbVector(x: cos(Double(index)) * 15, y: sin(Double(index) * 15) * 12) }
        let ring = LiquidOrbContour(diameter: 90, points: points).inwardOffset(by: 4.5)
        let path = ring.localPath()

        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(ring.points.allSatisfy { $0.isFinite })
        XCTAssertTrue(path.boundingBox.origin.x.isFinite)
        XCTAssertTrue(path.boundingBox.origin.y.isFinite)
        XCTAssertTrue(path.boundingBox.width.isFinite)
        XCTAssertTrue(path.boundingBox.height.isFinite)
    }
}
