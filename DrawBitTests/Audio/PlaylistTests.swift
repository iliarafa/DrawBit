import XCTest
@testable import DrawBit

final class PlaylistTests: XCTestCase {

    private func tracks(_ n: Int) -> [AudioTrack] {
        (1...n).map { AudioTrack(url: URL(fileURLWithPath: "/tmp/\($0).m4a"), title: "T\($0)") }
    }

    func testEmptyPlaylistIsSafe() {
        var p = Playlist(tracks: [])
        XCTAssertTrue(p.isEmpty)
        XCTAssertNil(p.current)
        p.next(); XCTAssertEqual(p.currentIndex, 0); XCTAssertNil(p.current)
        p.previous(); XCTAssertEqual(p.currentIndex, 0)
        p.advance(); XCTAssertEqual(p.currentIndex, 0)
    }

    func testNextWrapsAtEnd() {
        var p = Playlist(tracks: tracks(3))
        XCTAssertEqual(p.current?.title, "T1")
        p.next(); XCTAssertEqual(p.current?.title, "T2")
        p.next(); XCTAssertEqual(p.current?.title, "T3")
        p.next(); XCTAssertEqual(p.current?.title, "T1", "next at last wraps to first")
    }

    func testPreviousWrapsAtStart() {
        var p = Playlist(tracks: tracks(3))
        p.previous(); XCTAssertEqual(p.current?.title, "T3", "previous at first wraps to last")
        p.previous(); XCTAssertEqual(p.current?.title, "T2")
    }

    func testAdvanceLoopsPlaylist() {
        var p = Playlist(tracks: tracks(2))
        p.select(index: 1)
        XCTAssertEqual(p.current?.title, "T2")
        p.advance(); XCTAssertEqual(p.current?.title, "T1", "advance from last loops to first")
    }

    func testSingleTrackReplays() {
        var p = Playlist(tracks: tracks(1))
        XCTAssertEqual(p.current?.title, "T1")
        p.advance(); XCTAssertEqual(p.currentIndex, 0)
        p.next(); XCTAssertEqual(p.currentIndex, 0)
        p.previous(); XCTAssertEqual(p.currentIndex, 0)
        XCTAssertEqual(p.current?.title, "T1")
    }

    func testSelectIndexIgnoresOutOfRange() {
        var p = Playlist(tracks: tracks(3))
        p.select(index: 2); XCTAssertEqual(p.current?.title, "T3")
        p.select(index: 99); XCTAssertEqual(p.current?.title, "T3", "out-of-range ignored")
        p.select(index: -1); XCTAssertEqual(p.current?.title, "T3", "negative ignored")
    }

    func testSelectByID() {
        let t = tracks(3)
        var p = Playlist(tracks: t)
        p.select(id: t[1].id)
        XCTAssertEqual(p.current?.title, "T2")
    }
}
