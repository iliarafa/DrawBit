import XCTest

final class RadioStripUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testRadioStripAppearsInGallery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // -UITest-skipLanding lands straight in the gallery; the DrawBit FM strip
        // sits under the GALLERY header. (Controls are present even with no bundled
        // audio — they're just disabled in that empty-station state.)
        XCTAssertTrue(app.staticTexts["DRAWBIT FM"].waitForExistence(timeout: 5),
                      "DrawBit FM header must appear in the gallery")
        XCTAssertTrue(app.buttons["RadioStrip.playPause"].exists,
                      "FM play/pause control must be present")
        XCTAssertTrue(app.buttons["RadioStrip.next"].exists,
                      "FM next control must be present")
        XCTAssertTrue(app.buttons["RadioStrip.previous"].exists,
                      "FM previous control must be present")
    }

    func testPlayTogglesToPause() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        let play = app.buttons["RadioStrip.playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        // The bundled station ships with tracks, so the control is live.
        XCTAssertTrue(play.isEnabled, "play must be enabled when the station has tracks")
        XCTAssertEqual(play.label, "Play station")

        play.tap()

        // Tapping play starts playback; the control flips to the pause state.
        var flipped = false
        for _ in 0..<10 {
            if app.buttons["RadioStrip.playPause"].label == "Pause station" { flipped = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(flipped, "tapping play must start playback and flip to 'Pause station'")
    }
}
