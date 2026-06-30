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

    // MARK: - fallback (reference image)

    private let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    private let blue = RGBA(r: 0, g: 0, b: 255, a: 255)

    func testFallbackUsedWhenPrimaryTransparent() {
        let primary = PixelGrid(size: .s16)                 // empty
        var fallback = PixelGrid(size: .s16)
        fallback.setPixel(x: 4, y: 4, color: blue)
        XCTAssertEqual(Eyedropper.pick(from: primary, fallback: fallback, at: (4, 4)), blue)
    }

    func testPrimaryWinsOverFallback() {
        var primary = PixelGrid(size: .s16)
        var fallback = PixelGrid(size: .s16)
        primary.setPixel(x: 4, y: 4, color: red)
        fallback.setPixel(x: 4, y: 4, color: blue)
        XCTAssertEqual(Eyedropper.pick(from: primary, fallback: fallback, at: (4, 4)), red)
    }

    func testBothEmptyReturnsNil() {
        let primary = PixelGrid(size: .s16)
        let fallback = PixelGrid(size: .s16)
        XCTAssertNil(Eyedropper.pick(from: primary, fallback: fallback, at: (4, 4)))
    }

    func testNilFallbackBehavesLikePlainPick() {
        let primary = PixelGrid(size: .s16)
        XCTAssertNil(Eyedropper.pick(from: primary, fallback: nil, at: (4, 4)))
    }
}
