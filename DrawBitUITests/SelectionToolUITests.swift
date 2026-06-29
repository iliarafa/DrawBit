import XCTest

final class SelectionToolUITests: XCTestCase {
    /// Define a selection over a painted pixel, confirm the contextual action bar appears, that a
    /// transform keeps it floating, and that Delete dismisses it.
    func testSelectionActionBarAppearsTransformsAndDeleteDismisses() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // New piece → editor.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()
        let canvas = app.otherElements["Canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15)) // editor is up

        // Paint a pixel at the canvas center (pencil is the default tool).
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Switch to the Select tool — tool buttons are labeled by their uppercased name.
        XCTAssertTrue(app.buttons["SELECT"].waitForExistence(timeout: 15))
        app.buttons["SELECT"].tap()

        // Drag a marquee (in canvas coords) that comfortably contains the painted pixel,
        // so the lift has content and the selection floats.
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.65))
        start.press(forDuration: 0.2, thenDragTo: end)

        // The contextual action bar appears (its buttons are queried by label — the canvas's
        // accessibility identifier propagates onto them, so a custom identifier wouldn't stick).
        XCTAssertTrue(app.buttons["ROTATE"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["FLIP H"].exists)

        // A transform keeps the selection floating, so the bar stays.
        app.buttons["ROTATE"].tap()
        XCTAssertTrue(app.buttons["FLIP H"].waitForExistence(timeout: 5))

        // Delete discards the selection and dismisses the bar.
        app.buttons["DELETE"].tap()
        XCTAssertFalse(app.buttons["FLIP H"].waitForExistence(timeout: 2))
    }
}
