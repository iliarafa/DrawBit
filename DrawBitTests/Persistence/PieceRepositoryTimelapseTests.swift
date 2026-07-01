import XCTest
import SwiftData
@testable import DrawBit

@MainActor
final class PieceRepositoryTimelapseTests: XCTestCase {
    private func repo() throws -> (PieceRepository, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Piece.self, AppSettings.self, configurations: config)
        let ctx = ModelContext(container)
        return (PieceRepository(context: ctx), ctx)
    }

    func testSaveAndReloadTimelapse() throws {
        let (r, _) = try repo()
        let piece = try r.createPiece(size: CanvasSize(width: 16, height: 16))
        XCTAssertNil(piece.timelapseData)
        let blob = TimelapseCodec.encode([Data([1, 2, 3]), Data([4, 5, 6])])
        try r.saveTimelapse(piece: piece, blob: blob)
        XCTAssertEqual(piece.timelapseData, blob)
    }

    func testDuplicateCopiesTimelapse() throws {
        let (r, _) = try repo()
        let piece = try r.createPiece(size: CanvasSize(width: 16, height: 16))
        let blob = TimelapseCodec.encode([Data([9, 9])])
        try r.saveTimelapse(piece: piece, blob: blob)
        let copy = try r.duplicate(piece: piece)
        XCTAssertEqual(copy.timelapseData, blob)
    }
}
