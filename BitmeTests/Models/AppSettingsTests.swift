import XCTest
@testable import Bitme

final class AppSettingsTests: XCTestCase {
    func testPrependKeepsUnique() {
        let s = AppSettings()
        s.addRecentColor("#FF0000")
        s.addRecentColor("#00FF00")
        s.addRecentColor("#FF0000")
        XCTAssertEqual(s.recentColors, ["#FF0000", "#00FF00"])
    }

    func testCapAt16() {
        let s = AppSettings()
        for i in 0..<20 {
            s.addRecentColor(String(format: "#%06X", i))
        }
        XCTAssertEqual(s.recentColors.count, 16)
        XCTAssertEqual(s.recentColors.first, "#000013")
    }
}
