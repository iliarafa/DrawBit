import XCTest

/// `HelpScreen` is the in-app help reference pushed from the `?` button in
/// the gallery's `GALLERY` header. These tests verify the button is
/// discoverable, the screen pushes when tapped, and all six section
/// headings render.
final class HelpScreenUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launchAndOpenHelp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        let button = app.buttons["Help.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Help button must exist in the gallery header")
        button.tap()

        // The pushed help screen's TOOLS section heading uniquely identifies
        // the destination — `Help.section.tools` is set only on `HelpScreen`.
        XCTAssertTrue(app.staticTexts["Help.section.tools"].waitForExistence(timeout: 15),
                      "Help screen must push when the ? button is tapped")
        return app
    }

    func testHelpButtonIsVisibleInGallery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["Help.button"].waitForExistence(timeout: 15),
                      "? button must appear in the GALLERY header")
        XCTAssertEqual(app.buttons["Help.button"].label, "Help")
    }

    func testTappingHelpButtonPushesHelpScreen() throws {
        _ = launchAndOpenHelp()
        // launchAndOpenHelp already asserts the destination pushed. The
        // explicit test makes the contract obvious to a reader scanning the
        // test class.
    }

    func testAllSectionHeadingsRender() throws {
        let app = launchAndOpenHelp()

        // Six sections in order; their identifiers were set only on the
        // heading Text views in `HelpScreen`. Tools renders at the top of
        // the page; the remaining five are below and become visible after
        // scrolling, but since the screen is a single ScrollView with all
        // children eagerly laid out (a VStack, not a List), every heading
        // is in the accessibility tree from the moment the screen appears.
        let ids = [
            "Help.section.tools",
            "Help.section.canvas",
            "Help.section.layers",
            "Help.section.animation",
            "Help.section.export",
            "Help.section.fm",
        ]
        for id in ids {
            XCTAssertTrue(app.staticTexts[id].exists,
                          "Help screen must show section heading: \(id)")
        }
    }
}
