import XCTest
@testable import Bitme

final class EraserTests: XCTestCase {
    func testErasePointSetsAlphaZero() {
        var grid = PixelGrid(size: .s16)
        Pencil.paint(on: &grid, at: (5, 5), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        Eraser.erase(on: &grid, at: (5, 5))
        XCTAssertEqual(grid.pixel(x: 5, y: 5), .transparent)
    }

    func testEraseLineClearsEveryPixel() {
        var grid = PixelGrid(size: .s16)
        Pencil.paintLine(on: &grid, from: (0, 0), to: (4, 0), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        Eraser.eraseLine(on: &grid, from: (0, 0), to: (4, 0))
        for x in 0...4 {
            XCTAssertEqual(grid.pixel(x: x, y: 0), .transparent)
        }
    }
}
