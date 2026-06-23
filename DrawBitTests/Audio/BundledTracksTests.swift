import XCTest
@testable import DrawBit

final class BundledTracksTests: XCTestCase {

    func testPrettifyTitleDropsTrackNumberAndSeparators() {
        XCTAssertEqual(BundledTracks.prettifyTitle(fileName: "01-chiptune_dawn.m4a"), "CHIPTUNE DAWN")
        XCTAssertEqual(BundledTracks.prettifyTitle(fileName: "03 morning.m4a"), "MORNING")
        XCTAssertEqual(BundledTracks.prettifyTitle(fileName: "lofi-beat.mp3"), "LOFI BEAT")
        XCTAssertEqual(BundledTracks.prettifyTitle(fileName: "noprefix.m4a"), "NOPREFIX")
    }

    func testSortByFileNameIsNumericAware() {
        let urls = ["10-z.m4a", "2-b.m4a", "1-a.m4a"].map { URL(fileURLWithPath: "/tmp/\($0)") }
        let sorted = BundledTracks.sortedByFileName(urls).map { $0.lastPathComponent }
        XCTAssertEqual(sorted, ["1-a.m4a", "2-b.m4a", "10-z.m4a"])
    }

    func testLoadFromBundleWithoutAudioReturnsEmpty() {
        let testBundle = Bundle(for: BundledTracksTests.self)
        XCTAssertEqual(BundledTracks.load(bundle: testBundle), [])
    }

    func testIsStationFileExcludesNonNumericPrefixedAudio() {
        // Station tracks use a numeric prefix and stay in the playlist.
        XCTAssertTrue(BundledTracks.isStationFile("01-sunrise.mp3"))
        XCTAssertTrue(BundledTracks.isStationFile("10-cyber_angel.mp3"))
        // The intro music (and any other root-bundled audio) is not a station.
        XCTAssertFalse(BundledTracks.isStationFile("dbfm7.mp3"))
        XCTAssertFalse(BundledTracks.isStationFile("intro.mp3"))
        XCTAssertFalse(BundledTracks.isStationFile("click.wav"))
    }
}
