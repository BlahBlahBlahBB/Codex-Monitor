import XCTest
@testable import CodexMonitorApp

final class LiquidOrbRenderTransformTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 110, height: 110)

    func testLegacyDiagnosticShowsOppositeVerticalScreenDirections() {
        let canonical = translatedCircle(by: .init(x: 0, y: 10)).localPath()
        // Before this correction, the pre-flipped canonical path was fed to
        // both renderers. Convert each local result into canonical y-up screen
        // displacement to show the observed -10 / +10 split.
        let legacyPath = transformed(canonical, with: .init(scaleX: 1, y: -1))
        let appKitLocalY = legacyPath.boundingBox.midY
        let swiftUILocalY = LiquidOrbRenderTransform.appKitPath(legacyPath, in: bounds).boundingBox.midY
        XCTAssertEqual(appKitLocalY, -10, accuracy: 1e-10)
        XCTAssertEqual(bounds.midY - swiftUILocalY, 10, accuracy: 1e-10)
    }

    func testHorizontalBodyAndRingRenderedDisplacementsAgree() {
        assertRenderedDisplacement(body: .init(x: 10, y: 0), expected: .init(x: 10, y: 0))
    }

    func testVerticalBodyAndRingRenderedDisplacementsAgree() {
        assertRenderedDisplacement(body: .init(x: 0, y: 10), expected: .init(x: 0, y: 10))
    }

    func testDiagonalBodyAndRingRenderedQuadrantsAgree() {
        assertRenderedDisplacement(body: .init(x: -8, y: 11), expected: .init(x: -8, y: 11))
    }

    func testTextYTranslationUsesTheSameCanonicalDirectionAsBody() {
        let rendered = LiquidOrbRenderTransform.swiftUITranslation(CGSize(width: 1.8, height: 2.5))
        XCTAssertEqual(rendered.width, 1.8, accuracy: 1e-10)
        XCTAssertEqual(rendered.height, -2.5, accuracy: 1e-10)
    }

    func testRestCircleRenderBoundsRemainUnchanged() {
        let path = LiquidOrbContour.circle(diameter: 90).localPath()
        let appKit = LiquidOrbRenderTransform.appKitPath(path, in: bounds).boundingBox
        let swiftUI = LiquidOrbRenderTransform.swiftUIPath(path, in: bounds).boundingBox
        XCTAssertEqual(appKit, swiftUI)
        XCTAssertEqual(appKit, CGRect(x: 10, y: 10, width: 90, height: 90))
    }

    private func assertRenderedDisplacement(body displacement: LiquidOrbVector, expected: LiquidOrbVector) {
        let body = translatedCircle(by: displacement)
        let ring = body.inwardOffset(by: 4.5)
        for path in [body.localPath(), ring.localPath()] {
            let appKit = LiquidOrbRenderTransform.appKitPath(path, in: bounds).boundingBox
            let swiftUI = LiquidOrbRenderTransform.swiftUIPath(path, in: bounds).boundingBox
            XCTAssertEqual(appKit.midX - bounds.midX, expected.x, accuracy: 1e-10)
            XCTAssertEqual(appKit.midY - bounds.midY, expected.y, accuracy: 1e-10)
            XCTAssertEqual(swiftUI.midX - bounds.midX, expected.x, accuracy: 1e-10)
            XCTAssertEqual(bounds.midY - swiftUI.midY, expected.y, accuracy: 1e-10)
        }
    }

    private func translatedCircle(by displacement: LiquidOrbVector) -> LiquidOrbContour {
        let base = LiquidOrbContour.circle(diameter: 90)
        return .init(diameter: 90, points: base.points.map { $0 + displacement })
    }

    private func transformed(_ path: CGPath, with transform: CGAffineTransform) -> CGPath {
        let result = CGMutablePath()
        result.addPath(path, transform: transform)
        return result
    }
}
