import XCTest

final class DrawAndSaveTest: XCTestCase {
    func testCreatePieceDrawAndReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // 1. Create a 32x32 piece from the gallery.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()

        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // 2. Editor is up. Tap near the middle to paint one pixel.
        let window = app.windows.firstMatch
        let center = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.tap()

        // 3. Go back to the gallery.
        XCTAssertTrue(app.buttons["Gallery"].waitForExistence(timeout: 15))
        app.buttons["Gallery"].tap()

        // 4. The thumbnail for our piece should be present.
        // PieceThumbnailView has the .isButton trait so XCTest reports it as a button element.
        XCTAssertTrue(app.buttons["PieceThumbnail"].waitForExistence(timeout: 15))
    }
}
