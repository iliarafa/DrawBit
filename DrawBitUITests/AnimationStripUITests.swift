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
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()

        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // FramesStrip is hidden by default for a new (single-frame) piece.
        // ANIMATE both reveals the strip and seeds the second frame.
        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 15))
        animate.tap()

        let add = app.buttons["FramesStrip.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 15),
                      "FramesStrip.add must be visible after tapping ANIMATE")

        // ANIMATE seeded one extra frame (total: 2). Add two more (total: 4).
        add.tap()
        add.tap()

        // FrameRow views have accessibilityIdentifier "FrameRow.<UUID>" and the
        // .isButton trait, so XCTest surfaces them as buttons.
        let frameRowsPredicate = NSPredicate(format: "identifier BEGINSWITH 'FrameRow.'")
        let frameButtons = app.buttons.matching(frameRowsPredicate)
        // Poll for the row count to settle — FrameRow insertion + thumbnail render is
        // async, so a single read right after .tap() races the SwiftUI rebuild. The
        // sibling tests (testAnimateButtonAddsFrameRevealsTimelineAndPreservesFramesOnHide,
        // testAddInsertsBlankFrame) use this same poll; this one was missing it.
        var countAfterAdds = frameButtons.count
        for _ in 0..<50 where countAfterAdds < 3 {
            Thread.sleep(forTimeInterval: 0.1)
            countAfterAdds = frameButtons.count
        }
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
        XCTAssertTrue(app.buttons["Gallery"].waitForExistence(timeout: 15))
        app.buttons["Gallery"].tap()

        XCTAssertTrue(app.buttons["PieceThumbnail"].waitForExistence(timeout: 10))
        app.buttons["PieceThumbnail"].firstMatch.tap()

        // Reopened — the piece now has ≥2 frames, so the strip auto-shows.
        XCTAssertTrue(add.waitForExistence(timeout: 15),
                      "FramesStrip.add must be visible after reopening a multi-frame piece")
        let frameButtonsAfterReopen = app.buttons.matching(frameRowsPredicate)
        var reopenCount = frameButtonsAfterReopen.count
        for _ in 0..<50 where reopenCount < 3 {
            Thread.sleep(forTimeInterval: 0.1)
            reopenCount = frameButtonsAfterReopen.count
        }
        XCTAssertGreaterThanOrEqual(reopenCount, 3,
                                    "Frame count must persist across editor sessions")
    }

    func testOnionSkinToggleGatedAndNotPersisted() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Create a fresh 32×32 piece.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // FramesStrip is hidden by default. ANIMATE reveals it and seeds frame 2;
        // active frame becomes #2 (FrameSequence.addFrameAfter selects the new one).
        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 15))
        animate.tap()

        let onion = app.buttons["FramesStrip.onionSkin"]
        XCTAssertTrue(onion.waitForExistence(timeout: 15))

        // We landed on frame 1, so onion is enabled. Switch back to frame 0 to
        // verify the gate ("disabled when no previous frame to ghost").
        let frameRowsPredicate = NSPredicate(format: "identifier BEGINSWITH 'FrameRow.'")
        let frameButtons = app.buttons.matching(frameRowsPredicate)
        frameButtons.element(boundBy: 0).tap()
        var disabled = false
        for _ in 0..<50 {
            if !onion.isEnabled { disabled = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(disabled, "onion skin must be disabled at frame 0")

        // Switch back to frame 1; onion should re-enable.
        frameButtons.element(boundBy: 1).tap()
        var enabled = false
        for _ in 0..<50 {
            if onion.isEnabled { enabled = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(enabled, "onion skin must become enabled once active frame index > 0")

        // Toggle on, then leave the editor and re-open.
        onion.tap()

        XCTAssertTrue(app.buttons["Gallery"].waitForExistence(timeout: 15))
        app.buttons["Gallery"].tap()
        XCTAssertTrue(app.buttons["PieceThumbnail"].waitForExistence(timeout: 10))
        app.buttons["PieceThumbnail"].firstMatch.tap()

        // Reopened — piece has 2 frames so the strip auto-shows. Active frame is
        // the last-saved one (frame 1), and onion skin must have reset to off
        // because EditorState.isOnionSkinEnabled is display-only and not persisted.
        XCTAssertTrue(onion.waitForExistence(timeout: 15))
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

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // ANIMATE button must exist and be the entry point — strip itself must NOT.
        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 15),
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

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 15))

        // First tap: reveal strip + seed a 2nd frame.
        animate.tap()

        let add = app.buttons["FramesStrip.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 15),
                      "FramesStrip.add must appear after first ANIMATE tap")

        let frameRowsPredicate = NSPredicate(format: "identifier BEGINSWITH 'FrameRow.'")
        let frameButtons = app.buttons.matching(frameRowsPredicate)
        // Poll briefly — view rebuild after addFrame can take a moment.
        var sawTwoRows = false
        for _ in 0..<50 {
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
        XCTAssertTrue(app.buttons["Gallery"].waitForExistence(timeout: 15))
        app.buttons["Gallery"].tap()

        XCTAssertTrue(app.buttons["PieceThumbnail"].waitForExistence(timeout: 10))
        app.buttons["PieceThumbnail"].firstMatch.tap()

        XCTAssertTrue(add.waitForExistence(timeout: 15),
                      "Strip must auto-show on reopen for a multi-frame piece (no ANIMATE tap needed)")
        let rowsAfterReopen = app.buttons.matching(frameRowsPredicate)
        XCTAssertGreaterThanOrEqual(rowsAfterReopen.count, 2,
                                    "Both frames must persist after ANIMATE-then-hide-then-reopen")
    }

    func testEditModeToggleIsGone() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 15))
        animate.tap()

        XCTAssertTrue(app.buttons["FramesStrip.add"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["FramesStrip.editToggle"].exists,
                       "EDIT mode toggle must be removed from the strip")
    }

    func testAddInsertsBlankFrame() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 15))
        animate.tap()

        let add = app.buttons["FramesStrip.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))

        let frameRowsPredicate = NSPredicate(format: "identifier BEGINSWITH 'FrameRow.'")
        let before = app.buttons.matching(frameRowsPredicate).count
        add.tap()
        var grew = false
        for _ in 0..<50 {
            if app.buttons.matching(frameRowsPredicate).count > before { grew = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(grew, "ADD must insert a new frame row")
        // Behavioral note: blank-vs-copy pixel content is asserted at the unit level
        // (FrameSequenceTests.testAddBlankFrameAfterInsertsEmptyFrame); the UI test
        // only verifies the button inserts a frame.
    }

    func testDuplicateBadgeOnSelectedFrameAddsCopy() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 15))
        animate.tap()

        let frameRowsPredicate = NSPredicate(format: "identifier BEGINSWITH 'FrameRow.'")
        let frameButtons = app.buttons.matching(frameRowsPredicate)
        var rowCount = frameButtons.count
        for _ in 0..<50 where rowCount < 2 {
            Thread.sleep(forTimeInterval: 0.1)
            rowCount = frameButtons.count
        }
        XCTAssertGreaterThanOrEqual(rowCount, 2, "ANIMATE must seed a 2nd frame")
        let countBefore = frameButtons.count

        // The duplicate glyph is shown only on the selected frame — exactly one.
        let duplicate = app.buttons["FrameDuplicateButton"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 15),
                      "Selected frame must show a duplicate glyph")
        XCTAssertEqual(app.buttons.matching(identifier: "FrameDuplicateButton").count, 1,
                       "Only the selected frame shows the duplicate glyph — not every frame")

        duplicate.tap()
        var grew = false
        for _ in 0..<50 {
            if frameButtons.count > countBefore { grew = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(grew, "Tapping the duplicate glyph must insert a copy of the frame")
    }

    func testDeleteBadgeOnSelectedFrameRemovesIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // ANIMATE reveals the strip and seeds a 2nd frame (total: 2). The active
        // frame becomes the new one, so exactly one delete × is shown.
        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 15))
        animate.tap()

        let add = app.buttons["FramesStrip.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))

        let frameRowsPredicate = NSPredicate(format: "identifier BEGINSWITH 'FrameRow.'")
        let frameButtons = app.buttons.matching(frameRowsPredicate)
        var rowCount = frameButtons.count
        for _ in 0..<50 where rowCount < 2 {
            Thread.sleep(forTimeInterval: 0.1)
            rowCount = frameButtons.count
        }
        XCTAssertGreaterThanOrEqual(rowCount, 2, "ANIMATE must seed a 2nd frame")

        // The delete × is shown only on the selected frame, so with 2 frames there
        // must be exactly one — never one per frame.
        let deleteBadge = app.buttons["FrameDeleteButton"]
        XCTAssertTrue(deleteBadge.waitForExistence(timeout: 15),
                      "Selected frame must show a delete × once there are ≥2 frames")
        XCTAssertEqual(app.buttons.matching(identifier: "FrameDeleteButton").count, 1,
                       "Only the selected frame shows the delete × — not every frame")

        // The seeded frame is blank, so delete is immediate (no confirm dialog).
        deleteBadge.tap()
        var droppedToOne = false
        for _ in 0..<50 {
            if frameButtons.count <= 1 { droppedToOne = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(droppedToOne, "Tapping the delete × must remove the frame")

        // Last remaining frame must not show a delete × (guarded by frameCount > 1).
        XCTAssertFalse(app.buttons["FrameDeleteButton"].waitForExistence(timeout: 1),
                       "A single-frame sequence must show no delete ×")
    }

    func testFPSButtonCyclesSpeedOnTap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 15))
        animate.tap()

        let fps = app.buttons["FramesStrip.fps"]
        XCTAssertTrue(fps.waitForExistence(timeout: 15))

        // Tapping the icon cycles the playback speed (no popup opens). Six speeds → six taps
        // advance through all of them and wrap back to the start.
        let start = fps.value as? String
        var prev = start
        for _ in 0..<6 {
            fps.tap()
            XCTAssertTrue(waitUntilValueChanges(fps, from: prev ?? ""),
                          "each tap on the FPS icon must advance the speed")
            prev = fps.value as? String
        }
        XCTAssertEqual(fps.value as? String, start,
                       "cycling through all six speeds wraps back to the start")
    }

    func testAddDisabledDuringPlayback() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-create"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-create"].tap()

        // ANIMATE reveals the strip and seeds a 2nd frame, so Play is enabled.
        let animate = app.buttons["Animate"]
        XCTAssertTrue(animate.waitForExistence(timeout: 15))
        animate.tap()

        let add = app.buttons["FramesStrip.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        XCTAssertTrue(add.isEnabled, "ADD must be enabled when not playing")

        // Start playback — every edit control (ADD included) must go disabled.
        let play = app.buttons["FramesStrip.playPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        play.tap()

        var disabled = false
        for _ in 0..<50 {
            if !add.isEnabled { disabled = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(disabled, "ADD must be disabled during playback, like every other edit control")
    }

    /// Polls until the element's `value` differs from `old` — a read right after `.tap()` races the
    /// SwiftUI rebuild (per CLAUDE.md).
    private func waitUntilValueChanges(_ element: XCUIElement, from old: String,
                                       timeout: TimeInterval = 4) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) != old { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return (element.value as? String) != old
    }
}
