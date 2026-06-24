import XCTest
@testable import DrawBit

final class PixelRectTests: XCTestCase {
    func testFromTwoCornersNormalizes() {
        let r = PixelRect.from((5, 10), (2, 3))
        XCTAssertEqual(r, PixelRect(x: 2, y: 3, width: 4, height: 8))
    }

    func testFromTwoCornersEqualPointsIsOnePixel() {
        let r = PixelRect.from((4, 4), (4, 4))
        XCTAssertEqual(r, PixelRect(x: 4, y: 4, width: 1, height: 1))
    }

    func testContains() {
        let r = PixelRect(x: 2, y: 3, width: 4, height: 8)
        XCTAssertTrue(r.contains(x: 2, y: 3))
        XCTAssertTrue(r.contains(x: 5, y: 10))
        XCTAssertFalse(r.contains(x: 1, y: 3))
        XCTAssertFalse(r.contains(x: 6, y: 3))
        XCTAssertFalse(r.contains(x: 2, y: 11))
    }

    func testClippedFullyInsideReturnsSelf() {
        let r = PixelRect(x: 2, y: 3, width: 4, height: 5)
        XCTAssertEqual(r.clipped(toCanvasDimension: 16), r)
    }

    func testClippedPartiallyOutsideClampsToCanvas() {
        let r = PixelRect(x: -2, y: 14, width: 6, height: 8)
        XCTAssertEqual(
            r.clipped(toCanvasDimension: 16),
            PixelRect(x: 0, y: 14, width: 4, height: 2)
        )
    }

    func testClippedFullyOutsideReturnsNil() {
        XCTAssertNil(PixelRect(x: -10, y: -10, width: 4, height: 4).clipped(toCanvasDimension: 16))
        XCTAssertNil(PixelRect(x: 20, y: 20, width: 4, height: 4).clipped(toCanvasDimension: 16))
    }

    func testClippedToCanvasWidthHeightClipsPerAxis() {
        // 8 wide × 16 tall: x clips at 8, y clips at 16, independently.
        let r = PixelRect(x: 6, y: 6, width: 10, height: 10)
        XCTAssertEqual(
            r.clipped(toCanvasWidth: 8, height: 16),
            PixelRect(x: 6, y: 6, width: 2, height: 10)
        )
    }

    func testTranslated() {
        let r = PixelRect(x: 2, y: 3, width: 4, height: 5)
        XCTAssertEqual(r.translated(dx: 1, dy: -2), PixelRect(x: 3, y: 1, width: 4, height: 5))
    }
}
