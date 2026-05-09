import Foundation

/// Drives `EditorState.activeFrameIndex` forward at `state.fps`, looping at the end
/// of the sequence. Stays on the main thread (Timer scheduled on the main run loop
/// in `.common` modes so playback keeps ticking during scroll-tracking gestures).
/// Single-frame sequences are not playable.
///
/// **Marquee invariant:** `start()` auto-commits any floating selection before
/// the timer arms, otherwise the floating overlay would drift across frames and
/// commit into the wrong frame on a later tap. This mirrors the Stage 3 fix
/// where any state mutation that changes the destination of a marquee commit
/// must commit it first. Callers should also persist after the auto-commit.
@MainActor
final class PlaybackController {
    private weak var state: EditorState?
    private var timer: Timer?
    private(set) var isRunning: Bool = false

    init(state: EditorState) { self.state = state }

    deinit {
        // `Timer.invalidate()` is documented as safe to call from any thread; the
        // timer is otherwise retained by the run loop and would keep firing for the
        // lifetime of the process if the controller is dropped without explicit stop.
        timer?.invalidate()
    }

    func start() {
        guard !isRunning, let state, state.frames.count > 1 else { return }
        // Auto-commit any floating selection so it lands in its originating frame
        // before playback begins drifting through the sequence.
        state.commitFloatingSelectionIfAny()
        let fps = max(1, min(120, state.fps))
        let interval = 1.0 / TimeInterval(fps)
        isRunning = true
        state.isPlaying = true
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let state = self.state else { return }
                let next = (state.activeFrameIndex + 1) % state.frames.count
                state.activeFrameIndex = next
            }
        }
        // .common keeps the timer firing during scroll-tracking gestures (FramesStrip
        // ScrollView, system gestures). Default scheduling would freeze playback for
        // the duration of any tracking interaction.
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    func stop() {
        isRunning = false
        state?.isPlaying = false
        timer?.invalidate()
        timer = nil
    }
}
