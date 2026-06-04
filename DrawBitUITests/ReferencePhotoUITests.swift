import XCTest

final class ReferencePhotoUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testReferenceRowAppearsInLayersPanel() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
        app.launch()

        // Create a fresh 32x32 piece from the gallery.
        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 15))
        app.buttons["NewButton"].tap()
        XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 15))
        app.buttons["NewPiece-32"].tap()

        // Open the layers panel.
        XCTAssertTrue(app.buttons["LAYERS"].waitForExistence(timeout: 15))
        app.buttons["LAYERS"].tap()

        // The reference row container is present. The VStack identifier surfaces via
        // descendants() — PhotosPicker inside it overrides the parent identifier on
        // the button element, so we use the broader descendants query here.
        XCTAssertTrue(app.descendants(matching: .any)["ReferenceRow"].waitForExistence(timeout: 15))

        // The empty-state picker affordance is present. PhotosPicker doesn't propagate
        // .accessibilityIdentifier through the UIKit bridge, so the button is matched by
        // its human-readable .accessibilityLabel, which is "Add reference photo" while no
        // reference exists (it becomes "Replace reference photo" once one is set).
        XCTAssertTrue(app.buttons["Add reference photo"].waitForExistence(timeout: 15))

        // With no reference yet, the remove/toggle controls are absent.
        XCTAssertFalse(app.buttons["Reference-remove"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["Reference-toggle"].waitForExistence(timeout: 1))
    }
}
