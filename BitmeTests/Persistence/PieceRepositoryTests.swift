import XCTest
import SwiftData
@testable import Bitme

@MainActor
final class PieceRepositoryTests: XCTestCase {
    var container: ModelContainer!
    var repo: PieceRepository!

    override func setUpWithError() throws {
        let schema = Schema([Piece.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        repo = PieceRepository(context: ModelContext(container))
    }

    func testCreatePieceReturnsAllTransparent() throws {
        let piece = try repo.createPiece(size: .s32)
        XCTAssertEqual(piece.pixels.count, CanvasSize.s32.byteCount)
        XCTAssertTrue(piece.pixels.allSatisfy { $0 == 0 })
    }

    func testSaveUpdatesPixelsAndThumbnail() throws {
        let piece = try repo.createPiece(size: .s16)
        var grid = PixelGrid(data: piece.pixels, size: piece.size)
        Pencil.paint(on: &grid, at: (0, 0), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        try repo.save(piece: piece, pixels: grid.data)
        XCTAssertEqual(piece.pixels, grid.data)
        XCTAssertGreaterThan(piece.thumbnail.count, 0)
    }

    func testDuplicateCopiesPixelsAndAppendsCopy() throws {
        let original = try repo.createPiece(size: .s16)
        original.name = "Hero"
        var grid = PixelGrid(data: original.pixels, size: .s16)
        Pencil.paint(on: &grid, at: (1, 1), color: RGBA(r: 9, g: 9, b: 9, a: 255))
        try repo.save(piece: original, pixels: grid.data)

        let dup = try repo.duplicate(piece: original)
        XCTAssertNotEqual(dup.id, original.id)
        XCTAssertEqual(dup.pixels, original.pixels)
        XCTAssertEqual(dup.name, "Hero copy")
    }

    func testDeleteRemovesPiece() throws {
        let piece = try repo.createPiece(size: .s16)
        try repo.delete(piece: piece)
        let remaining = try repo.allPieces()
        XCTAssertFalse(remaining.contains(where: { $0.id == piece.id }))
    }
}
