import XCTest
@testable import DrawBit

final class EditorStateTests: XCTestCase {

    private func makeState(size: CanvasSize = .s16) -> EditorState {
        let piece = Piece(size: size)
        let frame = FrameCodec.wrapV1Data(Data(count: size.byteCount), defaultName: "Layer 1")
        return EditorState(piece: piece, frame: frame)
    }

    func testInitialStateFromPiece() {
        let state = makeState(size: .s32)
        XCTAssertEqual(state.activeLayerPixelGrid.size, .s32)
        XCTAssertEqual(state.tool, .pencil)
        XCTAssertEqual(state.color, RGBA(r: 255, g: 255, b: 255, a: 255))
        XCTAssertFalse(state.canUndo)
        XCTAssertFalse(state.canRedo)
    }

    func testCommitStrokePushesUndo() {
        let state = makeState()
        state.beginStrokeSnapshot()
        state.mutateActiveLayerPixels { data in
            let offset = (1 * 16 + 1) * 4
            data[offset]     = 255
            data[offset + 1] = 0
            data[offset + 2] = 0
            data[offset + 3] = 255
        }
        state.commitStroke()
        XCTAssertTrue(state.canUndo)
        XCTAssertFalse(state.canRedo)
    }

    func testUndoRestoresPrevious() {
        let state = makeState()
        state.beginStrokeSnapshot()
        state.mutateActiveLayerPixels { data in
            let offset = (1 * 16 + 1) * 4
            data[offset] = 255; data[offset+1] = 0; data[offset+2] = 0; data[offset+3] = 255
        }
        state.commitStroke()
        state.undo()
        XCTAssertEqual(state.activeLayerPixelGrid.pixel(x: 1, y: 1), .transparent)
        XCTAssertTrue(state.canRedo)
    }

    func testRedoReapplies() {
        let state = makeState()
        state.beginStrokeSnapshot()
        state.mutateActiveLayerPixels { data in
            let offset = (1 * 16 + 1) * 4
            data[offset] = 255; data[offset+1] = 0; data[offset+2] = 0; data[offset+3] = 255
        }
        state.commitStroke()
        state.undo()
        state.redo()
        XCTAssertEqual(state.activeLayerPixelGrid.pixel(x: 1, y: 1), RGBA(r: 255, g: 0, b: 0, a: 255))
    }

    func testNewStrokeAfterUndoClearsRedoStack() {
        let state = makeState()
        state.beginStrokeSnapshot()
        state.mutateActiveLayerPixels { data in
            let offset = (1 * 16 + 1) * 4
            data[offset] = 255; data[offset+1] = 0; data[offset+2] = 0; data[offset+3] = 255
        }
        state.commitStroke()
        state.undo()
        state.beginStrokeSnapshot()
        state.mutateActiveLayerPixels { data in
            let offset = (5 * 16 + 5) * 4
            data[offset] = 0; data[offset+1] = 255; data[offset+2] = 0; data[offset+3] = 255
        }
        state.commitStroke()
        XCTAssertFalse(state.canRedo)
    }

    func testUndoStackCappedAt50() {
        let state = makeState()
        for i in 0..<60 {
            state.beginStrokeSnapshot()
            state.mutateActiveLayerPixels { data in
                let offset = (i % 16) * 4
                data[offset] = 1; data[offset+1] = 1; data[offset+2] = 1; data[offset+3] = 255
            }
            state.commitStroke()
        }
        for _ in 0..<50 { state.undo() }
        XCTAssertFalse(state.canUndo)
    }

    func testCancelInProgressStrokeDiscardsChanges() {
        let state = makeState()
        state.beginStrokeSnapshot()
        state.mutateActiveLayerPixels { data in
            let offset = (1 * 16 + 1) * 4
            data[offset] = 255; data[offset+1] = 0; data[offset+2] = 0; data[offset+3] = 255
        }
        state.cancelStroke()
        XCTAssertEqual(state.activeLayerPixelGrid.pixel(x: 1, y: 1), .transparent)
        XCTAssertFalse(state.canUndo)
    }
}
