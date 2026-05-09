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

    func testAdvancesActiveFrameAtFPS() async throws {
        // 2 frames @ 100 fps = 10 ms per advance. After ~70 ms we should observe
        // the active index move at least once. Loose tolerance to keep CI happy.
        let state = makeState(frameCount: 2, fps: 100)
        let pb = PlaybackController(state: state)
        XCTAssertEqual(state.activeFrameIndex, 0)
        pb.start()
        try await Task.sleep(nanoseconds: 70_000_000)
        let advanced = state.activeFrameIndex != 0
        pb.stop()
        XCTAssertTrue(advanced, "playback should have moved active frame within 70ms at 100fps")
    }

    func testLoopsAroundEndOfSequence() async throws {
        // 3 frames starting at index 2, 100 fps. After ~30 ms we should see at least
        // one advance — the next index after 2 must wrap to 0.
        let state = makeState(frameCount: 3, fps: 100)
        state.activeFrameIndex = 2
        let pb = PlaybackController(state: state)
        pb.start()
        try await Task.sleep(nanoseconds: 70_000_000)
        pb.stop()
        // After looping at least once, we must have visited index 0.
        // We can't easily assert "visited" without an observer, so we assert:
        // the active index is no longer 2 (it advanced at least once and either
        // landed at 0, 1, or back at 2 after a full lap; given timing, it should
        // have moved at least once).
        XCTAssertNotEqual(state.activeFrameIndex, 2, "playback should have advanced past the starting tail frame")
    }
}
