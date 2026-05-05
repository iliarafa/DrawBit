import XCTest
@testable import DrawBit

final class EditorStateTests: XCTestCase {

    private func makeState(size: CanvasSize = .s16) -> EditorState {
        let piece = Piece(size: size)
        let frame = FrameCodec.wrapV1Data(Data(count: size.byteCount), defaultName: "Layer 1")
        return EditorState(piece: piece, frames: [frame], activeFrameIndex: 0, fps: 12)
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

    func testEditorStateFrameAccessorIsActiveFrame() {
        let pixels = Data(count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "Layer 1", pixels: pixels)
        let f1 = Frame(name: "Frame 1", layers: [layer], activeLayerID: layer.id)
        let state = EditorState(pieceID: UUID(), size: .s32,
                                frames: [f1], activeFrameIndex: 0, fps: 12)
        XCTAssertEqual(state.frame.id, f1.id)
        XCTAssertEqual(state.frames.count, 1)
        XCTAssertEqual(state.fps, 12)
    }

    func testEditorStateMutatingActiveFramePixelsAffectsFramesArray() {
        let pixels = Data(count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: pixels)
        let f = Frame(name: "F", layers: [layer], activeLayerID: layer.id)
        let state = EditorState(pieceID: UUID(), size: .s32,
                                frames: [f], activeFrameIndex: 0, fps: 12)
        state.mutateActiveLayerPixels { data in
            data[0] = 0xFF
        }
        XCTAssertEqual(state.frames[0].layers[0].pixels[0], 0xFF)
    }
}
