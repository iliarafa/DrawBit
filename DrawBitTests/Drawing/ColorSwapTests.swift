import XCTest
@testable import DrawBit

final class ColorSwapTests: XCTestCase {
    private let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    private let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
    private let green = RGBA(r: 0, g: 255, b: 0, a: 255)

    func testSwapsAllPixelsOfTargetColor() {
        var grid = PixelGrid(size: .s16)
        for y in 0..<16 { for x in 0..<16 { grid.setPixel(x: x, y: y, color: red) } }
        grid.setPixel(x: 5, y: 5, color: blue)

        ColorSwap.swap(on: &grid, from: red, to: green)

        XCTAssertEqual(grid.pixel(x: 0, y: 0), green)
        XCTAssertEqual(grid.pixel(x: 5, y: 5), blue)
        XCTAssertEqual(grid.pixel(x: 15, y: 15), green)
    }

    func testSwapsAcrossDisconnectedRegions() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 1, y: 1, color: red)
        grid.setPixel(x: 14, y: 14, color: red)

        ColorSwap.swap(on: &grid, from: red, to: blue)

        XCTAssertEqual(grid.pixel(x: 1, y: 1), blue)
        XCTAssertEqual(grid.pixel(x: 14, y: 14), blue)
    }

    func testIgnoresOtherColors() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 0, y: 0, color: red)
        grid.setPixel(x: 1, y: 0, color: blue)

        ColorSwap.swap(on: &grid, from: red, to: green)

        XCTAssertEqual(grid.pixel(x: 0, y: 0), green)
        XCTAssertEqual(grid.pixel(x: 1, y: 0), blue)
    }

    func testSwapTransparentToOpaque() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 5, y: 5, color: red)

        ColorSwap.swap(on: &grid, from: .transparent, to: blue)

        XCTAssertEqual(grid.pixel(x: 5, y: 5), red)
        XCTAssertEqual(grid.pixel(x: 0, y: 0), blue)
        XCTAssertEqual(grid.pixel(x: 15, y: 15), blue)
    }

    func testSwapOpaqueToTransparentErases() {
        var grid = PixelGrid(size: .s16)
        for y in 0..<16 { for x in 0..<16 { grid.setPixel(x: x, y: y, color: red) } }

        ColorSwap.swap(on: &grid, from: red, to: .transparent)

        XCTAssertEqual(grid.pixel(x: 0, y: 0), .transparent)
        XCTAssertEqual(grid.pixel(x: 8, y: 8), .transparent)
    }

    func testSwapToSameColorIsNoOp() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 3, y: 3, color: red)
        let before = grid.data

        ColorSwap.swap(on: &grid, from: red, to: red)

        XCTAssertEqual(grid.data, before)
    }

    func testSwapAbsentColorIsNoOp() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 3, y: 3, color: red)
        let before = grid.data

        ColorSwap.swap(on: &grid, from: blue, to: green)

        XCTAssertEqual(grid.data, before)
    }
}
