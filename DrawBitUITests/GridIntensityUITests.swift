import XCTest

/// The top-bar GRID button cycles the canvas grid intensity OFF → SOFT → STRONG (resting on SOFT),
/// exposing the level as its accessibility value. Keyed off the value, never the glyph (which swaps
/// between states) — per the "never query a button by its glyph" lesson.
final class GridIntensityUITests: XCTestCase {
    func testTapGridButtonCyclesIntensity() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // New draw → editor.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()
        XCTAssertTrue(app.otherElements["Canvas"].firstMatch.waitForExistence(timeout: 15))

        let grid = app.buttons["EditorView.gridIntensity"]
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        XCTAssertEqual(grid.value as? String, "soft")   // default: the calmer look ships out of the box

        grid.tap()
        XCTAssertTrue(waitForValue(grid, "strong"), "grid should cycle SOFT → STRONG")
        grid.tap()
        XCTAssertTrue(waitForValue(grid, "off"), "grid should cycle STRONG → OFF")
        grid.tap()
        XCTAssertTrue(waitForValue(grid, "soft"), "grid should wrap OFF → SOFT")
    }

    /// The value updates on an async SwiftUI rebuild, so poll rather than read once (per CLAUDE.md).
    private func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) == expected { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return (element.value as? String) == expected
    }
}
