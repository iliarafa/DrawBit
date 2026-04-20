import XCTest

final class DrawAndSaveTest: XCTestCase {
    func testCreatePieceDrawAndReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset"]
        app.launch()

        // 1. Create a 32x32 piece from the gallery.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 5))
        app.buttons["NewButton"].tap()

        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 3))
        app.buttons["NewPiece-32"].tap()

        // 2. Editor is up. Tap near the middle to paint one pixel.
        let window = app.windows.firstMatch
        let center = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.tap()

        // 3. Go back to the gallery.
        XCTAssertTrue(app.buttons["Gallery"].waitForExistence(timeout: 3))
        app.buttons["Gallery"].tap()

        // 4. The thumbnail for our piece should be present.
        XCTAssertTrue(app.otherElements["PieceThumbnail"].waitForExistence(timeout: 3)
                      || app.images["PieceThumbnail"].waitForExistence(timeout: 1))
    }
}
