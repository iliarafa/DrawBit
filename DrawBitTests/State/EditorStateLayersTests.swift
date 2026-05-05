import XCTest
@testable import DrawBit

final class EditorStateLayersTests: XCTestCase {
    private func newState() -> EditorState {
        let layer = Layer(name: "Layer 1", pixels: Data(count: CanvasSize.s32.byteCount))
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        return EditorState(pieceID: UUID(), size: .s32, frames: [frame], activeFrameIndex: 0, fps: 12)
    }

    func testActiveLayerPixelGridReflectsActiveLayer() {
        let state = newState()
        XCTAssertEqual(state.activeLayerPixelGrid.size, .s32)
        XCTAssertEqual(state.activeLayerPixelGrid.data.count, CanvasSize.s32.byteCount)
    }

    func testDrawStrokeUndoRestoresActiveLayerOnly() {
        let state = newState()
        let originalPixels = state.activeLayerPixelGrid.data

        state.beginStrokeSnapshot()
        state.mutateActiveLayerPixels { data in
            data[0] = 0xFF
        }
        state.commitStroke()

        XCTAssertEqual(state.activeLayerPixelGrid.data[0], 0xFF)
        state.undo()
        XCTAssertEqual(state.activeLayerPixelGrid.data, originalPixels)
    }

    func testStructuralUndoRestoresWholeFrame() {
        let state = newState()
        let originalFrame = state.frame

        state.beginStructuralSnapshot()
        state.frame.addLayer(name: "Layer 2")
        state.commitStructuralChange()

        XCTAssertEqual(state.frame.layers.count, 2)
        state.undo()
        XCTAssertEqual(state.frame, originalFrame)
    }
}
