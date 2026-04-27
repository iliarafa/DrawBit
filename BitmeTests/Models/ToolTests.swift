import XCTest
@testable import Bitme

final class ToolTests: XCTestCase {
    func testAllCases() {
        XCTAssertEqual(Tool.allCases, [.pencil, .eraser, .fill, .eyedropper, .marquee])
    }

    func testSFSymbolNames() {
        XCTAssertEqual(Tool.pencil.sfSymbol, "pencil")
        XCTAssertEqual(Tool.eraser.sfSymbol, "eraser")
        XCTAssertEqual(Tool.fill.sfSymbol, "drop.fill")
        XCTAssertEqual(Tool.eyedropper.sfSymbol, "eyedropper")
        XCTAssertEqual(Tool.marquee.sfSymbol, "rectangle.dashed")
    }
}
