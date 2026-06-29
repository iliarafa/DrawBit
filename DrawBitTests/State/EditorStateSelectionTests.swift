import XCTest
@testable import DrawBit

final class EditorStateSelectionTests: XCTestCase {
    private let red   = RGBA(r: 255, g: 0, b: 0, a: 255)
    private let green = RGBA(r: 0, g: 255, b: 0, a: 255)

    private func makeState(size: CanvasSize = .s16) -> EditorState {
        let piece = Piece(size: size)
        let frame = FrameCodec.wrapV1Data(Data(count: size.byteCount), defaultName: "Layer 1")
        return EditorState(piece: piece, frames: [frame], activeFrameIndex: 0, fps: 12)
    }

    /// Convenience: write a pixel into the active layer without recording an undo entry.
    private func setPixel(_ state: EditorState, x: Int, y: Int, color: RGBA) {
        var grid = state.activeLayerPixelGrid
        grid.setPixel(x: x, y: y, color: color)
        state.setActiveLayerPixels(grid.data)
    }

    private func pixel(_ state: EditorState, x: Int, y: Int) -> RGBA {
        state.activeLayerPixelGrid.pixel(x: x, y: y)
    }

    private func paintedPiece() -> EditorState {
        let state = makeState()
        setPixel(state, x: 4, y: 4, color: red)
        setPixel(state, x: 5, y: 4, color: red)
        setPixel(state, x: 4, y: 5, color: red)
        setPixel(state, x: 5, y: 5, color: red)
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
        XCTAssertEqual(pixel(state, x: 4, y: 4), .transparent)
        XCTAssertEqual(pixel(state, x: 5, y: 5), .transparent)
        // Pending rect cleared.
        XCTAssertNil(state.pendingMarqueeRect)
        // Snapshot retained for the eventual commit (no commitStroke yet).
        XCTAssertFalse(state.canUndo)
    }

    func testEndMarqueeDefineEmptyRegionCancels() {
        let state = makeState() // empty canvas
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
        XCTAssertEqual(pixel(state, x: 7, y: 4), red)
        XCTAssertEqual(pixel(state, x: 4, y: 4), .transparent)
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
        XCTAssertEqual(pixel(state, x: 4, y: 4), red)
        XCTAssertEqual(pixel(state, x: 5, y: 5), red)
        XCTAssertEqual(pixel(state, x: 10, y: 4), .transparent)
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
        XCTAssertEqual(pixel(state, x: 4, y: 4), .transparent) // cut
        state.cancelMarquee()
        XCTAssertNil(state.selection)
        XCTAssertEqual(pixel(state, x: 4, y: 4), red) // restored
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
        XCTAssertEqual(pixel(state, x: 7, y: 4), red)
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
        XCTAssertEqual(pixel(state, x: 4, y: 4), red)
        XCTAssertEqual(pixel(state, x: 7, y: 4), .transparent)
    }

    func testRedoAutoCommitsFloatingSelectionFirst() {
        let state = paintedPiece()
        state.beginStrokeSnapshot()
        setPixel(state, x: 0, y: 0, color: green)
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

    // MARK: - Flip

    func testFlipHorizontalMirrorsFloatingSelectionInPlace() {
        let state = makeState()
        setPixel(state, x: 4, y: 4, color: red)    // left cell of a 2-wide selection
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 4))
        state.endMarqueeDefine()                   // bounds (4,4) 2×1, red at local (0,0)

        state.flipSelectionHorizontal()

        XCTAssertEqual(state.selection?.extracted.pixels.pixel(x: 5, y: 4), red)         // (0,0)->(1,0)
        XCTAssertEqual(state.selection?.extracted.pixels.pixel(x: 4, y: 4), .transparent)
        XCTAssertFalse(state.canUndo)              // no commit yet — rides the eventual commit

        state.commitMarquee()
        XCTAssertEqual(pixel(state, x: 5, y: 4), red)         // flipped in place, committed
        XCTAssertEqual(pixel(state, x: 4, y: 4), .transparent)
    }

    // MARK: - Rotate

    func testRotateSwapsBoundsAndResetsOffset() {
        let state = makeState()
        setPixel(state, x: 5, y: 4, color: red)
        setPixel(state, x: 5, y: 5, color: red)
        setPixel(state, x: 5, y: 6, color: red)    // vertical 1×3 bar
        state.beginMarqueeDefine(at: (5, 4))
        state.updateMarqueeDefine(to: (5, 6))
        state.endMarqueeDefine()                   // bounds (5,4) 1×3

        XCTAssertTrue(state.rotateSelection())
        XCTAssertEqual(state.selection?.extracted.originalBounds.width, 3)
        XCTAssertEqual(state.selection?.extracted.originalBounds.height, 1)
        XCTAssertEqual(state.selection?.dragOffset.dx, 0)
        XCTAssertEqual(state.selection?.dragOffset.dy, 0)
    }

    func testRotateRefusedOnNonSquareLeavesSelectionUnchanged() {
        let state = makeState(size: CanvasSize(width: 16, height: 8))
        for x in 0..<10 { setPixel(state, x: x, y: 0, color: red) }   // 10-wide horizontal run
        state.beginMarqueeDefine(at: (0, 0))
        state.updateMarqueeDefine(to: (9, 2))
        state.endMarqueeDefine()                   // bounds (0,0) 10×3 → rotated 3×10 can't fit h=8
        let before = state.selection

        XCTAssertFalse(state.rotateSelection())
        XCTAssertEqual(state.selection, before)    // untouched
    }

    // MARK: - Duplicate

    func testDuplicateStampsCopyAtCurrentOffsetAndKeepsFloating() {
        let state = paintedPiece()                 // red 2×2 at (4,4)
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 5))
        state.endMarqueeDefine()
        state.beginMarqueeDrag(at: (4, 4))
        state.updateMarqueeDrag(to: (8, 4))        // offset (4,0): float at (8,4)
        state.endMarqueeDrag()

        state.duplicateSelection()

        XCTAssertEqual(pixel(state, x: 8, y: 4), red)        // copy stamped at the float position
        XCTAssertEqual(pixel(state, x: 9, y: 5), red)
        XCTAssertNotNil(state.selection)                     // still floating
        XCTAssertTrue(state.canUndo)                         // one undo step
        XCTAssertEqual(pixel(state, x: 4, y: 4), .transparent) // origin stayed a hole

        // Move the still-floating copy and commit → a SECOND copy; the first remains.
        state.beginMarqueeDrag(at: (8, 4))
        state.updateMarqueeDrag(to: (12, 4))
        state.endMarqueeDrag()
        state.commitMarquee()
        XCTAssertEqual(pixel(state, x: 12, y: 4), red)
        XCTAssertEqual(pixel(state, x: 8, y: 4), red)
    }

    // MARK: - Delete

    func testDeleteLeavesHoleAndUndoRestores() {
        let state = paintedPiece()
        state.beginMarqueeDefine(at: (4, 4))
        state.updateMarqueeDefine(to: (5, 5))
        state.endMarqueeDefine()
        XCTAssertEqual(pixel(state, x: 4, y: 4), .transparent)   // cut on define

        state.deleteSelection()
        XCTAssertNil(state.selection)
        XCTAssertEqual(pixel(state, x: 4, y: 4), .transparent)   // hole stays
        XCTAssertTrue(state.canUndo)

        state.undo()
        XCTAssertEqual(pixel(state, x: 4, y: 4), red)            // restored in one step
        XCTAssertEqual(pixel(state, x: 5, y: 5), red)
    }

    func testDeleteNoOpWhenNoSelection() {
        let state = paintedPiece()
        state.deleteSelection()
        XCTAssertFalse(state.canUndo)
    }
}
