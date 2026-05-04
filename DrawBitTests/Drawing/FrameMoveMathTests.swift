import XCTest
@testable import DrawBit

/// Unit tests for `Frame.modelTargetIndex(displayedFrom:newOffset:count:)`.
///
/// The displayed list is the model layers reversed (display[0] = model.last).
/// SwiftUI's `.onMove` provides `newOffset` as a *pre-removal* insertion point
/// in the displayed array, per `Array.move(fromOffsets:toOffset:)` semantics.
/// `Frame.move(id:toIndex:)` expects a *post-removal* insertion point in the
/// model array.  The helper converts between the two coordinate spaces.
///
/// Expected values are hand-verified by simulating `Array.move` on the
/// displayed array and reversing the result.
final class FrameMoveMathTests: XCTestCase {

    // MARK: - 3-layer cases: model [A, B, C], display [C, B, A]

    /// Drag C (display 0) down by 1 — drop between B and A.
    /// Array.move([0], toOffset:2) on [C,B,A] → remove C → [B,A], insert at 1 → [B,C,A].
    /// Model (reversed) = [A,C,B]. Frame.move(C, toIndex:1) → [A,C,B]. ✓
    func testThreeLayer_dragTopDownOne() {
        XCTAssertEqual(Frame.modelTargetIndex(displayedFrom: 0, newOffset: 2, count: 3), 1)
    }

    /// Drag C (display 0) all the way to the bottom.
    /// Array.move([0], toOffset:3) → remove C → [B,A], insert at 2 → [B,A,C].
    /// Model = [C,A,B]. Frame.move(C, toIndex:0) → [C,A,B]. ✓
    func testThreeLayer_dragTopToBottom() {
        XCTAssertEqual(Frame.modelTargetIndex(displayedFrom: 0, newOffset: 3, count: 3), 0)
    }

    /// Drag A (display 2) all the way to the top.
    /// Array.move([2], toOffset:0) → remove A → [C,B], insert at 0 → [A,C,B].
    /// Model = [B,C,A]. Frame.move(A, toIndex:2) → [B,C,A]. ✓
    func testThreeLayer_dragBottomToTop() {
        XCTAssertEqual(Frame.modelTargetIndex(displayedFrom: 2, newOffset: 0, count: 3), 2)
    }

    /// Drag B (display 1) up by 1 — drop above C.
    /// Array.move([1], toOffset:0) → remove B → [C,A], insert at 0 → [B,C,A].
    /// Model = [A,C,B]. Frame.move(B, toIndex:2) produces [A,C,B]
    /// (remove B at index 1 → [A,C], insert at 2 → [A,C,B]). ✓
    func testThreeLayer_dragMiddleUpOne() {
        XCTAssertEqual(Frame.modelTargetIndex(displayedFrom: 1, newOffset: 0, count: 3), 2)
    }

    /// No-op: drag C (display 0) and release at original position (newOffset=0).
    /// Swift semantics: drop before index 0 with element already at 0 → no move.
    func testThreeLayer_noOpDrop() {
        XCTAssertNil(Frame.modelTargetIndex(displayedFrom: 0, newOffset: 0, count: 3))
    }

    // MARK: - 4-layer cases: model [A, B, C, D], display [D, C, B, A]

    /// Drag D (display 0) to mid-list — newOffset=2.
    /// Array.move([0], toOffset:2) → remove D → [C,B,A], insert at 1 → [C,D,B,A].
    /// Model = [A,B,D,C]. Frame.move(D, toIndex:2) → [A,B,D,C]. ✓
    func testFourLayer_dragTopToMidLow() {
        XCTAssertEqual(Frame.modelTargetIndex(displayedFrom: 0, newOffset: 2, count: 4), 2)
    }

    /// Drag D (display 0) down by 2 — newOffset=3.
    /// Array.move([0], toOffset:3) → remove D → [C,B,A], insert at 2 → [C,B,D,A].
    /// Model = [A,D,B,C]. Frame.move(D, toIndex:1) → [A,D,B,C]. ✓
    func testFourLayer_dragTopDownTwo() {
        XCTAssertEqual(Frame.modelTargetIndex(displayedFrom: 0, newOffset: 3, count: 4), 1)
    }

    /// Drag D (display 0) to the very bottom — newOffset=4.
    /// Array.move([0], toOffset:4) → remove D → [C,B,A], insert at 3 → [C,B,A,D].
    /// Model = [D,A,B,C]. Frame.move(D, toIndex:0) → [D,A,B,C]. ✓
    func testFourLayer_dragTopToBottom() {
        XCTAssertEqual(Frame.modelTargetIndex(displayedFrom: 0, newOffset: 4, count: 4), 0)
    }

    /// Drag A (display 3) to top — newOffset=0.
    /// Array.move([3], toOffset:0) → remove A → [D,C,B], insert at 0 → [A,D,C,B].
    /// Model = [B,C,D,A]. Frame.move(A, toIndex:3) → [B,C,D,A]. ✓
    func testFourLayer_dragBottomToTop() {
        XCTAssertEqual(Frame.modelTargetIndex(displayedFrom: 3, newOffset: 0, count: 4), 3)
    }

    // MARK: - 2-layer cases: model [A, B], display [B, A]

    /// Swap by dragging B (display 0) to the bottom — newOffset=2.
    /// Array.move([0], toOffset:2) → remove B → [A], insert at 1 → [A,B].
    /// Model = [B,A]. Frame.move(B, toIndex:0) → [B,A]. ✓
    func testTwoLayer_swapTopToBottom() {
        XCTAssertEqual(Frame.modelTargetIndex(displayedFrom: 0, newOffset: 2, count: 2), 0)
    }

    /// Swap by dragging A (display 1) to the top — newOffset=0.
    /// Array.move([1], toOffset:0) → remove A → [B], insert at 0 → [A,B].
    /// Model = [B,A]. Frame.move(A, toIndex:1) → [B,A]. ✓
    func testTwoLayer_swapBottomToTop() {
        XCTAssertEqual(Frame.modelTargetIndex(displayedFrom: 1, newOffset: 0, count: 2), 1)
    }
}
