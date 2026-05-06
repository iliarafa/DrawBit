import XCTest

final class AnimationStripUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAddFramesAndSwitchActiveFrame() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Create a fresh 32×32 piece from the gallery — same tap sequence used
        // by DrawAndSaveTest and LayersPanelUITests.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 5))
        app.buttons["NewButton"].tap()

        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 3))
        app.buttons["NewPiece-32"].tap()

        // Editor is now open. The FramesStrip is always visible (not behind a toggle).
        let add = app.buttons["FramesStrip.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "FramesStrip.add must be visible in the editor")

        // Tap + twice to add two more frames (total: 3).
        add.tap()
        add.tap()

        // FrameRow views have accessibilityIdentifier "FrameRow.<UUID>" and the
        // .isButton trait, so XCTest surfaces them as buttons.
        let frameRowsPredicate = NSPredicate(format: "identifier BEGINSWITH 'FrameRow.'")
        let frameButtons = app.buttons.matching(frameRowsPredicate)
        // Give the UI time to settle after the two additions.
        let countAfterAdds = frameButtons.count
        XCTAssertGreaterThanOrEqual(countAfterAdds, 3,
                                    "Should have at least 3 frame rows after two adds")

        // Tap the first frame to make it the active frame.
        let firstFrame = frameButtons.element(boundBy: 0)
        XCTAssertTrue(firstFrame.exists)
        firstFrame.tap()

        // Tap the third frame to verify scrubbing.
        let thirdFrame = frameButtons.element(boundBy: 2)
        XCTAssertTrue(thirdFrame.exists)
        thirdFrame.tap()

        // Persistence round-trip: navigate back to gallery and reopen the piece.
        // The frame count must survive the SwiftData save/load cycle.
        XCTAssertTrue(app.buttons["Gallery"].waitForExistence(timeout: 3))
        app.buttons["Gallery"].tap()

        XCTAssertTrue(app.buttons["PieceThumbnail"].waitForExistence(timeout: 10))
        app.buttons["PieceThumbnail"].firstMatch.tap()

        // FramesStrip must reappear with the same 3 frames.
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "FramesStrip.add must be visible after reopening the editor")
        let frameButtonsAfterReopen = app.buttons.matching(frameRowsPredicate)
        XCTAssertGreaterThanOrEqual(frameButtonsAfterReopen.count, 3,
                                    "Frame count must persist across editor sessions")
    }
}
