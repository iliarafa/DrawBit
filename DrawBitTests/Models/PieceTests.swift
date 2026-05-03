import XCTest
import SwiftData
@testable import DrawBit

final class PieceTests: XCTestCase {
    func testNewPieceIsAllTransparent() throws {
        let piece = Piece(size: .s16)
        let frame = try FrameCodec.decode(piece.frameData)
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.layers[0].pixels.count, CanvasSize.s16.byteCount)
        XCTAssertTrue(frame.layers[0].pixels.allSatisfy { $0 == 0 })
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
