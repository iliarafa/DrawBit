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

        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // Open the layers panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()

        // Verify the single layer "Layer 1" shows.
        // The name is rendered as Text(layer.name) inside a List cell; look in cells if top-level lookup fails.
        XCTAssertTrue(app.staticTexts["Layer 1"].waitForExistence(timeout: 15))

        // Tap the inline Rename (pencil) button on the row to enter rename mode.
        XCTAssertTrue(app.buttons["Rename"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Rename"].firstMatch.tap()
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

        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // Open the layers panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()

        // Add a second layer via the action bar's ADD button (LayersPanel-plus).
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
        XCTAssertTrue(app.buttons["LayersPanel-delete"].waitForExistence(timeout: 15))
        app.buttons["LayersPanel-delete"].tap()

        // Confirm the delete if the dialog appeared (tap should have made the layer non-empty,
        // but tolerate either path in case CanvasView's tap mapping fell on a transparent pixel).
        if app.buttons["ConfirmDialog.confirm"].waitForExistence(timeout: 1) {
            app.buttons["ConfirmDialog.confirm"].tap()
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
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // Open layers panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()
        XCTAssertTrue(app.staticTexts["Layer 1"].waitForExistence(timeout: 15))

        // Add a second layer via the DUPE button (duplicateActiveLayer). This test
        // covers the duplicate code path and the persistence round-trip;
        // testAddDrawDeleteFlow covers the addLayer (LayersPanel-plus) code path
        // separately. The duplicate creates a layer named "Layer 1 copy".
        XCTAssertTrue(app.buttons["LayersPanel-duplicate"].waitForExistence(timeout: 15))
        app.buttons["LayersPanel-duplicate"].tap()
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
        XCTAssertTrue(app.buttons["LayersPanel-delete"].waitForExistence(timeout: 15))
        app.buttons["LayersPanel-delete"].tap()
        if app.buttons["ConfirmDialog.confirm"].waitForExistence(timeout: 1) {
            app.buttons["ConfirmDialog.confirm"].tap()
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

    /// Layers reorder no longer requires entering an Edit mode: dragging a row
    /// works inline like the FramesStrip does. This guards against the EDIT
    /// button being re-added as a reorder gate.
    func testReorderHasNoEditModeGate() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Fresh 32×32 piece.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // Open the layers panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()
        XCTAssertTrue(app.staticTexts["Layer 1"].waitForExistence(timeout: 15))

        // The EDIT button must not exist anywhere in the panel — it was removed
        // along with the EditMode gating in favor of direct drag-to-reorder.
        XCTAssertFalse(app.buttons["EDIT"].waitForExistence(timeout: 1),
                       "EDIT button should be gone — reorder is now direct drag")

        // DUPE creates "Layer 1 copy" — basic panel actions still work.
        XCTAssertTrue(app.buttons["LayersPanel-duplicate"].waitForExistence(timeout: 15))
        app.buttons["LayersPanel-duplicate"].tap()
        XCTAssertTrue(app.staticTexts["Layer 1 copy"].waitForExistence(timeout: 15))

        // The inline Rename (pencil) button still works.
        XCTAssertTrue(app.buttons["Rename"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Rename"].firstMatch.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 15))
    }

    /// Swipe-left on a layer row deletes it (in addition to the DELETE button).
    /// The freshly-added Layer 2 is empty, so it deletes without a confirmation dialog.
    func testSwipeLeftDeletesLayer() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()

        // Add Layer 2 so there are two layers (the last layer can't be swipe-deleted).
        XCTAssertTrue(app.buttons["LayersPanel-plus"].waitForExistence(timeout: 15))
        app.buttons["LayersPanel-plus"].tap()
        let layer2 = app.staticTexts["Layer 2"]
        XCTAssertTrue(layer2.waitForExistence(timeout: 15))

        // A firm leftward drag across the row (starting in the spacer, away from the
        // trailing buttons). The short 0.12s press stays under the 0.22s reorder
        // long-press, so this reads as a delete-swipe, not a reorder. Layer 2 is
        // empty, so it deletes without a confirmation dialog.
        let anchor = layer2.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let start = anchor.withOffset(CGVector(dx: 70, dy: 0))
        let end = anchor.withOffset(CGVector(dx: -170, dy: 0))
        start.press(forDuration: 0.12, thenDragTo: end)

        XCTAssertFalse(layer2.waitForExistence(timeout: 3),
                       "Swiping a row left should delete that layer")
        XCTAssertTrue(app.staticTexts["Layer 1"].exists)
    }

    func testVisibilityAndLockTogglesPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Create a fresh 32×32 piece.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // Open the layers panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()
        XCTAssertTrue(app.staticTexts["Layer 1"].waitForExistence(timeout: 15))

        // The eye/lock controls are now custom pixel glyphs (no SF Symbol name to
        // query), so the row exposes stable identifiers plus an accessibilityValue
        // that flips with state.
        let visibility = app.buttons["LayerRow-visibility"].firstMatch
        let lock = app.buttons["LayerRow-lock"].firstMatch
        XCTAssertTrue(visibility.waitForExistence(timeout: 15))
        XCTAssertEqual(visibility.value as? String, "visible")
        XCTAssertEqual(lock.value as? String, "unlocked")

        // Toggle visibility: visible → hidden.
        visibility.tap()
        XCTAssertTrue(waitForValue(visibility, "hidden"))

        // Toggle lock: unlocked → locked.
        lock.tap()
        XCTAssertTrue(waitForValue(lock, "locked"))

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
        XCTAssertTrue(waitForValue(app.buttons["LayerRow-visibility"].firstMatch, "hidden"))
        XCTAssertTrue(waitForValue(app.buttons["LayerRow-lock"].firstMatch, "locked"))
    }

    /// Poll an element's accessibilityValue until it matches (a11y value updates
    /// arrive on a SwiftUI rebuild after the tap, so a single read can race it).
    private func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.value as? String == expected { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return element.value as? String == expected
    }
}
