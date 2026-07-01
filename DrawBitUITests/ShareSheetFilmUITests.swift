import XCTest

/// The FILM (time-lapse) export tile: disabled on a fresh draw with no recorded
/// process, enabled once a few strokes have been recorded. Deliberately does NOT
/// tap EXPORT — that presents the system share sheet, which is flaky to drive.
final class ShareSheetFilmUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testFilmTileDisabledOnFreshDrawEnabledAfterDrawing() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Fresh piece.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // Open export — FILM tile exists but is disabled (nothing recorded yet).
        XCTAssertTrue(app.buttons["SHARE"].waitForExistence(timeout: 15))
        app.buttons["SHARE"].tap()
        let filmTile = app.buttons["ShareSheet.format.film"]
        XCTAssertTrue(filmTile.waitForExistence(timeout: 15))
        XCTAssertFalse(filmTile.isEnabled, "FILM should be disabled on a fresh draw")

        // Dismiss the sheet and draw a few dots so the recorder captures keyframes.
        app.buttons["ShareSheet.cancel"].tap()
        let canvas = app.otherElements["Canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        for (dx, dy) in [(0.35, 0.35), (0.5, 0.5), (0.65, 0.65), (0.4, 0.6)] {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        }

        // Reopen export — FILM should now be enabled.
        XCTAssertTrue(app.buttons["SHARE"].waitForExistence(timeout: 15))
        app.buttons["SHARE"].tap()
        XCTAssertTrue(filmTile.waitForExistence(timeout: 15))
        var enabled = false
        for _ in 0..<50 {
            if filmTile.isEnabled { enabled = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(enabled, "FILM should enable once strokes are recorded")
    }
}
