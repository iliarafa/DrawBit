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

    // MARK: - setActiveFrame tests

    func testSetActiveFrameUpdatesIndex() {
        let state = makeStateWithTwoFrames()
        state.setActiveFrame(index: 1)
        XCTAssertEqual(state.activeFrameIndex, 1)
    }

    func testSetActiveFrameAutoCommitsFloatingMarquee() {
        let state = makeStateWithTwoFrames()
        // Paint a pixel so extractAndCut finds opaque content and creates a floating selection.
        state.mutateActiveLayerPixels { data in data[0] = 255; data[3] = 255 }
        state.beginMarqueeDefine(at: (0, 0))
        state.updateMarqueeDefine(to: (4, 4))
        state.endMarqueeDefine()
        XCTAssertNotNil(state.selection, "Floating selection should exist")
        state.setActiveFrame(index: 1)
        XCTAssertNil(state.selection, "Frame switch must commit the floating selection")
    }

    func testSetActiveFrameCancelsPendingMarquee() {
        let state = makeStateWithTwoFrames()
        state.beginMarqueeDefine(at: (0, 0))
        state.updateMarqueeDefine(to: (4, 4))
        XCTAssertNotNil(state.pendingMarqueeRect)
        state.setActiveFrame(index: 1)
        XCTAssertNil(state.pendingMarqueeRect, "Frame switch must cancel pending marquee define")
    }

    func testSetActiveFrameOutOfRangeNoOps() {
        let state = makeStateWithTwoFrames()
        state.setActiveFrame(index: 5)
        XCTAssertEqual(state.activeFrameIndex, 0, "Out-of-range index must no-op")
    }

    func testSetActiveFrameSameIndexNoOpsForMarquee() {
        let state = makeStateWithTwoFrames()
        // Paint a pixel so extractAndCut finds opaque content and creates a floating selection.
        state.mutateActiveLayerPixels { data in data[0] = 255; data[3] = 255 }
        state.beginMarqueeDefine(at: (0, 0))
        state.updateMarqueeDefine(to: (4, 4))
        state.endMarqueeDefine()
        XCTAssertNotNil(state.selection)
        state.setActiveFrame(index: 0)  // already on frame 0
        XCTAssertNotNil(state.selection, "Setting active to current frame must not commit marquee")
    }

    func testSequenceStructuralUndoRestoresFrames() {
        let state = makeStateWithTwoFrames()
        state.beginSequenceSnapshot()
        FrameSequence.addFrameAfter(frameID: state.frames.last!.id, in: &state.frames)
        state.commitSequenceChange()
        XCTAssertEqual(state.frames.count, 3)
        state.undo()
        XCTAssertEqual(state.frames.count, 2)
    }

    func testSequenceStructuralRedoReplaysFrames() {
        let state = makeStateWithTwoFrames()
        state.beginSequenceSnapshot()
        FrameSequence.addFrameAfter(frameID: state.frames.last!.id, in: &state.frames)
        state.commitSequenceChange()
        state.undo()
        XCTAssertEqual(state.frames.count, 2)
        state.redo()
        XCTAssertEqual(state.frames.count, 3)
    }

    func testActiveFrameHasContentAfterFloatingSelectionCommit() {
        let state = makeStateWithTwoFrames()
        // Paint a non-zero byte into frame 0's active layer.
        state.mutateActiveLayerPixels { data in
            data[0] = 0xFF
            data[3] = 0xFF
        }
        // Lift it into a floating marquee selection.
        state.beginMarqueeDefine(at: (0, 0))
        state.updateMarqueeDefine(to: (1, 1))
        state.endMarqueeDefine()
        XCTAssertNotNil(state.selection, "Floating selection should exist after extract")
        // The layer pixels under the lifted area are zeroed while the selection floats.
        let beforeCommit = state.frames[state.activeFrameIndex].layers[0].pixels
        XCTAssertTrue(beforeCommit.allSatisfy { $0 == 0 },
                      "Floating selection lifts content out of the layer")
        // Commit the floating selection; pixels should reappear in the layer.
        state.commitFloatingSelectionIfAny()
        let afterCommit = state.frames[state.activeFrameIndex].layers[0].pixels
        XCTAssertTrue(afterCommit.contains(where: { $0 != 0 }),
                      "After commit, the layer should contain non-zero bytes again")
    }

    func testCancelSequenceChangeRestoresFrames() {
        let state = makeStateWithTwoFrames()
        state.beginSequenceSnapshot()
        FrameSequence.addFrameAfter(frameID: state.frames.last!.id, in: &state.frames)
        XCTAssertEqual(state.frames.count, 3)
        state.cancelSequenceChange()
        XCTAssertEqual(state.frames.count, 2, "Cancel must restore the pre-snapshot sequence")
    }

    private func makeStateWithTwoFrames() -> EditorState {
        let pixels = Data(count: CanvasSize.s32.byteCount)
        let layerID = UUID()
        let l = Layer(id: layerID, name: "L", pixels: pixels)
        let f1 = Frame(name: "F1", layers: [l], activeLayerID: l.id)
        let f2 = Frame(name: "F2", layers: [l], activeLayerID: l.id)
        return EditorState(pieceID: UUID(), size: .s32,
                           frames: [f1, f2], activeFrameIndex: 0, fps: 12)
    }

    // MARK: - Per-frame undo (regression: undo on a non-first frame)

    private func makeStateWithThreeFrames() -> EditorState {
        let pixels = Data(count: CanvasSize.s16.byteCount)
        // Cascade: every frame shares the same layer UUID but has a unique frame id.
        let l = Layer(id: UUID(), name: "L", pixels: pixels)
        let f1 = Frame(name: "F1", layers: [l], activeLayerID: l.id)
        let f2 = Frame(name: "F2", layers: [l], activeLayerID: l.id)
        let f3 = Frame(name: "F3", layers: [l], activeLayerID: l.id)
        return EditorState(pieceID: UUID(), size: .s16,
                           frames: [f1, f2, f3], activeFrameIndex: 0, fps: 12)
    }

    /// Drawing on frame 2 then undoing must revert frame 2 — not frame 0. Layer UUIDs
    /// are shared across frames (the cascade), so an undo entry keyed only by layer id
    /// resolves to frame 0 and corrupts the wrong frame. Regression for "undo on frame 5
    /// undoes frame 1 instead."
    func testUndoOnNonFirstFrameRevertsThatFrameOnly() {
        let state = makeStateWithThreeFrames()
        state.setActiveFrame(index: 2)
        let baseline = state.frames[0].layers[0].pixels   // all-transparent, shared baseline
        let offset = (5 * 16 + 5) * 4

        state.beginStrokeSnapshot()
        state.mutateActiveLayerPixels { data in
            data[offset] = 0; data[offset+1] = 255; data[offset+2] = 0; data[offset+3] = 255
        }
        state.commitStroke()

        XCTAssertEqual(state.frames[2].layers[0].pixels[offset+1], 255, "stroke painted on frame 2")
        XCTAssertEqual(state.frames[0].layers[0].pixels, baseline, "frame 0 untouched by the stroke")

        state.undo()

        XCTAssertEqual(state.frames[2].layers[0].pixels, baseline, "undo reverts frame 2")
        XCTAssertEqual(state.frames[0].layers[0].pixels, baseline, "undo must not corrupt frame 0")
        XCTAssertEqual(state.activeFrameIndex, 2, "active frame follows the undone change")

        state.redo()

        XCTAssertEqual(state.frames[2].layers[0].pixels[offset+1], 255, "redo repaints frame 2")
        XCTAssertEqual(state.frames[0].layers[0].pixels, baseline, "redo must not touch frame 0")
    }
}
