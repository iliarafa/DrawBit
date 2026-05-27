import XCTest
@testable import DrawBit

/// Lightweight tests for the public surface `FMScreen` reads from
/// `RadioController`: the track list and the current index. We don't exercise
/// `play(trackAt:)` here because the AVAudioPlayer load on a synthetic URL
/// cascades into the auto-advance-on-failure path; that wiring is verified by
/// `FMScreenUITests` against the real bundled station. The pure `Playlist`
/// covers the index-jump semantics in `PlaylistTests`.
@MainActor
final class RadioControllerTests: XCTestCase {

    private func tracks(_ n: Int) -> [AudioTrack] {
        (1...n).map { AudioTrack(url: URL(fileURLWithPath: "/tmp/\($0).m4a"), title: "T\($0)") }
    }

    func testTracksAccessorMirrorsInit() {
        let r = RadioController(tracks: tracks(3))
        XCTAssertEqual(r.tracks.map(\.title), ["T1", "T2", "T3"])
    }

    func testCurrentIndexStartsAtZero() {
        let r = RadioController(tracks: tracks(3))
        XCTAssertEqual(r.currentIndex, 0)
        XCTAssertEqual(r.currentTitle, "T1")
    }

    func testEmptyStationHasNoTracksAndNoTitle() {
        let r = RadioController(tracks: [])
        XCTAssertTrue(r.tracks.isEmpty)
        XCTAssertFalse(r.hasTracks)
        XCTAssertEqual(r.currentTitle, "")
    }
}
