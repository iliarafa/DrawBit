import XCTest
@testable import DrawBit

final class EditorStateTests: XCTestCase {
    func testInitialStateFromPiece() {
        let piece = Piece(size: .s32)
        let state = EditorState(piece: piece)
        XCTAssertEqual(state.grid.size, .s32)
        XCTAssertEqual(state.tool, .pencil)
        XCTAssertEqual(state.color, RGBA(r: 255, g: 255, b: 255, a: 255))
        XCTAssertFalse(state.canUndo)
        XCTAssertFalse(state.canRedo)
    }

    func testCommitStrokePushesUndo() {
        let state = EditorState(piece: Piece(size: .s16))
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 1, y: 1, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        state.commitStroke()
        XCTAssertTrue(state.canUndo)
        XCTAssertFalse(state.canRedo)
    }

    func testUndoRestoresPrevious() {
        let state = EditorState(piece: Piece(size: .s16))
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 1, y: 1, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        state.commitStroke()
        state.undo()
        XCTAssertEqual(state.grid.pixel(x: 1, y: 1), .transparent)
        XCTAssertTrue(state.canRedo)
    }

    func testRedoReapplies() {
        let state = EditorState(piece: Piece(size: .s16))
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 1, y: 1, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        state.commitStroke()
        state.undo()
        state.redo()
        XCTAssertEqual(state.grid.pixel(x: 1, y: 1), RGBA(r: 255, g: 0, b: 0, a: 255))
    }

    func testNewStrokeAfterUndoClearsRedoStack() {
        let state = EditorState(piece: Piece(size: .s16))
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 1, y: 1, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        state.commitStroke()
        state.undo()
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 5, y: 5, color: RGBA(r: 0, g: 255, b: 0, a: 255))
        state.commitStroke()
        XCTAssertFalse(state.canRedo)
    }

    func testUndoStackCappedAt50() {
        let state = EditorState(piece: Piece(size: .s16))
        for i in 0..<60 {
            state.beginStrokeSnapshot()
            state.grid.setPixel(x: i % 16, y: 0, color: RGBA(r: 1, g: 1, b: 1, a: 255))
            state.commitStroke()
        }
        for _ in 0..<50 { state.undo() }
        XCTAssertFalse(state.canUndo)
    }

    func testCancelInProgressStrokeDiscardsChanges() {
        let state = EditorState(piece: Piece(size: .s16))
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 1, y: 1, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        state.cancelStroke()
        XCTAssertEqual(state.grid.pixel(x: 1, y: 1), .transparent)
        XCTAssertFalse(state.canUndo)
    }
}
