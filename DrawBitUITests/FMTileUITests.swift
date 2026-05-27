import XCTest

/// The `FMTile` is the first cell in the gallery grid (before the piece
/// thumbnails) and the doorway to `FMScreen`. It also exposes an inline
/// play/pause that pauses without leaving the gallery — verified here.
final class FMTileUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testFMTileAppearsInGalleryWithWordmark() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // The tile shows the "DRAWBIT FM" wordmark and the inline play/pause.
        XCTAssertTrue(app.staticTexts["DRAWBIT FM"].waitForExistence(timeout: 15),
                      "FM tile wordmark must appear in the gallery")
        XCTAssertTrue(app.buttons["FM.tile.playPause"].exists,
                      "FM tile must expose an inline play/pause control")
    }

    func testInlinePlayTogglesToPauseWithoutNavigating() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        let play = app.buttons["FM.tile.playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertTrue(play.isEnabled, "play must be enabled when the bundled station has tracks")
        XCTAssertEqual(play.label, "Play station")

        play.tap()

        // Tapping the inline button must NOT push the FM screen — gallery stays put.
        XCTAssertFalse(app.otherElements["FM.screen"].waitForExistence(timeout: 1),
                       "tapping inline play/pause must not navigate to the FM destination")

        var flipped = false
        for _ in 0..<25 {
            if app.buttons["FM.tile.playPause"].label == "Pause station" { flipped = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(flipped, "inline play/pause must flip to 'Pause station' after tap")
    }

    func testTappingTileBodyPushesFMScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Tap the "DRAWBIT FM" wordmark inside the tile. It lives at the top-left,
        // away from the inline play/pause control — so the tap bubbles to the
        // tile's outer `.onTapGesture` set by `GalleryView` and pushes `FMScreen`.
        let wordmark = app.staticTexts["DRAWBIT FM"]
        XCTAssertTrue(wordmark.waitForExistence(timeout: 15), "FM tile wordmark must exist")
        wordmark.tap()

        // The destination's transport button is unique to `FMScreen` (the tile
        // uses `FM.tile.playPause`), so its appearance proves the push happened.
        XCTAssertTrue(app.buttons["FM.playPause"].waitForExistence(timeout: 15),
                      "tapping the tile body must push the FM destination")
    }
}
