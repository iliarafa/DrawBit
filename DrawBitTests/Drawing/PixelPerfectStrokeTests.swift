import XCTest
@testable import DrawBit

final class PixelPerfectStrokeTests: XCTestCase {
    func testFirstTwoPointsNeverProduceElbow() {
        var s = PixelPerfectStroke()
        XCTAssertNil(s.append((0, 0)))
        XCTAssertNil(s.append((1, 0)))
    }

    func testStraightHorizontalNoElbow() {
        var s = PixelPerfectStroke()
        _ = s.append((0, 0))
        _ = s.append((1, 0))
        XCTAssertNil(s.append((2, 0)))
    }

    func testStraightVerticalNoElbow() {
        var s = PixelPerfectStroke()
        _ = s.append((0, 0))
        _ = s.append((0, 1))
        XCTAssertNil(s.append((0, 2)))
    }

    func testLCornerDownThenRightDropsElbow() {
        var s = PixelPerfectStroke()
        _ = s.append((0, 0))
        _ = s.append((1, 0))
        let elbow = s.append((1, 1))
        XCTAssertNotNil(elbow)
        XCTAssertEqual(elbow?.0, 1)
        XCTAssertEqual(elbow?.1, 0)
    }

    func testLCornerDownThenLeftDropsElbow() {
        var s = PixelPerfectStroke()
        _ = s.append((5, 5))
        _ = s.append((5, 6))
        let elbow = s.append((4, 6))
        XCTAssertNotNil(elbow)
        XCTAssertEqual(elbow?.0, 5)
        XCTAssertEqual(elbow?.1, 6)
    }

    func testDiagonalStepsAreNotUnitMovesAndAreNotFiltered() {
        var s = PixelPerfectStroke()
        _ = s.append((0, 0))
        _ = s.append((1, 1))
        XCTAssertNil(s.append((2, 2)))
    }

    func testNonAdjacentSegmentNotFiltered() {
        var s = PixelPerfectStroke()
        _ = s.append((0, 0))
        _ = s.append((5, 5))
        XCTAssertNil(s.append((5, 6)))
    }

    func testUTurnSameAxisIsNotAnLCorner() {
        var s = PixelPerfectStroke()
        _ = s.append((0, 0))
        _ = s.append((1, 0))
        XCTAssertNil(s.append((0, 0)))
    }

    func testElbowRemovedFromHistorySoNextCheckUsesPredecessor() {
        var s = PixelPerfectStroke()
        _ = s.append((0, 0))
        _ = s.append((1, 0))
        _ = s.append((1, 1))         // drops (1,0); history is [(0,0),(1,1)]
        // Now (0,0) → (1,1) is a diagonal step (|dx|+|dy| = 2), not a unit.
        // Adding (2,1) makes (1,1) → (2,1) unit, but the previous segment
        // is non-unit, so no elbow can be detected.
        XCTAssertNil(s.append((2, 1)))
    }

    func testResetClearsHistory() {
        var s = PixelPerfectStroke()
        _ = s.append((0, 0))
        _ = s.append((1, 0))
        s.reset()
        XCTAssertNil(s.append((1, 1)))
        XCTAssertNil(s.append((2, 1)))
    }

    func testRepeatedSamePointDoesNotCountAsUnit() {
        var s = PixelPerfectStroke()
        _ = s.append((3, 3))
        _ = s.append((3, 3))
        XCTAssertNil(s.append((4, 3)))
    }
}
