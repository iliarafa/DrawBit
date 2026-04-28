import XCTest
@testable import DrawBit

final class EyedropperTests: XCTestCase {
    func testPicksOpaqueColor() {
        var grid = PixelGrid(size: .s16)
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        grid.setPixel(x: 4, y: 4, color: red)
        XCTAssertEqual(Eyedropper.pick(from: grid, at: (4, 4)), red)
    }

    func testTransparentSampleReturnsNil() {
        let grid = PixelGrid(size: .s16)
        XCTAssertNil(Eyedropper.pick(from: grid, at: (0, 0)))
    }

    func testOutOfBoundsReturnsNil() {
        let grid = PixelGrid(size: .s16)
        XCTAssertNil(Eyedropper.pick(from: grid, at: (-1, 0)))
        XCTAssertNil(Eyedropper.pick(from: grid, at: (0, 16)))
    }
}
