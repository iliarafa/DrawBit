import XCTest
import UIKit
@testable import Bitme

final class PixelFontTests: XCTestCase {
    func testPressStart2PIsRegistered() {
        XCTAssertNotNil(
            UIFont(name: "PressStart2P-Regular", size: 12),
            "PressStart2P-Regular must be registered via Info.plist's UIAppFonts. Check project.yml INFOPLIST_KEY_UIAppFonts and that Bitme/Resources/Fonts/PressStart2P-Regular.ttf exists."
        )
    }
}
