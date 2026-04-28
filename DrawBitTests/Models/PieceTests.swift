import XCTest
import SwiftData
@testable import DrawBit

final class PieceTests: XCTestCase {
    func testNewPieceIsAllTransparent() {
        let piece = Piece(size: .s16)
        XCTAssertEqual(piece.pixels.count, CanvasSize.s16.byteCount)
        XCTAssertTrue(piece.pixels.allSatisfy { $0 == 0 })
    }

    func testDefaultNameFallsBackToGenerated() {
        let piece = Piece(size: .s32)
        piece.name = nil
        XCTAssertTrue(piece.effectiveName.contains("32 × 32"))
    }

    func testExplicitNameUsedWhenSet() {
        let piece = Piece(size: .s32)
        piece.name = "Hero sprite"
        XCTAssertEqual(piece.effectiveName, "Hero sprite")
    }

    func testSizeEnumPreserved() {
        let piece = Piece(size: .s128)
        XCTAssertEqual(piece.size, .s128)
    }
}
