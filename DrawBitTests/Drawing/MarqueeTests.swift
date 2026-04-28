import XCTest
@testable import DrawBit

final class MarqueeTests: XCTestCase {
    private let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    private let green = RGBA(r: 0, g: 255, b: 0, a: 255)
    private let blue = RGBA(r: 0, g: 0, b: 255, a: 255)

    // MARK: - extractAndCut

    func testExtractAndCutCopiesOpaqueAndClearsSource() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 4, y: 4, color: red)
        grid.setPixel(x: 5, y: 4, color: red)
        grid.setPixel(x: 4, y: 5, color: red)

        let rect = PixelRect(x: 4, y: 4, width: 2, height: 2)
        let sel = Marquee.extractAndCut(grid: &grid, rect: rect)

        XCTAssertNotNil(sel)
        XCTAssertEqual(sel?.originalBounds, rect)
        XCTAssertEqual(sel?.pixels.pixel(x: 4, y: 4), red)
        XCTAssertEqual(sel?.pixels.pixel(x: 5, y: 4), red)
        XCTAssertEqual(sel?.pixels.pixel(x: 4, y: 5), red)
        XCTAssertEqual(sel?.pixels.pixel(x: 5, y: 5), .transparent)

        XCTAssertEqual(grid.pixel(x: 4, y: 4), .transparent)
        XCTAssertEqual(grid.pixel(x: 5, y: 4), .transparent)
        XCTAssertEqual(grid.pixel(x: 4, y: 5), .transparent)
    }

    func testExtractAndCutLeavesPixelsOutsideRectUntouched() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 0, y: 0, color: blue)
        grid.setPixel(x: 10, y: 10, color: blue)
        grid.setPixel(x: 5, y: 5, color: red)

        let rect = PixelRect(x: 4, y: 4, width: 3, height: 3)
        _ = Marquee.extractAndCut(grid: &grid, rect: rect)

        XCTAssertEqual(grid.pixel(x: 0, y: 0), blue)
        XCTAssertEqual(grid.pixel(x: 10, y: 10), blue)
        XCTAssertEqual(grid.pixel(x: 5, y: 5), .transparent)
    }

    func testExtractAndCutIgnoresTransparentInsideRect() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 5, y: 5, color: red)
        // (4,4) and others in rect are transparent.

        let rect = PixelRect(x: 4, y: 4, width: 3, height: 3)
        let sel = Marquee.extractAndCut(grid: &grid, rect: rect)

        XCTAssertEqual(sel?.pixels.pixel(x: 4, y: 4), .transparent)
        XCTAssertEqual(sel?.pixels.pixel(x: 5, y: 5), red)
    }

    func testExtractAndCutEmptyRegionReturnsNil() {
        var grid = PixelGrid(size: .s16)
        let rect = PixelRect(x: 4, y: 4, width: 3, height: 3)
        let sel = Marquee.extractAndCut(grid: &grid, rect: rect)
        XCTAssertNil(sel)
        // grid untouched
        XCTAssertTrue(grid.data.allSatisfy { $0 == 0 })
    }

    // MARK: - commit

    func testCommitBlitsOpaquePixelsAtOffset() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 4, y: 4, color: red)
        let rect = PixelRect(x: 4, y: 4, width: 1, height: 1)
        let sel = Marquee.extractAndCut(grid: &grid, rect: rect)!

        Marquee.commit(into: &grid, selection: sel, offset: (dx: 3, dy: 2))

        XCTAssertEqual(grid.pixel(x: 4, y: 4), .transparent)
        XCTAssertEqual(grid.pixel(x: 7, y: 6), red)
    }

    func testCommitDoesNotEraseDestinationWhereSelectionIsTransparent() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 5, y: 5, color: red)
        // Now define selection rect that includes the red pixel + transparent neighbors.
        let rect = PixelRect(x: 5, y: 5, width: 2, height: 2)
        let sel = Marquee.extractAndCut(grid: &grid, rect: rect)!

        // Paint a destination canvas under the future drop area.
        for x in 0..<16 {
            for y in 0..<16 {
                grid.setPixel(x: x, y: y, color: green)
            }
        }

        Marquee.commit(into: &grid, selection: sel, offset: (dx: 3, dy: 0))

        // The opaque red lands at (8,5).
        XCTAssertEqual(grid.pixel(x: 8, y: 5), red)
        // The transparent cells of the selection should NOT erase the green underneath.
        XCTAssertEqual(grid.pixel(x: 9, y: 5), green)
        XCTAssertEqual(grid.pixel(x: 8, y: 6), green)
        XCTAssertEqual(grid.pixel(x: 9, y: 6), green)
    }

    func testCommitClipsOffCanvasPixels() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 1, y: 1, color: red)
        grid.setPixel(x: 2, y: 1, color: red)
        let rect = PixelRect(x: 1, y: 1, width: 2, height: 1)
        let sel = Marquee.extractAndCut(grid: &grid, rect: rect)!

        // Drag both pixels almost off the right edge: (1,1)→(15,1), (2,1)→(16,1) which is OOB.
        Marquee.commit(into: &grid, selection: sel, offset: (dx: 14, dy: 0))

        XCTAssertEqual(grid.pixel(x: 15, y: 1), red)
        // (16,1) is off-canvas, must be silently dropped.
        XCTAssertFalse(grid.contains(x: 16, y: 1))
    }

    func testRoundTripExtractCommitAtZeroOffsetIsIdentity() {
        var original = PixelGrid(size: .s16)
        original.setPixel(x: 3, y: 3, color: red)
        original.setPixel(x: 4, y: 3, color: red)
        original.setPixel(x: 3, y: 4, color: blue)
        var grid = original

        let rect = PixelRect(x: 3, y: 3, width: 2, height: 2)
        let sel = Marquee.extractAndCut(grid: &grid, rect: rect)!
        Marquee.commit(into: &grid, selection: sel, offset: (dx: 0, dy: 0))

        XCTAssertEqual(grid, original)
    }
}
