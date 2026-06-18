import Foundation
import AVFoundation
import UIKit

/// App-global click + haptic for tool / mode selection in the editor toolbar.
///
/// Fires the instant a tool (or the mirror toggle) is tapped, so the accent-color
/// change is reinforced by a light haptic tap and a short 8-bit click — leaving no
/// doubt which tool is live.
///
/// AVFoundation/UIKit are isolated to this file, mirroring how `RadioController`
/// keeps the playback engine in one place. The click plays on its own
/// `AVAudioPlayer` and this type deliberately never touches the shared
/// `AVAudioSession` (no category change, no `setActive`), so a tool tap mixes over
/// DrawBit FM without pausing or ducking the music. (Consequence: while the radio's
/// `.playback` session is active the click rides it and plays through the silent
/// switch, matching the music; with the radio off it follows the default session.)
@MainActor
final class SelectionFeedback {
    static let shared = SelectionFeedback()

    private var player: AVAudioPlayer?
    private let haptics = UISelectionFeedbackGenerator()
    private var prepared = false

    private init() {}

    /// Loads the click and warms up the haptic engine so the first tap has no
    /// latency. Safe to call repeatedly (e.g. on every toolbar `onAppear`).
    func prepare() {
        haptics.prepare()
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: "click", withExtension: "wav")
            ?? Bundle.main.url(forResource: "click", withExtension: "caf") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        prepared = true
    }

    /// Plays the click and fires a light selection haptic. Call from the toolbar
    /// button action, alongside the actual tool change.
    func fire() {
        if !prepared { prepare() }
        haptics.selectionChanged()
        if let player {
            player.currentTime = 0
            player.play()
        }
    }
}
