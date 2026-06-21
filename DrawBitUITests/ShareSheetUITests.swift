import XCTest

/// Light coverage of the redesigned export sheet: the hero preview + controls are present and
/// switching format updates the smart-preview badge. Deliberately does NOT tap EXPORT — that
/// presents the system `UIActivityViewController`, which is flaky to drive in XCUITest.
final class ShareSheetUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testShareSheetShowsPreviewAndControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Fresh 32x32 piece.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-32"].tap()

        // Open the export sheet.
        XCTAssertTrue(app.buttons["SHARE"].waitForExistence(timeout: 15))
        app.buttons["SHARE"].tap()

        // Controls + the big EXPORT button are present.
        XCTAssertTrue(app.buttons["ShareSheet.format.png"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["ShareSheet.scale.32"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["ShareSheet.export"].waitForExistence(timeout: 15))

        // The hero preview collapses to one a11y element whose label is the smart badge text.
        // Its existence proves the preview rendered; the label proves the format-aware badge.
        let preview = app.staticTexts["ExportPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        XCTAssertTrue(preview.label.hasPrefix("PNG"), "expected PNG badge, got '\(preview.label)'")

        // Switching to GIF updates the badge.
        app.buttons["ShareSheet.format.gif"].tap()
        var label = ""
        for _ in 0..<50 {
            label = app.staticTexts["ExportPreview"].label
            if label.hasPrefix("GIF") { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(label.hasPrefix("GIF"), "badge should switch to GIF, got '\(label)'")
    }
}
