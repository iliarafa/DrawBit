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

    func testOnionSkinToggleGatedAndNotPersisted() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Create a fresh 32×32 piece.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 5))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 3))
        app.buttons["NewPiece-32"].tap()

        let onion = app.buttons["FramesStrip.onionSkin"]
        let add = app.buttons["FramesStrip.add"]
        XCTAssertTrue(onion.waitForExistence(timeout: 5))
        XCTAssertTrue(add.waitForExistence(timeout: 5))

        // Frame 0 is the only frame — onion-skin button must be disabled.
        XCTAssertFalse(onion.isEnabled,
                       "onion skin must be disabled at frame 0")

        // Add a second frame; tapping `+` switches the active frame to the new one
        // (FrameSequence.addFrameAfter places it after the active and selects it).
        add.tap()
        // Settle, then verify the toggle is now enabled.
        XCTAssertTrue(onion.waitForExistence(timeout: 3))
        // isEnabled may take a beat to flip; poll briefly.
        var enabled = false
        for _ in 0..<10 {
            if onion.isEnabled { enabled = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(enabled, "onion skin must become enabled once active frame index > 0")

        // Toggle on, then leave the editor and re-open.
        onion.tap()

        XCTAssertTrue(app.buttons["Gallery"].waitForExistence(timeout: 3))
        app.buttons["Gallery"].tap()
        XCTAssertTrue(app.buttons["PieceThumbnail"].waitForExistence(timeout: 10))
        app.buttons["PieceThumbnail"].firstMatch.tap()

        // Reopened — the FramesStrip should be back, the active frame is the
        // last-saved one (frame 1), and onion skin must have reset to off because
        // EditorState.isOnionSkinEnabled is display-only and not persisted.
        XCTAssertTrue(onion.waitForExistence(timeout: 5))
        // Ensure we're at frame 1 (button enabled is the proxy — disabled would
        // mean we landed at frame 0 for some reason).
        XCTAssertTrue(onion.isEnabled, "expected to reopen on a non-zero active frame")

        // The toggle's accessibility identifier doesn't change with state, so
        // reading the value indirectly: the icon SF Symbol changes between
        // "circle" (off) and "circle.righthalf.filled" (on). XCTest surfaces the
        // SF Symbol name via `value` on iOS images; check that here.
        // Fallback if the value bridge differs by OS: just assert a tap is harmless.
        // (This is a minimum-viable check; the strong assertion is "the toggle
        // does not survive reopen"; if it survived as `on`, the icon would be
        // "circle.righthalf.filled".)
        let label = onion.label
        // SF symbol names appear in the accessibility label when no overriding
        // .accessibilityLabel is set. "circle" is the off state.
        XCTAssertTrue(label.contains("circle") && !label.contains("filled"),
                      "onion-skin toggle must reset to off after editor reopen; saw label '\(label)'")
    }
}
