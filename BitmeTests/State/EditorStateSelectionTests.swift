import XCTest
@testable import Bitme

final class EditorStateSelectionTests: XCTestCase {
    private let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    private let green = RGBA(r: 0, g: 255, b: 0, a: 255)

    private func paintedPiece() -> EditorState {
        let state = EditorState(piece: Piece(size: .s16))
        state.grid.setPixel(x: 4, y: 4, color: red)
        state.grid.setPixel(x: 5, y: 4, color: red)
        state.grid.setPixel(x: 4, y: 5, color: red)
        state.grid.setPixel(x: 5, y: 5, color: red)
        return state
    }

    // MARK: - Define

    func testBeginMarqueeDefineSetsPendingRectAndSnapshots() {
        let state = paintedPiece()
        state.beginMarqueeDefine(at: (4, 4))
        XCTAssertEqual(state.pendingMarqueeRect, PixelRect(x: 4, y: 4, width: 1, height: 1))
        XCTAssertNil(state.selection)
    }

    func testUpdateMarqueeDefineExpandsRect() {
        let state = paintedPiece()
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (6, 7))
        XCTAssertEqual(state.pendingMarqueeRect, PixelRect(x: 4, y: 4, width: 3, height: 4))
    }

    func testEndMarqueeDefineCutsAndCreatesSelection() {
        let state = paintedPiece()
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 5))
        state.endMarqueeDefine()

        XCTAssertNotNil(state.selection)
        XCTAssertEqual(state.selection?.extracted.originalBounds, PixelRect(x: 4, y: 4, width: 2, height: 2))
        // Source pixels were cut.
        XCTAssertEqual(state.grid.pixel(x: 4, y: 4), .transparent)
        XCTAssertEqual(state.grid.pixel(x: 5, y: 5), .transparent)
        // Pending rect cleared.
        XCTAssertNil(state.pendingMarqueeRect)
        // Snapshot retained for the eventual commit (no commitStroke yet).
        XCTAssertFalse(state.canUndo)
    }

    func testEndMarqueeDefineEmptyRegionCancels() {
        let state = EditorState(piece: Piece(size: .s16)) // empty canvas
        state.beginMarqueeDefine(at: (1, 1))
        state.updateMarqueeDefine(to: (3, 3))
        state.endMarqueeDefine()

        XCTAssertNil(state.selection)
        XCTAssertNil(state.pendingMarqueeRect)
        XCTAssertFalse(state.canUndo)
    }

    // MARK: - Drag

    func testDragUpdatesOffsetByDelta() {
        let state = paintedPiece()
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 5))
        state.endMarqueeDefine()

        state.beginMarqueeDrag(at: (4, 4))
        state.updateMarqueeDrag(to: (7, 6))
        XCTAssertEqual(state.selection?.dragOffset.dx, 3)
        XCTAssertEqual(state.selection?.dragOffset.dy, 2)
    }

    func testSecondDragAccumulatesOffset() {
        let state = paintedPiece()
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 5))
        state.endMarqueeDefine()

        state.beginMarqueeDrag(at: (4, 4))
        state.updateMarqueeDrag(to: (7, 4))
        state.endMarqueeDrag()
        // Second drag: starts inside the now-shifted bounds (4+3 .. 5+3) = (7..8).
        state.beginMarqueeDrag(at: (7, 4))
        state.updateMarqueeDrag(to: (9, 4))
        XCTAssertEqual(state.selection?.dragOffset.dx, 5)
        XCTAssertEqual(state.selection?.dragOffset.dy, 0)
    }

    // MARK: - Commit

    func testCommitMarqueeBlitsAtOffsetAndPushesOneUndo() {
        let state = paintedPiece()
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 5))
        state.endMarqueeDefine()
        state.beginMarqueeDrag(at: (4, 4))
        state.updateMarqueeDrag(to: (7, 4))
        state.endMarqueeDrag()
        state.commitMarquee()

        XCTAssertNil(state.selection)
        XCTAssertEqual(state.grid.pixel(x: 7, y: 4), red)
        XCTAssertEqual(state.grid.pixel(x: 4, y: 4), .transparent)
        XCTAssertTrue(state.canUndo)
    }

    func testUndoOfCommittedMarqueeRestoresPreSelectionGridInOneStep() {
        let state = paintedPiece()
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 5))
        state.endMarqueeDefine()
        state.beginMarqueeDrag(at: (4, 4))
        state.updateMarqueeDrag(to: (10, 4))
        state.endMarqueeDrag()
        state.commitMarquee()

        state.undo()
        XCTAssertEqual(state.grid.pixel(x: 4, y: 4), red)
        XCTAssertEqual(state.grid.pixel(x: 5, y: 5), red)
        XCTAssertEqual(state.grid.pixel(x: 10, y: 4), .transparent)
    }

    func testCommitNoOpWhenNoSelection() {
        let state = paintedPiece()
        state.commitMarquee()
        XCTAssertFalse(state.canUndo)
    }

    // MARK: - Cancel

    func testCancelMarqueeRestoresGridAndClearsSelection() {
        let state = paintedPiece()
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 5))
        state.endMarqueeDefine()
        XCTAssertEqual(state.grid.pixel(x: 4, y: 4), .transparent) // cut
        state.cancelMarquee()
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.grid.pixel(x: 4, y: 4), red) // restored
    }

    // MARK: - Auto-commit on tool / undo / redo

    func testSetToolAutoCommitsFloatingSelection() {
        let state = paintedPiece()
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 5))
        state.endMarqueeDefine()
        state.beginMarqueeDrag(at: (4, 4))
        state.updateMarqueeDrag(to: (7, 4))
        state.endMarqueeDrag()

        state.setTool(.pencil)
        XCTAssertEqual(state.tool, .pencil)
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.grid.pixel(x: 7, y: 4), red)
        XCTAssertTrue(state.canUndo)
    }

    func testUndoAutoCommitsFloatingSelectionFirst() {
        let state = paintedPiece()
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 5))
        state.endMarqueeDefine()
        state.beginMarqueeDrag(at: (4, 4))
        state.updateMarqueeDrag(to: (7, 4))
        state.endMarqueeDrag()

        // Undo while floating: commit first, then undo restores pre-selection state.
        state.undo()
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.grid.pixel(x: 4, y: 4), red)
        XCTAssertEqual(state.grid.pixel(x: 7, y: 4), .transparent)
    }

    func testRedoAutoCommitsFloatingSelectionFirst() {
        let state = paintedPiece()
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 0, y: 0, color: green)
        state.commitStroke()
        state.undo() // now redo is possible

        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 5))
        state.endMarqueeDefine()
        state.beginMarqueeDrag(at: (4, 4))
        state.updateMarqueeDrag(to: (7, 4))
        state.endMarqueeDrag()

        state.redo()
        XCTAssertNil(state.selection)
    }
}
