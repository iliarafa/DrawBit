import XCTest

/// Tapping an already-selected pencil/eraser cycles its brush size; the size is exposed as the
/// button's accessibility value, and the glyph (the nib square) grows with it.
final class ToolBarBrushSizeUITests: XCTestCase {
    private let shotDir = "/private/tmp/claude-501/-Users-iliasrafailidis-development-bitme/a3013f43-a0bf-4a7d-9d10-f65198e741e1/scratchpad"

    func testTapSelectedPencilCyclesSizeAndStaysIndependentFromEraser() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // New draw → editor (pencil is the default selected tool).
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()
        XCTAssertTrue(app.otherElements["Canvas"].firstMatch.waitForExistence(timeout: 15))

        let pencil = app.buttons["Tool-pencil"]
        XCTAssertTrue(pencil.waitForExistence(timeout: 15))
        XCTAssertEqual(pencil.value as? String, "1")        // default size
        saveShot("toolbar-pencil-size1")

        pencil.tap()                                        // already selected → cycle
        XCTAssertTrue(waitForValue(pencil, "2"), "pencil should cycle to 2")
        pencil.tap()
        XCTAssertTrue(waitForValue(pencil, "3"), "pencil should cycle to 3")
        saveShot("toolbar-pencil-size3")

        // Per-tool independence: the eraser kept its own size.
        XCTAssertEqual(app.buttons["Tool-eraser"].value as? String, "1")

        // Wrap 3 → 4 → 1.
        pencil.tap()
        XCTAssertTrue(waitForValue(pencil, "4"), "pencil should cycle to 4")
        pencil.tap()
        XCTAssertTrue(waitForValue(pencil, "1"), "pencil should wrap to 1")
    }

    /// The size updates on an async SwiftUI rebuild, so poll rather than read once (per CLAUDE.md).
    private func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) == expected { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return (element.value as? String) == expected
    }

    private func saveShot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "\(shotDir)/\(name).png"))
    }
}
