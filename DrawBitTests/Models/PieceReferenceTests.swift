import XCTest
@testable import DrawBit

final class PieceReferenceTests: XCTestCase {
    func testNewPieceHasNoReferenceAndDefaultOpacity() {
        let piece = Piece(size: .s32)
        XCTAssertNil(piece.referenceImageData)
        XCTAssertEqual(piece.referenceOpacity, 0.35, accuracy: 0.0001)
    }
}
