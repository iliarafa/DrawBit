import XCTest
@testable import DrawBit

final class GridIntensityTests: XCTestCase {

    // MARK: - multiplier (scales the existing zoom-fade in CanvasView.gridOverlay)

    func testMultiplierOffIsZero() {
        XCTAssertEqual(GridIntensity.off.multiplier, 0)
    }

    func testMultiplierSoftIsTheCalmDefault() {
        // The midpoint between the first-cut SOFT (0.35) and invisible — a gentle whisper.
        XCTAssertEqual(GridIntensity.soft.multiplier, 0.175, accuracy: 0.0001)
        XCTAssertGreaterThan(GridIntensity.soft.multiplier, 0)
        XCTAssertLessThan(GridIntensity.soft.multiplier, GridIntensity.strong.multiplier)
    }

    func testMultiplierStrongIsBoldButBelowRetiredLooks() {
        // STRONG carries the first-cut SOFT strength (0.35). Both bolder looks — the original
        // full-strength 1.0 grid and the first-cut STRONG 0.6 — are retired for good.
        XCTAssertEqual(GridIntensity.strong.multiplier, 0.35, accuracy: 0.0001)
        XCTAssertLessThan(GridIntensity.strong.multiplier, 0.6)
    }

    func testExactlyThreeLevelsExist() {
        XCTAssertEqual(GridIntensity.allCases.count, 3)
    }

    // MARK: - next() (the OFF → SOFT → STRONG cycle)

    func testNextCyclesForwardAndWraps() {
        XCTAssertEqual(GridIntensity.off.next(), .soft)
        XCTAssertEqual(GridIntensity.soft.next(), .strong)
        XCTAssertEqual(GridIntensity.strong.next(), .off)
    }
}
