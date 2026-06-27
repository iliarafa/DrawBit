import XCTest
import CoreGraphics
@testable import DrawBit

/// Unit tests for the custom layer drag-reorder math (`LayerDragMath.swift`).
///
/// `draggedDisplayIndex` turns a vertical drag (points) into the display slot the row should
/// land in; `rowGapShift` is the per-row offset that opens the gap as the dragged row passes.
/// Both work purely in *display* coordinates — the LayersPanel translates the final slot to the
/// model index via the already-tested `performMove`/`Frame.move` path, so these tests only pin
/// the gesture-space math.
final class LayerDragMathTests: XCTestCase {
    private let H: CGFloat = 56   // LayerRow.rowHeight

    // MARK: - draggedDisplayIndex

    func testZeroDragStaysPut() {
        XCTAssertEqual(draggedDisplayIndex(start: 2, translation: 0, rowHeight: H, count: 5), 2)
    }

    func testDownOneRow() {
        XCTAssertEqual(draggedDisplayIndex(start: 1, translation: H, rowHeight: H, count: 5), 2)
    }

    func testUpTwoRows() {
        XCTAssertEqual(draggedDisplayIndex(start: 3, translation: -2 * H, rowHeight: H, count: 5), 1)
    }

    /// Less than half a row of travel rounds to no move (so a jittery hold doesn't reorder).
    func testSubHalfRowRoundsToNoMove() {
        XCTAssertEqual(draggedDisplayIndex(start: 2, translation: 0.4 * H, rowHeight: H, count: 5), 2)
    }

    /// Just past half a row rounds to a one-slot move.
    func testJustPastHalfRowMovesOne() {
        XCTAssertEqual(draggedDisplayIndex(start: 2, translation: 0.6 * H, rowHeight: H, count: 5), 3)
    }

    func testClampsAtBottom() {
        XCTAssertEqual(draggedDisplayIndex(start: 3, translation: 10 * H, rowHeight: H, count: 5), 4)
    }

    func testClampsAtTop() {
        XCTAssertEqual(draggedDisplayIndex(start: 1, translation: -10 * H, rowHeight: H, count: 5), 0)
    }

    func testZeroRowHeightIsSafe() {
        XCTAssertEqual(draggedDisplayIndex(start: 2, translation: 100, rowHeight: 0, count: 5), 2)
    }

    // MARK: - rowGapShift

    /// The dragged row itself never gets a gap shift (it follows the finger directly).
    func testDraggedRowHasNoGapShift() {
        XCTAssertEqual(rowGapShift(displayIndex: 1, start: 1, target: 3, rowHeight: H), 0)
    }

    /// Moving down (start 1 → target 3): rows 2 and 3 slide UP to fill the vacated slot.
    func testMovingDownSlidesInterveningRowsUp() {
        XCTAssertEqual(rowGapShift(displayIndex: 2, start: 1, target: 3, rowHeight: H), -H)
        XCTAssertEqual(rowGapShift(displayIndex: 3, start: 1, target: 3, rowHeight: H), -H)
        XCTAssertEqual(rowGapShift(displayIndex: 4, start: 1, target: 3, rowHeight: H), 0)   // outside range
        XCTAssertEqual(rowGapShift(displayIndex: 0, start: 1, target: 3, rowHeight: H), 0)   // above, unaffected
    }

    /// Moving up (start 3 → target 1): rows 1 and 2 slide DOWN to open the gap.
    func testMovingUpSlidesInterveningRowsDown() {
        XCTAssertEqual(rowGapShift(displayIndex: 1, start: 3, target: 1, rowHeight: H), H)
        XCTAssertEqual(rowGapShift(displayIndex: 2, start: 3, target: 1, rowHeight: H), H)
        XCTAssertEqual(rowGapShift(displayIndex: 3, start: 3, target: 1, rowHeight: H), 0)   // the dragged row
        XCTAssertEqual(rowGapShift(displayIndex: 0, start: 3, target: 1, rowHeight: H), 0)   // above target
    }

    /// No move (target == start): nobody shifts.
    func testNoMoveNoShift() {
        for i in 0..<5 {
            XCTAssertEqual(rowGapShift(displayIndex: i, start: 2, target: 2, rowHeight: H), 0)
        }
    }
}
