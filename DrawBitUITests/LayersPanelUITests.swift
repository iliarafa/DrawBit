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
    }
}
