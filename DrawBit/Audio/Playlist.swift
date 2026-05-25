import Foundation

/// Pure, testable sequencing for the DrawBit FM station. No AVFoundation, no
/// timer, no main-actor isolation — this is the `Drawing/`-style logic core that
/// `RadioController` drives. Every navigation method is empty-safe and wraps
/// around (playlist-radio behavior: after the last track, loop to the first).
struct Playlist: Equatable {
    private(set) var tracks: [AudioTrack]
    private(set) var currentIndex: Int

    init(tracks: [AudioTrack] = []) {
        self.tracks = tracks
        self.currentIndex = 0
    }

    var isEmpty: Bool { tracks.isEmpty }

    var current: AudioTrack? {
        guard tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    /// User pressed "next" — advance one, wrapping after the last.
    mutating func next() { step(1) }

    /// User pressed "previous" — go back one, wrapping before the first.
    mutating func previous() { step(-1) }

    /// A track finished playing — advance to the next (wraps after the last).
    /// Named distinctly from `next()` so call sites read clearly; a single-track
    /// playlist wraps to itself, i.e. the track replays.
    mutating func advance() { step(1) }

    /// Jump to a specific index. Out-of-range values are ignored.
    mutating func select(index: Int) {
        guard tracks.indices.contains(index) else { return }
        currentIndex = index
    }

    /// Jump to a specific track by id. Unknown ids are ignored.
    mutating func select(id: AudioTrack.ID) {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        currentIndex = idx
    }

    private mutating func step(_ delta: Int) {
        guard !tracks.isEmpty else { return }
        let n = tracks.count
        currentIndex = ((currentIndex + delta) % n + n) % n
    }
}
