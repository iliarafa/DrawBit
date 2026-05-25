import Foundation
import Observation

/// The DrawBit FM station — owns the bundled `Playlist` and (later) the audio
/// engine. Created once at app scope (`DrawBitApp`) and injected into the
/// environment so playback survives the Gallery↔Editor switch and the background.
///
/// This is the skeleton: it exposes the surface the UI binds to, with transport
/// methods that move through the playlist but do not yet produce sound. The
/// AVFoundation engine, progress timer, audio session, and Now Playing wiring
/// land in later tasks.
@MainActor
@Observable
final class RadioController {
    @ObservationIgnored private var playlist: Playlist

    /// True while the station is playing.
    private(set) var isPlaying = false
    /// Position within the current track, 0...1.
    private(set) var progress: Double = 0

    init(tracks: [AudioTrack]? = nil) {
        self.playlist = Playlist(tracks: tracks ?? BundledTracks.load())
    }

    var hasTracks: Bool { !playlist.isEmpty }
    var currentTitle: String { playlist.current?.title ?? "" }

    func togglePlayPause() {
        guard hasTracks else { return }
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard hasTracks else { return }
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func next() {
        guard hasTracks else { return }
        playlist.next()
        progress = 0
    }

    func previous() {
        guard hasTracks else { return }
        playlist.previous()
        progress = 0
    }

    func seek(toFraction fraction: Double) {
        guard hasTracks else { return }
        progress = min(1, max(0, fraction))
    }
}
