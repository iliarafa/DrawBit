import XCTest
@testable import DrawBit

final class ExportSizeBudgetFilmTests: XCTestCase {
    func testFilmBoundedByContextEdgeNotByteCap() {
        // 120 frames that would blow the animated byte cap for GIF are fine for film
        // (the writer streams frame-by-frame — only the per-frame context is bounded).
        let over = ExportSizeBudget.isOverBudget(
            format: .film, canvasWidth: 256, canvasHeight: 256, scale: 8, frameCount: 120)
        XCTAssertFalse(over, "512px-ish film frames are within budget regardless of count")
    }

    func testFilmOverBudgetOnlyWhenEdgeTooLarge() {
        let over = ExportSizeBudget.isOverBudget(
            format: .film, canvasWidth: 256, canvasHeight: 256, scale: 40, frameCount: 10)
        XCTAssertTrue(over, "256*40 = 10240 > maxContextEdge → too big")
    }
}
