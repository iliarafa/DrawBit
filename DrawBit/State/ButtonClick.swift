import Foundation
import AVFoundation
import QuartzCore
import UIKit

/// App-global tactile feedback for the New Draw controls: a literal mechanical click sound
/// paired with a haptic. Two entry points share the one gentle click:
///   • `fire()`  — single button press (light **impact** haptic), on touch-down.
///   • `tick()`  — a slider detent (selection haptic), fired rapidly per integer step.
///
/// Mirrors `SelectionFeedback`'s isolation: AVFoundation/UIKit live in this one file, and the
/// click plays on its own players that **deliberately never touch the shared `AVAudioSession`**
/// (no category change, no `setActive`), so feedback mixes over DrawBit FM without ducking it.
/// A small round-robin player pool lets rapid `tick()`s overlap their decay tails cleanly
/// instead of one player hard-restarting. Haptics are device-only (no-op on the Simulator).
@MainActor
final class ButtonClick {
    static let shared = ButtonClick()

    private var pool: [AVAudioPlayer] = []
    private var next = 0
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let selection = UISelectionFeedbackGenerator()
    private var prepared = false

    /// Min spacing between slider ticks — caps a fast flick at ~80 ticks/sec so it reads as
    /// "rapid" without machine-gunning hundreds of plays/sec.
    private let tickInterval: CFTimeInterval = 0.012
    private var lastTick: CFTimeInterval = 0

    private static let poolSize = 6

    private init() {}

    /// Loads the click pool and warms both haptic generators so the first press/tick has no
    /// latency. Safe to call repeatedly (e.g. on the sheet's `onAppear`).
    func prepare() {
        impact.prepare()
        selection.prepare()
        guard pool.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "button-press", withExtension: "wav")
            ?? Bundle.main.url(forResource: "button-press", withExtension: "caf") else { return }
        for _ in 0..<Self.poolSize {
            if let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                pool.append(p)
            }
        }
        prepared = !pool.isEmpty
    }

    /// Plays the click on the next pooled player (round-robin).
    private func play() {
        if !prepared { prepare() }
        guard !pool.isEmpty else { return }
        let p = pool[next]
        next = (next + 1) % pool.count
        p.currentTime = 0
        p.play()
    }

    /// Single button press: light-impact haptic + click, on touch-down.
    func fire() {
        impact.impactOccurred()
        play()
    }

    /// Slider detent: selection haptic + click, throttled for rapid drags.
    func tick() {
        let now = CACurrentMediaTime()
        guard now - lastTick >= tickInterval else { return }
        lastTick = now
        selection.selectionChanged()
        play()
    }
}
