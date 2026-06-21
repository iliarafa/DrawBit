import XCTest
@testable import DrawBit

/// Pins the sprite-sheet grid math now that it's a shared helper (`SpriteSheetExporter.grid`)
/// used by BOTH the exporter and the export-sheet preview — they must agree on layout, so the
/// preview shows exactly what gets written. Formula (after Piskel, square canvas):
/// `columns = clamp(round(sqrt(N)), 1, N)`, `rows = ceil(N / columns)`.
final class SpriteSheetLayoutTests: XCTestCase {

    func testGridForRepresentativeCounts() {
        XCTAssertEqual(tuple(SpriteSheetExporter.grid(count: 1)), [1, 1])
        XCTAssertEqual(tuple(SpriteSheetExporter.grid(count: 2)), [1, 2])
        XCTAssertEqual(tuple(SpriteSheetExporter.grid(count: 3)), [2, 2])
        XCTAssertEqual(tuple(SpriteSheetExporter.grid(count: 4)), [2, 2])
        XCTAssertEqual(tuple(SpriteSheetExporter.grid(count: 5)), [2, 3])
        XCTAssertEqual(tuple(SpriteSheetExporter.grid(count: 9)), [3, 3])
        XCTAssertEqual(tuple(SpriteSheetExporter.grid(count: 16)), [4, 4])
    }

    func testGridAlwaysHoldsAllFrames() {
        for n in 1...64 {
            let g = SpriteSheetExporter.grid(count: n)
            XCTAssertGreaterThanOrEqual(g.columns * g.rows, n, "count \(n): grid too small")
            XCTAssertGreaterThanOrEqual(g.columns, 1)
            XCTAssertGreaterThanOrEqual(g.rows, 1)
        }
    }

    private func tuple(_ g: (columns: Int, rows: Int)) -> [Int] { [g.columns, g.rows] }
}
