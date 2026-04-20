import XCTest
@testable import Bitme

final class PencilTests: XCTestCase {
    func testPaintSinglePixel() {
        var grid = PixelGrid(size: .s16)
        Pencil.paint(on: &grid, at: (5, 7), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        XCTAssertEqual(grid.pixel(x: 5, y: 7), RGBA(r: 255, g: 0, b: 0, a: 255))
    }

    func testPaintLineFillsEveryPixel() {
        var grid = PixelGrid(size: .s16)
        Pencil.paintLine(on: &grid, from: (0, 0), to: (3, 3), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        for i in 0...3 {
            XCTAssertEqual(grid.pixel(x: i, y: i), RGBA(r: 255, g: 0, b: 0, a: 255), "pixel (\(i),\(i))")
        }
    }

    func testPaintOutOfBoundsIsNoOp() {
        var grid = PixelGrid(size: .s16)
        Pencil.paint(on: &grid, at: (-1, 5), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        Pencil.paintLine(on: &grid, from: (-5, 0), to: (20, 0), color: RGBA(r: 0, g: 255, b: 0, a: 255))
        for x in 0..<16 {
            XCTAssertEqual(grid.pixel(x: x, y: 0), RGBA(r: 0, g: 255, b: 0, a: 255))
        }
    }
}
