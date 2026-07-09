import XCTest
@testable import DrawBit

final class GridIntensityTests: XCTestCase {

    // MARK: - multiplier (scales the existing zoom-fade in CanvasView.gridOverlay)

    func testMultiplierOffIsZero() {
        XCTAssertEqual(GridIntensity.off.multiplier, 0)
    }

    func testMultiplierStrongIsBoldButBelowOldFullStrength() {
        // The old full-strength (1.0) grid was retired as too loud. STRONG is the boldest level but
        // deliberately sits below it.
        XCTAssertEqual(GridIntensity.strong.multiplier, 0.6, accuracy: 0.0001)
        XCTAssertLessThan(GridIntensity.strong.multiplier, 1.0)
    }

    func testMultiplierSoftIsTheCalmDefault() {
        XCTAssertEqual(GridIntensity.soft.multiplier, 0.35, accuracy: 0.0001)
        XCTAssertGreaterThan(GridIntensity.soft.multiplier, 0)
        XCTAssertLessThan(GridIntensity.soft.multiplier, GridIntensity.strong.multiplier)
    }

    // MARK: - next() (the OFF → SOFT → STRONG → OFF cycle)

    func testNextCyclesForwardAndWraps() {
        XCTAssertEqual(GridIntensity.off.next(), .soft)
        XCTAssertEqual(GridIntensity.soft.next(), .strong)
        XCTAssertEqual(GridIntensity.strong.next(), .off)
    }
}
