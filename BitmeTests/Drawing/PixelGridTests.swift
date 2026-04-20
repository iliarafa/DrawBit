import XCTest
@testable import Bitme

final class PixelGridTests: XCTestCase {
    func testNewGridIsTransparent() {
        let grid = PixelGrid(size: .s16)
        XCTAssertEqual(grid.pixel(x: 0, y: 0), .transparent)
        XCTAssertEqual(grid.pixel(x: 15, y: 15), .transparent)
    }

    func testSetAndGetPixel() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 5, y: 7, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        XCTAssertEqual(grid.pixel(x: 5, y: 7), RGBA(r: 255, g: 0, b: 0, a: 255))
        XCTAssertEqual(grid.pixel(x: 5, y: 8), .transparent)
    }

    func testOutOfBoundsIsNoOp() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: -1, y: 0, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        grid.setPixel(x: 16, y: 0, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        XCTAssertTrue(grid.data.allSatisfy { $0 == 0 })
    }

    func testContainsReturnsFalseOutside() {
        let grid = PixelGrid(size: .s16)
        XCTAssertFalse(grid.contains(x: -1, y: 0))
        XCTAssertFalse(grid.contains(x: 0, y: 16))
        XCTAssertTrue(grid.contains(x: 15, y: 15))
    }

    func testRoundTripData() {
        var grid = PixelGrid(size: .s32)
        grid.setPixel(x: 10, y: 20, color: RGBA(r: 1, g: 2, b: 3, a: 4))
        let grid2 = PixelGrid(data: grid.data, size: .s32)
        XCTAssertEqual(grid2.pixel(x: 10, y: 20), RGBA(r: 1, g: 2, b: 3, a: 4))
    }

    func testSlicedDataIsNormalized() {
        var source = PixelGrid(size: .s16)
        source.setPixel(x: 0, y: 0, color: RGBA(r: 1, g: 2, b: 3, a: 4))
        // Surround source data with padding bytes, then slice exactly byteCount out.
        var padded = Data(repeating: 0xFF, count: 8)
        padded.append(source.data)
        padded.append(Data(repeating: 0xFF, count: 8))
        let slice = padded[8 ..< (8 + CanvasSize.s16.byteCount)]
        let grid = PixelGrid(data: slice, size: .s16)
        XCTAssertEqual(grid.pixel(x: 0, y: 0), RGBA(r: 1, g: 2, b: 3, a: 4))
    }
}
