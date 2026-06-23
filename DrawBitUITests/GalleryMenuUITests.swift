import XCTest

/// Covers the gallery piece tile: tap opens the piece; long-press reveals on-tile
/// Duplicate / Delete chips (Rename was dropped).
final class GalleryMenuUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Create one 32×32 piece and return to the gallery so its thumbnail is visible.
    private func makePieceAndReturnToGallery(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-32"].tap()

        // Creating a piece pushes the editor; go back to the gallery.
        XCTAssertTrue(app.buttons["Gallery"].waitForExistence(timeout: 15))
        app.buttons["Gallery"].tap()
        XCTAssertTrue(app.buttons["PieceThumbnail"].firstMatch.waitForExistence(timeout: 15))
    }

    func testLongPressRevealsIconsAndDuplicates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        makePieceAndReturnToGallery(app)

        let pieces = app.buttons.matching(identifier: "PieceThumbnail")
        XCTAssertEqual(pieces.count, 1, "Exactly one piece to start")

        // Long-press reveals the on-tile chips (tiles have no drag gesture).
        pieces.firstMatch.press(forDuration: 0.6)

        let duplicate = app.buttons["PieceDuplicateButton"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 15),
                      "Long-press must reveal the Duplicate chip")
        XCTAssertTrue(app.buttons["PieceDeleteButton"].exists,
                      "Long-press must reveal the Delete chip")

        duplicate.tap()

        var grew = false
        for _ in 0..<50 {
            if pieces.count >= 2 { grew = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(grew, "Duplicate must add a second piece")
        // Tapping a chip must act in place, not open the editor.
        XCTAssertTrue(app.buttons["NewButton"].exists,
                      "Tapping a chip must not navigate into the editor")
    }

    func testDeleteIconOpensConfirmAndRemovesPiece() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        makePieceAndReturnToGallery(app)
        let pieces = app.buttons.matching(identifier: "PieceThumbnail")
        XCTAssertEqual(pieces.count, 1)

        pieces.firstMatch.press(forDuration: 0.6)

        let deleteChip = app.buttons["PieceDeleteButton"]
        XCTAssertTrue(deleteChip.waitForExistence(timeout: 15))
        deleteChip.tap()

        XCTAssertTrue(app.staticTexts["DELETE PIECE?"].waitForExistence(timeout: 15),
                      "Delete chip must present the DeletePieceSheet")

        app.buttons["DELETE"].tap()

        var removed = false
        for _ in 0..<50 {
            if pieces.count == 0 { removed = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(removed, "Confirming delete must remove the piece")
    }

    func testCustomSizeCreatesPiece() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()

        let field = app.textFields["NewPiece-dimField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "Size field must exist")
        field.tap()
        // Clear the existing value, then type a custom size.
        if let current = field.value as? String {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText("48")

        app.buttons["NewPiece-create"].tap()

        // The dialed custom size opens straight into the editor.
        XCTAssertTrue(app.buttons["Animate"].waitForExistence(timeout: 15),
                      "Creating a custom size must open the editor")
    }

    func testStepperNudgesTheSize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()

        let field = app.textFields["NewPiece-dimField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        XCTAssertEqual(field.value as? String, "32", "Dial starts at 32")
        app.buttons["NewPiece-plus"].tap()
        XCTAssertEqual(field.value as? String, "33", "Plus must nudge the size to 33")
    }

    func testTapOpensPiece() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        makePieceAndReturnToGallery(app)

        // A plain tap opens the editor (the ANIMATE control only exists there).
        app.buttons.matching(identifier: "PieceThumbnail").firstMatch.tap()
        XCTAssertTrue(app.buttons["Animate"].waitForExistence(timeout: 15),
                      "Tapping a tile must open the piece in the editor")
    }
}
