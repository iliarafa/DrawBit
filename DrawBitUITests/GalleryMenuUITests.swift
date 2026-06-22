import XCTest

/// Covers the gallery piece's themed long-press menu (Rename / Duplicate / Delete),
/// which replaced the native `.contextMenu`.
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

    func testLongPressOpensThemedMenuAndDuplicates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        makePieceAndReturnToGallery(app)

        let pieces = app.buttons.matching(identifier: "PieceThumbnail")
        XCTAssertEqual(pieces.count, 1, "Exactly one piece to start")

        // Long-press the tile to open the custom popover (gallery tiles have no drag
        // gesture, so the long press is free to drive the menu).
        pieces.firstMatch.press(forDuration: 0.6)

        let duplicate = app.buttons["PieceMenu.duplicate"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 15),
                      "Long-press must open the themed piece menu")
        // All three actions present.
        XCTAssertTrue(app.buttons["PieceMenu.rename"].exists)
        XCTAssertTrue(app.buttons["PieceMenu.delete"].exists)

        duplicate.tap()

        var grew = false
        for _ in 0..<50 {
            if pieces.count >= 2 { grew = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(grew, "Duplicate must add a second piece")
    }

    func testDeleteFromMenuOpensConfirmSheetAndRemovesPiece() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        makePieceAndReturnToGallery(app)
        let pieces = app.buttons.matching(identifier: "PieceThumbnail")
        XCTAssertEqual(pieces.count, 1)

        pieces.firstMatch.press(forDuration: 0.6)

        let deleteRow = app.buttons["PieceMenu.delete"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 15))
        deleteRow.tap()

        // The menu must hand off cleanly to the existing themed confirm sheet
        // (this also proves the popover-dismiss → sheet-present sequence doesn't race).
        XCTAssertTrue(app.staticTexts["DELETE PIECE?"].waitForExistence(timeout: 15),
                      "Delete row must present the DeletePieceSheet")

        // Confirm — the menu popover is gone, so the only "DELETE" button is the sheet's.
        app.buttons["DELETE"].tap()

        var removed = false
        for _ in 0..<50 {
            if pieces.count == 0 { removed = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(removed, "Confirming delete must remove the piece")
    }

    func testRenameFromMenuOpensSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        makePieceAndReturnToGallery(app)
        app.buttons.matching(identifier: "PieceThumbnail").firstMatch.press(forDuration: 0.6)

        let renameRow = app.buttons["PieceMenu.rename"]
        XCTAssertTrue(renameRow.waitForExistence(timeout: 15))
        renameRow.tap()

        XCTAssertTrue(app.staticTexts["RENAME"].waitForExistence(timeout: 15),
                      "Rename row must present the RenamePieceSheet")
    }
}
