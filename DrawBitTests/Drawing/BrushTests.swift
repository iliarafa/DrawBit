import XCTest
@testable import DrawBit

/// `Brush.squareCells` is the pure nib geometry behind multi-pixel pencil/eraser strokes.
/// Row-major order, odd sizes centered, even sizes biased down-right. No bounds clamping —
/// `PixelGrid.setPixel` drops out-of-canvas writes.
final class BrushTests: XCTestCase {
    /// Tuples aren't `Equatable` as array elements; compare via `[Int]` rows.
    private func rows(_ cells: [(Int, Int)]) -> [[Int]] { cells.map { [$0.0, $0.1] } }

    func testSize1IsSingleCell() {
        XCTAssertEqual(rows(Brush.squareCells(centeredAt: (5, 5), size: 1)), [[5, 5]])
    }

    func testSize2BiasesDownRight() {
        XCTAssertEqual(rows(Brush.squareCells(centeredAt: (5, 5), size: 2)),
                       [[5, 5], [6, 5], [5, 6], [6, 6]])
    }

    func testSize3CentersOnCursor() {
        XCTAssertEqual(rows(Brush.squareCells(centeredAt: (5, 5), size: 3)),
                       [[4, 4], [5, 4], [6, 4],
                        [4, 5], [5, 5], [6, 5],
                        [4, 6], [5, 6], [6, 6]])
    }

    func testSize4CountAndCorners() {
        let cells = rows(Brush.squareCells(centeredAt: (5, 5), size: 4))
        XCTAssertEqual(cells.count, 16)
        XCTAssertEqual(cells.first, [4, 4])   // origin = (5 - 1, 5 - 1)
        XCTAssertEqual(cells.last, [7, 7])    // origin + 3
    }

    func testCellsMayBeNegativeNoClamping() {
        XCTAssertEqual(rows(Brush.squareCells(centeredAt: (0, 0), size: 3)).first, [-1, -1])
    }

    func testSizeBelowOneTreatedAsOne() {
        XCTAssertEqual(rows(Brush.squareCells(centeredAt: (2, 2), size: 0)), [[2, 2]])
    }
}
