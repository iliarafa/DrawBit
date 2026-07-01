import XCTest
@testable import DrawBit

@MainActor
final class EditorStateTimelapseTests: XCTestCase {
    private func makeState() -> EditorState {
        let size = CanvasSize(width: 16, height: 16)
        let layer = Layer(name: "L1", pixels: Data(count: size.byteCount))
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        return EditorState(pieceID: UUID(), size: size, frames: [frame],
                           activeFrameIndex: 0, fps: 12)
    }

    private func drawOneDot(_ s: EditorState, at p: (Int, Int)) {
        s.beginStrokeSnapshot()
        s.stampBrush(.pencil, at: p)
        s.commitStroke()
    }

    func testCommitStrokeRecordsAKeyframe() {
        let s = makeState()
        s.color = RGBA(r: 255, g: 0, b: 0, a: 255)
        XCTAssertEqual(s.timelapseFrameCount, 0)
        drawOneDot(s, at: (1, 1))
        XCTAssertEqual(s.timelapseFrameCount, 1)
        drawOneDot(s, at: (2, 2))
        XCTAssertEqual(s.timelapseFrameCount, 2)
    }

    func testNoOpCommitIsDeduped() {
        let s = makeState()
        s.color = RGBA(r: 255, g: 0, b: 0, a: 255)
        drawOneDot(s, at: (1, 1))
        // Commit again with no pixel change (snapshot then immediately commit).
        s.beginStrokeSnapshot(); s.commitStroke()
        XCTAssertEqual(s.timelapseFrameCount, 1, "identical canvas is not re-recorded")
    }

    func testUndoDoesNotRecordButFinalizeDoes() {
        let s = makeState()
        s.color = RGBA(r: 255, g: 0, b: 0, a: 255)
        drawOneDot(s, at: (1, 1))
        drawOneDot(s, at: (2, 2))
        XCTAssertEqual(s.timelapseFrameCount, 2)
        s.undo()
        XCTAssertEqual(s.timelapseFrameCount, 2, "undo alone does not record")
        s.recordKeyframe()   // finalize on close/share
        XCTAssertEqual(s.timelapseFrameCount, 3, "post-undo canvas differs → recorded")
    }

    func testEncodeLoadRoundTrip() {
        let s = makeState()
        s.color = RGBA(r: 9, g: 9, b: 9, a: 255)
        drawOneDot(s, at: (3, 3))
        let blob = s.encodedTimelapse()
        XCTAssertNotNil(blob)

        let s2 = makeState()
        s2.loadTimelapse(blob)
        XCTAssertEqual(s2.timelapseFrameCount, 1)
        XCTAssertNil(makeState().encodedTimelapse(), "empty recording encodes to nil")
    }
}
