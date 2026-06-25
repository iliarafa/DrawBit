import XCTest

/// Exercises the custom-palette flow end to end through the redesigned color picker:
/// create a palette, add the current color, switch palettes, and delete. Kept deliberately
/// light per the UI-test guidance in CLAUDE.md (generous waits, polled reads, short negatives).
final class ColorPaletteUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testCreateAddSwitchDeleteCustomPalette() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Fresh 32x32 piece from the gallery.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // Open the color picker.
        XCTAssertTrue(app.buttons["ColorSwatch"].waitForExistence(timeout: 15))
        app.buttons["ColorSwatch"].tap()

        // Default view: the palette selector is present (no custom palette yet → no pencil).
        XCTAssertTrue(app.buttons["PaletteSelector"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["EditPalette"].waitForExistence(timeout: 1))

        // Open the inline chooser and create a new palette.
        app.buttons["PaletteSelector"].tap()
        XCTAssertTrue(app.buttons["NewPalette"].waitForExistence(timeout: 15))
        app.buttons["NewPalette"].tap()

        // Lands in the focused edit panel for the new, empty palette.
        XCTAssertTrue(app.textFields["PaletteName"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Tap ADD or FROM DRAW to fill this palette."].waitForExistence(timeout: 15))

        // Add the current color; the empty state gives way to the removable grid.
        app.buttons["AddCurrentColor"].tap()
        XCTAssertTrue(app.staticTexts["Tap a color to remove it."].waitForExistence(timeout: 15))

        // Back to the default view; the new custom palette is selected, so the pencil appears.
        app.buttons["DonePalette"].tap()
        XCTAssertTrue(app.buttons["EditPalette"].waitForExistence(timeout: 15))

        // Switch to a built-in and back to the custom palette via the chooser.
        app.buttons["PaletteSelector"].tap()
        XCTAssertTrue(app.buttons["Palette-DB32"].waitForExistence(timeout: 15))
        app.buttons["Palette-DB32"].tap()
        // DB32 is read-only → no pencil.
        XCTAssertFalse(app.buttons["EditPalette"].waitForExistence(timeout: 1))

        app.buttons["PaletteSelector"].tap()
        XCTAssertTrue(app.buttons["Palette-PALETTE 1"].waitForExistence(timeout: 15))
        app.buttons["Palette-PALETTE 1"].tap()
        XCTAssertTrue(app.buttons["EditPalette"].waitForExistence(timeout: 15))

        // Delete the custom palette; selection falls back and it no longer appears in the chooser.
        app.buttons["EditPalette"].tap()
        XCTAssertTrue(app.buttons["DeletePalette"].waitForExistence(timeout: 15))
        app.buttons["DeletePalette"].tap()

        XCTAssertTrue(app.buttons["PaletteSelector"].waitForExistence(timeout: 15))
        app.buttons["PaletteSelector"].tap()
        XCTAssertTrue(app.buttons["Palette-DB32"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Palette-PALETTE 1"].waitForExistence(timeout: 1))
    }
}
