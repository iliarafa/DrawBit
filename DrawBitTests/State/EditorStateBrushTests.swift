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

    // MARK: - stampBrush

    func testStampSize1MatchesSinglePixel() {
        let s = makeState()
        s.color = red
        s.stampBrush(.pencil, at: (5, 5))
        XCTAssertEqual(pixel(s, 5, 5), red)
        XCTAssertEqual(pixel(s, 6, 5), .transparent)
        XCTAssertEqual(pixel(s, 5, 6), .transparent)
    }

    func testStampSize3PaintsNineCells() {
        let s = makeState()
        s.color = red
        s.pencilSize = 3
        s.stampBrush(.pencil, at: (5, 5))
        for y in 4...6 { for x in 4...6 { XCTAssertEqual(pixel(s, x, y), red, "(\(x),\(y))") } }
        XCTAssertEqual(pixel(s, 3, 5), .transparent)   // outside the nib
    }

    func testStampEraserClearsNib() {
        let s = makeState()
        for y in 4...6 { for x in 4...6 { setPixel(s, x, y, red) } }
        s.eraserSize = 3
        s.stampBrush(.eraser, at: (5, 5))
        for y in 4...6 { for x in 4...6 { XCTAssertEqual(pixel(s, x, y), .transparent) } }
    }

    func testStampMirrorsEachCell() {
        let s = makeState()                 // .s16 → width 16, so mirror x → 15 - x
        s.color = red
        s.pencilSize = 2
        s.isMirrorEnabled = true
        s.stampBrush(.pencil, at: (1, 1))   // cells (1,1)(2,1)(1,2)(2,2)
        XCTAssertEqual(pixel(s, 1, 1), red)
        XCTAssertEqual(pixel(s, 14, 1), red)   // 15 - 1
        XCTAssertEqual(pixel(s, 13, 2), red)   // 15 - 2
    }

    func testStrokeIsOneUndoStep() {
        let s = makeState()
        s.color = red
        s.pencilSize = 3
        s.beginStrokeSnapshot()
        s.stampBrush(.pencil, at: (5, 5))
        s.stampBrush(.pencil, at: (6, 5))
        s.commitStroke()
        XCTAssertEqual(pixel(s, 5, 5), red)            // painted before undo
        XCTAssertTrue(s.canUndo)
        s.undo()
        XCTAssertEqual(pixel(s, 5, 5), .transparent)   // one undo wipes the whole stroke
        XCTAssertFalse(s.canUndo)
    }
}
