import XCTest

final class LayersPanelUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOpenPanelAndRenameLayer() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Create a fresh 32x32 piece from the gallery.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 5))
        app.buttons["NewButton"].tap()

        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 3))
        app.buttons["NewPiece-32"].tap()

        // Open the layers panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 3))
        app.buttons["LAYERS"].tap()

        // Verify the single layer "Layer 1" shows.
        // The name is rendered as Text(layer.name) inside a List cell; look in cells if top-level lookup fails.
        XCTAssertTrue(app.staticTexts["Layer 1"].waitForExistence(timeout: 2))

        // Long-press to enter rename mode.
        app.staticTexts["Layer 1"].press(forDuration: 0.8)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        // Tap to establish keyboard focus, then select all existing text and replace with new name.
        field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.menuItems["Select All"].tap()
        field.typeText("Sketch")
        app.keyboards.buttons["Return"].tap()

        XCTAssertTrue(app.staticTexts["Sketch"].waitForExistence(timeout: 2))

        // Dismiss the layers panel by tapping the backdrop, then navigate back.
        // Tap a coordinate that hits the backdrop (left side of screen, away from the panel).
        let backdrop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        backdrop.tap()

        // Wait for panel to animate out (0.18s), then tap Gallery.
        XCTAssertTrue(app.buttons["Gallery"].waitForExistence(timeout: 3))
        app.buttons["Gallery"].tap()

        // Wait for the gallery root view (NewButton is always visible in the gallery).
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 10))

        // Reopen the same piece. PieceThumbnail now has the .isButton trait so XCTest can
        // find and tap it even when the piece has no thumbnail image yet.
        // Exactly one piece exists in this fresh-store run, so firstMatch is unambiguous.
        XCTAssertTrue(app.buttons["PieceThumbnail"].waitForExistence(timeout: 5))
        app.buttons["PieceThumbnail"].firstMatch.tap()

        // Reopen the layers panel in the editor.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 3))
        app.buttons["LAYERS"].tap()

        // The rename must have been persisted — "Sketch" should still appear.
        XCTAssertTrue(app.staticTexts["Sketch"].waitForExistence(timeout: 2),
                      "Layer rename was not persisted across editor sessions")
    }
}
