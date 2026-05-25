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
}
