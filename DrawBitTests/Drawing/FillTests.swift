import XCTest
@testable import DrawBit

final class FillTests: XCTestCase {
    func testFillEmptyCanvasFillsAll() {
        var grid = PixelGrid(size: .s16)
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        Fill.fill(on: &grid, at: (0, 0), with: red)
        for y in 0..<16 {
            for x in 0..<16 {
                XCTAssertEqual(grid.pixel(x: x, y: y), red, "(\(x),\(y))")
            }
        }
    }

    func testFillDoesNotCrossDifferentColor() {
        var grid = PixelGrid(size: .s16)
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
        for y in 0..<16 { grid.setPixel(x: 8, y: y, color: blue) }
        Fill.fill(on: &grid, at: (0, 0), with: red)
        XCTAssertEqual(grid.pixel(x: 0, y: 0), red)
        XCTAssertEqual(grid.pixel(x: 7, y: 7), red)
        XCTAssertEqual(grid.pixel(x: 8, y: 7), blue)
        XCTAssertEqual(grid.pixel(x: 9, y: 7), .transparent)
    }

    func testFillSameColorIsNoOp() {
        var grid = PixelGrid(size: .s16)
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        for y in 0..<16 { for x in 0..<16 { grid.setPixel(x: x, y: y, color: red) } }
        Fill.fill(on: &grid, at: (3, 3), with: red)
        XCTAssertEqual(grid.pixel(x: 3, y: 3), red)
    }

    func testFillCoversEntireTallCanvas() {
        // 8 wide × 16 tall: a width-bounded flood would stop at y=8, leaving the
        // bottom half unfilled. Fill must reach the true bottom row.
        var grid = PixelGrid(size: CanvasSize(width: 8, height: 16))
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        Fill.fill(on: &grid, at: (0, 0), with: red)
        XCTAssertEqual(grid.pixel(x: 0, y: 15), red)
        XCTAssertEqual(grid.pixel(x: 7, y: 15), red)
    }

    func testFillStartingOutOfBoundsIsNoOp() {
        var grid = PixelGrid(size: .s16)
        Fill.fill(on: &grid, at: (-1, -1), with: RGBA(r: 1, g: 2, b: 3, a: 255))
        XCTAssertTrue(grid.data.allSatisfy { $0 == 0 })
    }
}
