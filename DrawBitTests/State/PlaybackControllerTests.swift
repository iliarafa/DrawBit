import XCTest
@testable import DrawBit

@MainActor
final class PlaybackControllerTests: XCTestCase {

    private func makeState(frameCount: Int = 2, fps: Int = 60) -> EditorState {
        let pixels = Data(count: CanvasSize.s32.byteCount)
        let layerID = UUID()
        var frames: [Frame] = []
        for i in 0..<frameCount {
            let l = Layer(id: layerID, name: "L", pixels: pixels)
            frames.append(Frame(name: "F\(i)", layers: [l], activeLayerID: l.id))
        }
        return EditorState(pieceID: UUID(), size: .s32,
                           frames: frames, activeFrameIndex: 0, fps: fps)
    }

    func testInitialIsPlayingFalse() {
        let state = makeState()
        XCTAssertFalse(state.isPlaying)
    }

    func testStartFlipsIsRunningAndIsPlaying() async {
        let state = makeState()
        let pb = PlaybackController(state: state)
        pb.start()
        XCTAssertTrue(pb.isRunning)
        XCTAssertTrue(state.isPlaying)
        pb.stop()
    }

    func testStopHaltsAdvanceAndClearsIsPlaying() {
        let state = makeState()
        let pb = PlaybackController(state: state)
        pb.start()
        pb.stop()
        XCTAssertFalse(pb.isRunning)
        XCTAssertFalse(state.isPlaying)
    }

    func testStartTwiceIsIdempotent() {
        let state = makeState()
        let pb = PlaybackController(state: state)
        pb.start()
        pb.start()      // second call should be a no-op while running
        XCTAssertTrue(pb.isRunning)
        pb.stop()
        XCTAssertFalse(pb.isRunning)
    }

    func testStopWhenNotRunningIsSafe() {
        let state = makeState()
        let pb = PlaybackController(state: state)
        pb.stop()
        XCTAssertFalse(pb.isRunning)
        XCTAssertFalse(state.isPlaying)
    }

    func testCannotStartWithSingleFrame() {
        let state = makeState(frameCount: 1)
        let pb = PlaybackController(state: state)
        pb.start()
        XCTAssertFalse(pb.isRunning, "single-frame piece should not be playable")
        XCTAssertFalse(state.isPlaying)
    }

    func testTimerAdvancesActiveFrame() async throws {
        // 10 frames @ 100 fps (10 ms/tick), sleep 50 ms ≈ 5 ticks. Starting at 0,
        // any tick count between 1 and 9 lands at a non-zero index. Wrap-back to
        // 0 would require exactly 10 ticks (100 ms), well beyond the sleep window
        // even with substantial timer jitter.
        let state = makeState(frameCount: 10, fps: 100)
        let pb = PlaybackController(state: state)
        pb.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        let observed = state.activeFrameIndex
        pb.stop()
        XCTAssertNotEqual(observed, 0,
                          "playback at 100 fps should have moved active frame within 50 ms")
    }

    func testTimerWrapsPastEndOfSequence() async throws {
        // 10 frames starting at index 9 (the tail). After ~5 ticks, modular
        // arithmetic puts us at (9 + ticks) % 10, which is 4 at exactly 5 ticks
        // and is in [0, 8] for any tick count from 1 through 9 — i.e., the index
        // wrapped past the end of the array iff it's strictly less than 9.
        let state = makeState(frameCount: 10, fps: 100)
        state.activeFrameIndex = 9
        let pb = PlaybackController(state: state)
        pb.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        let observed = state.activeFrameIndex
        pb.stop()
        XCTAssertLessThan(observed, 9,
                          "expected wrap past the tail frame; saw \(observed)")
    }

    // MARK: - Marquee auto-commit on play (regression: holistic Opus review C1)

    /// Regression test for the Stage 3 / Stage 4 holistic-review pattern: any state
    /// change that alters the destination of an eventual marquee commit MUST
    /// auto-commit the floating selection first. Otherwise the floating overlay
    /// drifts across frames during playback and corrupts both the originating
    /// frame (which keeps its hole) and the eventual landing frame (which receives
    /// pixels meant for a different one).
    func testStartCommitsFloatingMarqueeIntoOriginatingFrame() {
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        let pixels = Data(count: CanvasSize.s16.byteCount)
        let layerID = UUID()
        let f0 = Frame(name: "F0", layers: [Layer(id: layerID, name: "L", pixels: pixels)],
                       activeLayerID: layerID)
        let f1 = Frame(name: "F1", layers: [Layer(id: layerID, name: "L", pixels: pixels)],
                       activeLayerID: layerID)
        let state = EditorState(pieceID: UUID(), size: .s16,
                                frames: [f0, f1], activeFrameIndex: 0, fps: 60)

        // Paint a small block and float it as a marquee selection.
        var grid = state.activeLayerPixelGrid
        grid.setPixel(x: 2, y: 2, color: red)
        grid.setPixel(x: 3, y: 2, color: red)
        state.setActiveLayerPixels(grid.data)
        state.beginMarqueeDefine(at: (2, 2))
        state.updateMarqueeDefine(to: (3, 2))
        state.endMarqueeDefine()
        XCTAssertNotNil(state.selection, "precondition: marquee should be floating")

        let pb = PlaybackController(state: state)
        pb.start()
        XCTAssertNil(state.selection, "start() must auto-commit any floating selection")

        // The committed pixels should be back in frame 0's active layer (not drifted).
        XCTAssertEqual(state.frames[0].layers[0].pixels[(2 * 16 + 2) * 4 + 3], 255,
                       "frame 0's floated pixel must be back in its layer pixels after auto-commit")
        pb.stop()
    }

    func testStartWithNoSelectionDoesNotPanic() {
        let state = makeState()
        XCTAssertNil(state.selection)
        let pb = PlaybackController(state: state)
        pb.start()
        XCTAssertTrue(pb.isRunning)
        pb.stop()
    }
}
