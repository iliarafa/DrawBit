import XCTest
@testable import Bitme

final class CanvasSizeTests: XCTestCase {
    func testAllCasesExist() {
        XCTAssertEqual(CanvasSize.allCases, [.s16, .s32, .s64, .s128])
    }

    func testDimensionMatchesRaw() {
        XCTAssertEqual(CanvasSize.s16.dimension, 16)
        XCTAssertEqual(CanvasSize.s32.dimension, 32)
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
