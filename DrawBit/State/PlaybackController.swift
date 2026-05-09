import Foundation

/// Drives `EditorState.activeFrameIndex` forward at `state.fps`, looping at the end
/// of the sequence. Stays on the main thread (Timer scheduled on the current run loop
/// by `@MainActor` isolation). Single-frame sequences are not playable.
@MainActor
final class PlaybackController {
    private weak var state: EditorState?
    private var timer: Timer?
    private(set) var isRunning: Bool = false

    init(state: EditorState) { self.state = state }

    func start() {
        guard !isRunning, let state, state.frames.count > 1 else { return }
        let fps = max(1, min(120, state.fps))
        let interval = 1.0 / TimeInterval(fps)
        isRunning = true
        state.isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let state = self.state else { return }
                let next = (state.activeFrameIndex + 1) % state.frames.count
                state.activeFrameIndex = next
            }
        }
    }

    func stop() {
        isRunning = false
        state?.isPlaying = false
        timer?.invalidate()
        timer = nil
    }
}
