import Foundation
import AVFoundation

/// App-global one-shot player for the intro music (`dbfm7.mp3`), which scores the
/// launch animation when the user taps PRESS START. Plays once through (no loop).
///
/// Mirrors `SelectionFeedback`'s "AVFoundation isolated to one file" shape, but —
/// unlike the click, which deliberately never touches the shared session — this one
/// sets the session to `.ambient` so the silent-switch behavior is *guaranteed*: the
/// intro auto-plays without the user asking, so on a silenced phone it stays quiet,
/// and `.ambient` mixes politely over any other app's audio instead of interrupting
/// it. (DrawBit FM, started deliberately, later flips the session back to `.playback`.)
@MainActor
final class IntroAudio {
    static let shared = IntroAudio()

    private var player: AVAudioPlayer?

    private init() {}

    /// Load and play the intro once. No-op if the resource is missing.
    func play() {
        if player == nil {
            guard let url = Bundle.main.url(forResource: "dbfm7", withExtension: "mp3") else { return }
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = 0
            player?.prepareToPlay()
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        try? session.setActive(true)
        player?.currentTime = 0
        player?.play()
    }

    /// Stop the intro early — when the user starts DrawBit FM or opens a piece, so
    /// the 17s clip never overlaps the music or bleeds into the canvas. Safe when the
    /// intro was never played.
    func stop() {
        player?.stop()
    }
}
