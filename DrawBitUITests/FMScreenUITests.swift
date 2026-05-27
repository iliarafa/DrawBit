import XCTest

/// `FMScreen` is the pushed FM destination. These tests verify it renders the
/// transport, scrubber, and track list, and that tapping a track row jumps
/// playback to that track.
final class FMScreenUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launchAndOpenFM() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // The tile's wordmark is the safest tap target — it's a child of the
        // tile, away from the inline play/pause, and the tap bubbles to the
        // tile's outer `.onTapGesture` for navigation.
        let wordmark = app.staticTexts["DRAWBIT FM"]
        XCTAssertTrue(wordmark.waitForExistence(timeout: 15), "FM tile wordmark must exist before opening")
        wordmark.tap()

        // `FM.playPause` is unique to the destination (the tile's is `FM.tile.playPause`).
        XCTAssertTrue(app.buttons["FM.playPause"].waitForExistence(timeout: 15),
                      "FM destination must push when the tile is tapped")
        return app
    }

    func testFMScreenShowsTransportAndScrubber() throws {
        let app = launchAndOpenFM()

        XCTAssertTrue(app.buttons["FM.playPause"].waitForExistence(timeout: 15),
                      "FM screen must show the play/pause transport")
        XCTAssertTrue(app.buttons["FM.next"].exists, "FM screen must show the next button")
        XCTAssertTrue(app.buttons["FM.previous"].exists, "FM screen must show the previous button")
        XCTAssertTrue(app.otherElements["FM.scrubber"].exists,
                      "FM screen must show the scrubber")
    }

    func testFMScreenShowsTrackList() throws {
        let app = launchAndOpenFM()

        // The bundled station ships with at least 2 tracks (today: 6). Verify
        // the first two rows render — that confirms the list mounts.
        XCTAssertTrue(app.buttons["FM.trackRow.0"].waitForExistence(timeout: 15),
                      "FM screen must show the first track row")
        XCTAssertTrue(app.buttons["FM.trackRow.1"].exists,
                      "FM screen must show the second track row")
    }

    func testTappingTrackRowChangesCurrentTrack() throws {
        let app = launchAndOpenFM()

        let row1 = app.buttons["FM.trackRow.1"]
        XCTAssertTrue(row1.waitForExistence(timeout: 15))

        // Capture the displayed current-track title, then tap the second row.
        let titleField = app.staticTexts["FM.currentTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 15))
        let initial = titleField.label

        row1.tap()

        // The title should change to the second track. Poll because the
        // controller updates via @Observable and SwiftUI rebuilds.
        var changed = false
        for _ in 0..<25 {
            if app.staticTexts["FM.currentTitle"].label != initial { changed = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(changed, "tapping a different track row must change the displayed current title")
    }
}
