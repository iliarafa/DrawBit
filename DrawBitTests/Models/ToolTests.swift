import XCTest
@testable import DrawBit

final class ToolTests: XCTestCase {
    func testAllCases() {
        XCTAssertEqual(Tool.allCases, [.pencil, .eraser, .fill, .colorSwap, .eyedropper, .marquee])
    }

    func testSFSymbolNames() {
        XCTAssertEqual(Tool.pencil.sfSymbol, "pencil")
        XCTAssertEqual(Tool.eraser.sfSymbol, "eraser")
        XCTAssertEqual(Tool.fill.sfSymbol, "drop.fill")
        XCTAssertEqual(Tool.colorSwap.sfSymbol, "arrow.left.arrow.right")
        XCTAssertEqual(Tool.eyedropper.sfSymbol, "eyedropper")
        XCTAssertEqual(Tool.marquee.sfSymbol, "rectangle.dashed")
    }
}
