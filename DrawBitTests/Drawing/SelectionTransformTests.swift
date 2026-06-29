import XCTest
@testable import DrawBit

final class SelectionTransformTests: XCTestCase {
    private let red  = RGBA(r: 255, g: 0, b: 0, a: 255)
    private let blue = RGBA(r: 0, g: 0, b: 255, a: 255)

    /// Build a selection directly from a canvas-sized grid + bounds (mirrors what
    /// `Marquee.extractAndCut` produces, but lets each test place pixels precisely).
    private func selection(bounds: PixelRect, _ paint: (inout PixelGrid) -> Void,
                           size: CanvasSize = .s16) -> ExtractedSelection {
        var grid = PixelGrid(size: size)
        paint(&grid)
        return ExtractedSelection(originalBounds: bounds, pixels: grid)
    }

    // MARK: - Flip horizontal

    func testFlipHorizontalMirrorsColumnsWithinBounds() {
        // bounds (4,4) 3×2: red at local (0,0)=(4,4), blue at local (2,1)=(6,5).
        let sel = selection(bounds: PixelRect(x: 4, y: 4, width: 3, height: 2)) { g in
            g.setPixel(x: 4, y: 4, color: red)
            g.setPixel(x: 6, y: 5, color: blue)
        }
        let out = SelectionTransform.flipHorizontal(sel)

        XCTAssertEqual(out.originalBounds, sel.originalBounds)       // bounds unchanged
        XCTAssertEqual(out.pixels.pixel(x: 6, y: 4), red)           // (0,0) -> (2,0)
        XCTAssertEqual(out.pixels.pixel(x: 4, y: 5), blue)          // (2,1) -> (0,1)
        XCTAssertEqual(out.pixels.pixel(x: 4, y: 4), .transparent)  // source vacated
    }

    func testFlipHorizontalTwiceIsIdentity() {
        let sel = selection(bounds: PixelRect(x: 2, y: 7, width: 4, height: 3)) { g in
            g.setPixel(x: 2, y: 7, color: red)
            g.setPixel(x: 5, y: 9, color: blue)
        }
        XCTAssertEqual(SelectionTransform.flipHorizontal(SelectionTransform.flipHorizontal(sel)), sel)
    }

    // MARK: - Flip vertical

    func testFlipVerticalMirrorsRowsWithinBounds() {
        // bounds (4,4) 2×3: red at local (0,0)=(4,4), blue at local (1,2)=(5,6).
        let sel = selection(bounds: PixelRect(x: 4, y: 4, width: 2, height: 3)) { g in
            g.setPixel(x: 4, y: 4, color: red)
            g.setPixel(x: 5, y: 6, color: blue)
        }
        let out = SelectionTransform.flipVertical(sel)

        XCTAssertEqual(out.originalBounds, sel.originalBounds)       // bounds unchanged
        XCTAssertEqual(out.pixels.pixel(x: 4, y: 6), red)           // (0,0) -> (0,2)
        XCTAssertEqual(out.pixels.pixel(x: 5, y: 4), blue)          // (1,2) -> (1,0)
        XCTAssertEqual(out.pixels.pixel(x: 4, y: 4), .transparent)  // source vacated
    }

    func testFlipVerticalTwiceIsIdentity() {
        let sel = selection(bounds: PixelRect(x: 6, y: 1, width: 3, height: 4)) { g in
            g.setPixel(x: 6, y: 1, color: red)
            g.setPixel(x: 8, y: 4, color: blue)
        }
        XCTAssertEqual(SelectionTransform.flipVertical(SelectionTransform.flipVertical(sel)), sel)
    }

    // MARK: - Rotate 90° clockwise

    func testRotate90SwapsWidthAndHeight() {
        // 2 wide × 3 tall -> 3 wide × 2 tall.
        let sel = selection(bounds: PixelRect(x: 5, y: 4, width: 2, height: 3)) { g in
            g.setPixel(x: 5, y: 4, color: red)
        }
        let out = SelectionTransform.rotate90(sel, around: (x: 6, y: 6))
        XCTAssertEqual(out?.originalBounds.width, 3)
        XCTAssertEqual(out?.originalBounds.height, 2)
    }

    func testRotate90PlacesTopLeftAtTopRightClockwise() {
        // Source 2×3 with red at the top-left local cell. A clockwise turn moves the
        // top-left cell to the top-right of the new (3×2) block.
        let sel = selection(bounds: PixelRect(x: 5, y: 4, width: 2, height: 3)) { g in
            g.setPixel(x: 5, y: 4, color: red)   // local (0,0)
        }
        let out = SelectionTransform.rotate90(sel, around: (x: 6, y: 6))!
        let nb = out.originalBounds
        // dest local (w'-1, 0) = top-right corner of the rotated block.
        XCTAssertEqual(out.pixels.pixel(x: nb.x + nb.width - 1, y: nb.y), red)
    }

    func testRotate90RefusesWhenRotatedSelectionCannotFitCanvas() {
        // 16×8 canvas, a 10-wide × 3-tall selection. Rotated it would be 3×10, but 10 > 8,
        // so it can't fit — refuse (nil) rather than clip and lose pixels.
        let sel = selection(bounds: PixelRect(x: 0, y: 0, width: 10, height: 3),
                            { g in g.setPixel(x: 0, y: 0, color: red) },
                            size: CanvasSize(width: 16, height: 8))
        XCTAssertNil(SelectionTransform.rotate90(sel, around: (x: 5, y: 1)))
    }

    func testRotate90FitsOnSquareCanvasForAnyContainedSelection() {
        // On a square canvas any selection that fits also fits rotated, so it never refuses.
        let sel = selection(bounds: PixelRect(x: 0, y: 0, width: 16, height: 10)) { g in
            g.setPixel(x: 0, y: 0, color: red)
        }
        XCTAssertNotNil(SelectionTransform.rotate90(sel, around: (x: 8, y: 5)))
    }
}
