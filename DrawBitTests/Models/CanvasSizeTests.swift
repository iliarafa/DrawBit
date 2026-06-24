import XCTest
@testable import DrawBit

final class CanvasSizeTests: XCTestCase {
    func testPresetsAreTheFourEvenSquares() {
        // Odd presets (15/31/63) were dropped from the picker once Custom shipped.
        XCTAssertEqual(CanvasSize.presets, [.s16, .s32, .s64, .s128])
    }

    func testCustomDimensionIsHonored() {
        XCTAssertEqual(CanvasSize(48).dimension, 48)
        XCTAssertEqual(CanvasSize(48).displayName, "48 × 48")
        XCTAssertEqual(CanvasSize(48).pixelCount, 48 * 48)
    }

    func testDimensionClampsToBounds() {
        XCTAssertEqual(CanvasSize(0).dimension, CanvasSize.minDimension)
        XCTAssertEqual(CanvasSize(-5).dimension, CanvasSize.minDimension)
        XCTAssertEqual(CanvasSize(9999).dimension, CanvasSize.maxDimension)
    }

    func testDimensionMatchesRaw() {
        XCTAssertEqual(CanvasSize.s15.dimension, 15)
        XCTAssertEqual(CanvasSize.s16.dimension, 16)
        XCTAssertEqual(CanvasSize.s31.dimension, 31)
        XCTAssertEqual(CanvasSize.s32.dimension, 32)
        XCTAssertEqual(CanvasSize.s63.dimension, 63)
        XCTAssertEqual(CanvasSize.s64.dimension, 64)
        XCTAssertEqual(CanvasSize.s128.dimension, 128)
    }

    func testPixelCountMatchesDimensionSquared() {
        XCTAssertEqual(CanvasSize.s16.pixelCount, 256)
        XCTAssertEqual(CanvasSize.s128.pixelCount, 16_384)
    }

    func testByteCountIsPixelsTimesFour() {
        XCTAssertEqual(CanvasSize.s32.byteCount, 4 * 32 * 32)
    }

    // MARK: - Non-square (Stage 1)

    func testSquareInitReportsSquare() {
        let s = CanvasSize(32)
        XCTAssertEqual(s.width, 32)
        XCTAssertEqual(s.height, 32)
        XCTAssertTrue(s.isSquare)
        XCTAssertEqual(s.longestEdge, 32)
    }

    func testNonSquareWidthHeight() {
        let s = CanvasSize(width: 16, height: 9)
        XCTAssertEqual(s.width, 16)
        XCTAssertEqual(s.height, 9)
        XCTAssertFalse(s.isSquare)
        XCTAssertEqual(s.displayName, "16 × 9")
        XCTAssertEqual(s.pixelCount, 16 * 9)
        XCTAssertEqual(s.byteCount, 16 * 9 * 4)
        XCTAssertEqual(s.longestEdge, 16)
    }

    func testNonSquareClampsEachAxisIndependently() {
        let s = CanvasSize(width: 9999, height: 0)
        XCTAssertEqual(s.width, CanvasSize.maxDimension)
        XCTAssertEqual(s.height, CanvasSize.minDimension)
    }

    func testRatioInitProducesExactIntegerSizes() {
        let wide = CanvasSize(ratio: .r16x9, longestEdge: 256)
        XCTAssertEqual(wide.width, 256)
        XCTAssertEqual(wide.height, 144)

        let tall = CanvasSize(ratio: .r9x16, longestEdge: 256)
        XCTAssertEqual(tall.width, 144)
        XCTAssertEqual(tall.height, 256)

        let square = CanvasSize(ratio: .square, longestEdge: 32)
        XCTAssertEqual(square.width, 32)
        XCTAssertEqual(square.height, 32)
    }

    func testRatioInitSnapsLongEdgeToKeepRatioExact() {
        // 200 isn't a clean 16:9 long edge; snap down to 192 (k=12) → 192×108.
        let s = CanvasSize(ratio: .r16x9, longestEdge: 200)
        XCTAssertEqual(s.width, 192)
        XCTAssertEqual(s.height, 108)
        XCTAssertEqual(s.width * 9, s.height * 16)  // exact 16:9
    }
}
