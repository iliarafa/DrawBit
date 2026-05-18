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

        // FramesStrip is hidden by default for a new (single-frame) piece.
        // ANIMATE both reveals the strip and seeds the second frame.
        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 5))
        animate.tap()

        let add = app.buttons["FramesStrip.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "FramesStrip.add must be visible after tapping ANIMATE")

        // ANIMATE seeded one extra frame (total: 2). Add two more (total: 4).
        add.tap()
        add.tap()

        // FrameRow views have accessibilityIdentifier "FrameRow.<UUID>" and the
        // .isButton trait, so XCTest surfaces them as buttons.
        let frameRowsPredicate = NSPredicate(format: "identifier BEGINSWITH 'FrameRow.'")
        let frameButtons = app.buttons.matching(frameRowsPredicate)
        // Give the UI time to settle after the additions.
        let countAfterAdds = frameButtons.count
        XCTAssertGreaterThanOrEqual(countAfterAdds, 3,
                                    "Should have at least 3 frame rows after ANIMATE + two adds")

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

        // Reopened — the piece now has ≥2 frames, so the strip auto-shows.
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "FramesStrip.add must be visible after reopening a multi-frame piece")
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

        // FramesStrip is hidden by default. ANIMATE reveals it and seeds frame 2;
        // active frame becomes #2 (FrameSequence.addFrameAfter selects the new one).
        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 5))
        animate.tap()

        let onion = app.buttons["FramesStrip.onionSkin"]
        XCTAssertTrue(onion.waitForExistence(timeout: 5))

        // We landed on frame 1, so onion is enabled. Switch back to frame 0 to
        // verify the gate ("disabled when no previous frame to ghost").
        let frameRowsPredicate = NSPredicate(format: "identifier BEGINSWITH 'FrameRow.'")
        let frameButtons = app.buttons.matching(frameRowsPredicate)
        frameButtons.element(boundBy: 0).tap()
        var disabled = false
        for _ in 0..<10 {
            if !onion.isEnabled { disabled = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(disabled, "onion skin must be disabled at frame 0")

        // Switch back to frame 1; onion should re-enable.
        frameButtons.element(boundBy: 1).tap()
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

        // Reopened — piece has 2 frames so the strip auto-shows. Active frame is
        // the last-saved one (frame 1), and onion skin must have reset to off
        // because EditorState.isOnionSkinEnabled is display-only and not persisted.
        XCTAssertTrue(onion.waitForExistence(timeout: 5))
        XCTAssertTrue(onion.isEnabled, "expected to reopen on a non-zero active frame")

        // The toggle's accessibility label encodes the state explicitly
        // ("Onion skin off" / "Onion skin on") so the test reads it directly.
        XCTAssertEqual(onion.label, "Onion skin off",
                       "onion-skin toggle must reset to off after editor reopen; saw label '\(onion.label)'")
    }

    // MARK: - ANIMATE toggle (timeline visibility)

    func testTimelineHiddenByDefaultForNewPiece() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 5))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 3))
        app.buttons["NewPiece-32"].tap()

        // ANIMATE button must exist and be the entry point — strip itself must NOT.
        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 5),
                      "ANIMATE button must exist in the top bar")

        let add = app.buttons["FramesStrip.add"]
        XCTAssertFalse(add.exists,
                       "FramesStrip must be hidden by default for a fresh single-frame piece")

        let onion = app.buttons["FramesStrip.onionSkin"]
        XCTAssertFalse(onion.exists,
                       "FramesStrip controls must not be present when the strip is hidden")
    }

    func testAnimateButtonAddsFrameRevealsTimelineAndPreservesFramesOnHide() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 5))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 3))
        app.buttons["NewPiece-32"].tap()

        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 5))

        // First tap: reveal strip + seed a 2nd frame.
        animate.tap()

        let add = app.buttons["FramesStrip.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "FramesStrip.add must appear after first ANIMATE tap")

        let frameRowsPredicate = NSPredicate(format: "identifier BEGINSWITH 'FrameRow.'")
        let frameButtons = app.buttons.matching(frameRowsPredicate)
        // Poll briefly — view rebuild after addFrame can take a moment.
        var sawTwoRows = false
        for _ in 0..<10 {
            if frameButtons.count >= 2 { sawTwoRows = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(sawTwoRows,
                      "First ANIMATE tap must seed a 2nd frame; got \(frameButtons.count) rows")

        // Second tap: hide strip. Frames stay in the model.
        animate.tap()
        XCTAssertFalse(add.waitForExistence(timeout: 1),
                       "FramesStrip.add must disappear when ANIMATE is toggled off")

        // Persistence: reopen the piece. Both frames must still be there, and
        // because frames.count > 1 the strip must auto-show without any tap.
        XCTAssertTrue(app.buttons["Gallery"].waitForExistence(timeout: 3))
        app.buttons["Gallery"].tap()

        XCTAssertTrue(app.buttons["PieceThumbnail"].waitForExistence(timeout: 10))
        app.buttons["PieceThumbnail"].firstMatch.tap()

        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "Strip must auto-show on reopen for a multi-frame piece (no ANIMATE tap needed)")
        let rowsAfterReopen = app.buttons.matching(frameRowsPredicate)
        XCTAssertGreaterThanOrEqual(rowsAfterReopen.count, 2,
                                    "Both frames must persist after ANIMATE-then-hide-then-reopen")
    }
}
