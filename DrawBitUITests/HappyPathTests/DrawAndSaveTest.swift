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

    /// A save that fails must not be silent: the editor surfaces a non-blocking indicator.
    /// `-UITest-failSaves` forces the content autosave to throw so we can drive the path
    /// that a disk-full failure would otherwise hit (and normally swallow via `try?`).
    func testFailedSaveShowsIndicator() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding", "-UITest-failSaves"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // Nothing has been saved yet, so no indicator.
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "EditorSaveError").firstMatch.waitForExistence(timeout: 1),
                       "No save-error indicator before any save is attempted")

        // Paint one pixel → triggers an autosave, which is forced to fail.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "EditorSaveError").firstMatch.waitForExistence(timeout: 15),
                      "A failed autosave must surface a non-blocking save-error indicator")
    }
}
