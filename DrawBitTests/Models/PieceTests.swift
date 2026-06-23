import XCTest
import SwiftData
@testable import DrawBit

final class PieceTests: XCTestCase {
    func testNewPieceIsAllTransparent() throws {
        let piece = Piece(size: .s16)
        let decoded = try FrameCodec.decodeSequence(piece.frameData)
        let frame = decoded.frames[decoded.activeFrameIndex]
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

    func testCustomSizeRoundTripsThroughSizeRaw() throws {
        let piece = Piece(size: CanvasSize(48))
        XCTAssertEqual(piece.sizeRaw, 48)
        XCTAssertEqual(piece.size, CanvasSize(48))
        XCTAssertEqual(piece.size.dimension, 48)
        let decoded = try FrameCodec.decodeSequence(piece.frameData)
        XCTAssertEqual(decoded.frames[0].layers[0].pixels.count, CanvasSize(48).byteCount)
    }

    func testNewPieceFrameDataIsV2SequenceWithOneFrame() throws {
        let piece = Piece(size: .s32)
        XCTAssertTrue(FrameCodec.hasV2SequenceMagicPrefix(piece.frameData))
        let decoded = try FrameCodec.decodeSequence(piece.frameData)
        XCTAssertEqual(decoded.frames.count, 1)
        XCTAssertEqual(decoded.frames[0].layers.count, 1)
        XCTAssertEqual(decoded.frames[0].layers[0].name, "Layer 1")
        XCTAssertEqual(decoded.activeFrameIndex, 0)
        XCTAssertEqual(decoded.fps, 12)
    }
}
