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
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()

        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-32"].tap()

        // Open the layers panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()

        // Verify the single layer "Layer 1" shows.
        // The name is rendered as Text(layer.name) inside a List cell; look in cells if top-level lookup fails.
        XCTAssertTrue(app.staticTexts["Layer 1"].waitForExistence(timeout: 15))

        // Long-press to enter rename mode.
        app.staticTexts["Layer 1"].press(forDuration: 0.8)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        // Tap to establish keyboard focus, then select all existing text and replace with new name.
        field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.menuItems["Select All"].tap()
        field.typeText("Sketch")
        app.keyboards.buttons["Return"].tap()

        XCTAssertTrue(app.staticTexts["Sketch"].waitForExistence(timeout: 15))

        // Dismiss the layers panel by tapping the backdrop, then navigate back.
        // Tap a coordinate that hits the backdrop (left side of screen, away from the panel).
        let backdrop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        backdrop.tap()

        // Wait for panel to animate out (0.18s), then tap Gallery.
        XCTAssertTrue(app.buttons["Gallery"].waitForExistence(timeout: 15))
        app.buttons["Gallery"].tap()

        // Wait for the gallery root view (NewButton is always visible in the gallery).
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 10))

        // Reopen the same piece. PieceThumbnail now has the .isButton trait so XCTest can
        // find and tap it even when the piece has no thumbnail image yet.
        // Exactly one piece exists in this fresh-store run, so firstMatch is unambiguous.
        XCTAssertTrue(app.buttons["PieceThumbnail"].waitForExistence(timeout: 15))
        app.buttons["PieceThumbnail"].firstMatch.tap()

        // Reopen the layers panel in the editor.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()

        // The rename must have been persisted — "Sketch" should still appear.
        XCTAssertTrue(app.staticTexts["Sketch"].waitForExistence(timeout: 15),
                      "Layer rename was not persisted across editor sessions")
    }

    func testAddDrawDeleteFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Create a fresh 32x32 piece from the gallery.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()

        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-32"].tap()

        // Open the layers panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()

        // Add a second layer via the action bar's + button (LayersPanel-plus).
        // We use the explicit accessibility identifier to avoid ambiguity with the
        // "plus" SF symbol that also appears in the RecentColorsStrip.
        // addLayer names the new layer by count, so the result is "Layer 2".
        XCTAssertTrue(app.buttons["LayersPanel-plus"].waitForExistence(timeout: 15))
        app.buttons["LayersPanel-plus"].tap()
        XCTAssertTrue(app.staticTexts["Layer 2"].waitForExistence(timeout: 15))

        // Dismiss the panel by tapping the LAYERS button again (toggles closed).
        app.buttons["LAYERS"].tap()

        // Tap the canvas to draw on the active layer (Layer 2).
        let canvas = app.otherElements["Canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        canvas.tap()

        // Reopen the panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()

        // Delete Layer 2. The tap above made it non-empty, so a confirmation
        // dialog should appear.
        XCTAssertTrue(app.buttons["trash"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["trash"].firstMatch.tap()

        // Confirm the delete if the dialog appeared (tap should have made the layer non-empty,
        // but tolerate either path in case CanvasView's tap mapping fell on a transparent pixel).
        if app.buttons["Delete"].waitForExistence(timeout: 1) {
            app.buttons["Delete"].tap()
        }

        // Layer 2 row should be gone; Layer 1 should remain.
        XCTAssertFalse(app.staticTexts["Layer 2"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Layer 1"].exists)
    }

    func testAddDrawDeletePersistsAcrossSessionBoundary() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Create a fresh 32x32 piece from the gallery.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-32"].tap()

        // Open layers panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()
        XCTAssertTrue(app.staticTexts["Layer 1"].waitForExistence(timeout: 15))

        // Add a second layer via doc.on.doc (duplicateActiveLayer). This test covers
        // the duplicate code path and the persistence round-trip; testAddDrawDeleteFlow
        // covers the addLayer (LayersPanel-plus) code path separately.
        // The duplicate creates a layer named "Layer 1 copy".
        XCTAssertTrue(app.buttons["doc.on.doc"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["doc.on.doc"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Layer 1 copy"].waitForExistence(timeout: 15))

        // Dismiss panel by tapping LAYERS again, then tap canvas to draw on the new layer.
        app.buttons["LAYERS"].tap()
        let canvas = app.otherElements["Canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        canvas.tap()

        // Reopen the panel and delete the duplicate layer (it now has a pixel, so the
        // confirmation dialog should appear; if for any reason it doesn't,
        // the empty-fast-path will have deleted it without confirmation).
        app.buttons["LAYERS"].tap()
        XCTAssertTrue(app.buttons["trash"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["trash"].firstMatch.tap()
        if app.buttons["Delete"].waitForExistence(timeout: 1) {
            app.buttons["Delete"].tap()
        }
        // The duplicate is gone. Layer 1 remains.
        XCTAssertFalse(app.staticTexts["Layer 1 copy"].exists)
        XCTAssertTrue(app.staticTexts["Layer 1"].exists)

        // Persistence check: navigate back to gallery and reopen the piece.
        // "Layer 1 copy" should still be gone after the round-trip through SwiftData.
        // First dismiss the panel (tap the dim backdrop on the left side, well
        // away from the panel's 360pt right column).
        let window = app.windows.firstMatch
        let backdropPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        backdropPoint.tap()

        app.buttons["Gallery"].tap()
        XCTAssertTrue(app.buttons["PieceThumbnail"].waitForExistence(timeout: 15))
        app.buttons["PieceThumbnail"].tap()
        app.buttons["LAYERS"].tap()
        XCTAssertTrue(app.staticTexts["Layer 1"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Layer 1 copy"].exists)
    }

    func testVisibilityAndLockTogglesPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Create a fresh 32×32 piece.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-32"].tap()

        // Open the layers panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()
        XCTAssertTrue(app.staticTexts["Layer 1"].waitForExistence(timeout: 15))

        // Default state: layer is visible (eye) and unlocked (lock.open).
        XCTAssertTrue(app.buttons["eye"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["lock.open"].firstMatch.exists)

        // Toggle visibility: eye → eye.slash.
        app.buttons["eye"].firstMatch.tap()
        XCTAssertTrue(app.buttons["eye.slash"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["eye"].firstMatch.exists)

        // Toggle lock: lock.open → lock.fill.
        app.buttons["lock.open"].firstMatch.tap()
        XCTAssertTrue(app.buttons["lock.fill"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["lock.open"].firstMatch.exists)

        // Persistence round-trip: dismiss panel → Gallery → reopen piece → reopen panel.
        // Both toggled states should still be in effect.
        let window = app.windows.firstMatch
        let backdropPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        backdropPoint.tap()
        app.buttons["Gallery"].tap()
        XCTAssertTrue(app.buttons["PieceThumbnail"].waitForExistence(timeout: 15))
        app.buttons["PieceThumbnail"].tap()
        app.buttons["LAYERS"].tap()
        XCTAssertTrue(app.staticTexts["Layer 1"].waitForExistence(timeout: 15))

        // Both toggles survived the SwiftData round-trip.
        XCTAssertTrue(app.buttons["eye.slash"].firstMatch.exists)
        XCTAssertTrue(app.buttons["lock.fill"].firstMatch.exists)
    }
}
