import XCTest

/// `HelpScreen` is the in-app help reference pushed from the `?` button in
/// the gallery's `GALLERY` header. These tests verify the button is
/// discoverable, the screen pushes when tapped, all ten section headings
/// render, and the landscape contract holds: the back chip stays pinned
/// on screen and the grid scrolls when the viewport can't fit it.
final class HelpScreenUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    override func tearDown() {
        // Orientation is a simulator-level property that persists across app
        // launches within a test run, and the rest of the suite assumes
        // portrait. This must live in tearDown, not at the end of the test
        // body: continueAfterFailure = false aborts a test at its failing
        // assert, so in-body restore code is skipped exactly when it matters.
        XCUIDevice.shared.orientation = .portrait
    }

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

    /// Regression: rotating to landscape used to compress the fixed VStack —
    /// the back chip was pushed off the top of the screen and the last grid
    /// row below the bottom, with no way to scroll (no ScrollView).
    func testLandscapeKeepsBackChipVisibleAndAboutReachable() throws {
        let app = launchAndOpenHelp()

        // Unique here: FMScreen/EditorView's "Gallery" buttons aren't presented,
        // and the gallery header's GALLERY text is a plain staticText.
        let back = app.buttons["Gallery"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        XCTAssertTrue(back.isHittable, "precondition: back chip hittable in portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        // Rotation re-layout is async and isHittable doesn't auto-wait; poll
        // until the window is wider than tall before asserting layout.
        let window = app.windows.firstMatch
        for _ in 0..<50 where window.frame.width <= window.frame.height {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(window.frame.width > window.frame.height, "must be landscape")

        // The back chip is pinned chrome — it must never be pushed off-screen.
        XCTAssertTrue(back.isHittable, "back chip must stay visible in landscape")

        // The eager Grid keeps every heading in the accessibility tree even
        // below the fold...
        let about = app.staticTexts["Help.section.about"]
        XCTAssertTrue(about.exists, "eager Grid keeps ABOUT in the tree off-screen")

        // ...and the content scrolls so the last row becomes reachable.
        var swipes = 0
        while !about.isHittable && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(about.isHittable, "ABOUT must be reachable by scrolling")
    }

    func testAllSectionHeadingsRender() throws {
        let app = launchAndOpenHelp()

        // Ten sections; their identifiers were set only on the heading Text
        // views in `HelpScreen`. The screen lays out every tile eagerly (a
        // VStack grid, not a List), so every heading is in the accessibility
        // tree from the moment the screen appears.
        let ids = [
            "Help.section.gallery",
            "Help.section.colours",
            "Help.section.tools",
            "Help.section.canvas",
            "Help.section.layers",
            "Help.section.trace",
            "Help.section.animation",
            "Help.section.export",
            "Help.section.fm",
            "Help.section.about",
        ]
        for id in ids {
            XCTAssertTrue(app.staticTexts[id].exists,
                          "Help screen must show section heading: \(id)")
        }
    }
}
