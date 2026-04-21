import XCTest

final class LandingScreenTests: XCTestCase {
    private func landingStart(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "LandingStart").firstMatch
    }

    func testStartTapEntersGallery() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset"]
        app.launch()

        let start = landingStart(app)
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 3))
    }
}
