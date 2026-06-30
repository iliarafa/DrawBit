import XCTest
@testable import DrawBit

/// Per-tool brush size + cycle-on-tap behavior on `EditorState`.
final class EditorStateBrushTests: XCTestCase {
    private let red = RGBA(r: 255, g: 0, b: 0, a: 255)

    private func makeState(size: CanvasSize = .s16) -> EditorState {
        let piece = Piece(size: size)
        let frame = FrameCodec.wrapV1Data(Data(count: size.byteCount), defaultName: "Layer 1")
        return EditorState(piece: piece, frames: [frame], activeFrameIndex: 0, fps: 12)
    }

    private func setPixel(_ s: EditorState, _ x: Int, _ y: Int, _ c: RGBA) {
        var g = s.activeLayerPixelGrid
        g.setPixel(x: x, y: y, color: c)
        s.setActiveLayerPixels(g.data)
    }
    private func pixel(_ s: EditorState, _ x: Int, _ y: Int) -> RGBA {
        s.activeLayerPixelGrid.pixel(x: x, y: y)
    }

    func testDefaultSizeIsOne() {
        let s = makeState()
        XCTAssertEqual(s.pencilSize, 1)
        XCTAssertEqual(s.eraserSize, 1)
        XCTAssertEqual(s.brushSize(for: .pencil), 1)
        XCTAssertEqual(s.brushSize(for: .fill), 1)   // non-sizable tool
    }

    func testCycleWraps() {
        let s = makeState()
        for expected in [2, 3, 4, 1, 2] {
            s.cycleBrushSize(for: .pencil)
            XCTAssertEqual(s.pencilSize, expected)
        }
    }

    func testPencilAndEraserIndependent() {
        let s = makeState()
        s.cycleBrushSize(for: .pencil)   // → 2
        s.cycleBrushSize(for: .pencil)   // → 3
        XCTAssertEqual(s.pencilSize, 3)
        XCTAssertEqual(s.eraserSize, 1)
    }

    func testCycleNoOpForOtherTools() {
        let s = makeState()
        s.cycleBrushSize(for: .fill)
        s.cycleBrushSize(for: .marquee)
        XCTAssertEqual(s.pencilSize, 1)
        XCTAssertEqual(s.eraserSize, 1)
    }
}
