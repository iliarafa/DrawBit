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
}
