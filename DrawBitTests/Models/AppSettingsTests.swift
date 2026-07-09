import XCTest
@testable import DrawBit

final class AppSettingsTests: XCTestCase {
    func testPrependKeepsUnique() {
        let s = AppSettings()
        s.addRecentColor("#FF0000")
        s.addRecentColor("#00FF00")
        s.addRecentColor("#FF0000")
        XCTAssertEqual(s.recentColors, ["#FF0000", "#00FF00"])
    }

    func testCapAtLimitDropsOldest() {
        let s = AppSettings()
        // limit defaults to 23; insert 30 distinct colors and verify the oldest are dropped.
        for i in 0..<30 {
            s.addRecentColor(String(format: "#%06X", i))
        }
        XCTAssertEqual(s.recentColors.count, 23)
        // Newest is at index 0 (prepended), oldest retained is the 8th-from-last (#000007).
        XCTAssertEqual(s.recentColors.first, "#00001D")
        XCTAssertEqual(s.recentColors.last, "#000007")
    }

    // MARK: - Grid intensity (persisted global viewing preference)

    func testGridIntensityDefaultsToSoft() {
        XCTAssertEqual(AppSettings().gridIntensity, .soft)
    }

    func testGridIntensityRoundTripsThroughRawStorage() {
        let s = AppSettings()
        s.gridIntensity = .off
        XCTAssertEqual(s.gridIntensityRaw, GridIntensity.off.rawValue)
        XCTAssertEqual(s.gridIntensity, .off)
        s.gridIntensity = .strong
        XCTAssertEqual(s.gridIntensity, .strong)
    }
}
