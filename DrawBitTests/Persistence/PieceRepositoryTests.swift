import XCTest
import SwiftData
@testable import DrawBit

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
        let frame = try repo.loadFrame(piece: piece)
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.layers[0].pixels.count, CanvasSize.s32.byteCount)
        XCTAssertTrue(frame.layers[0].pixels.allSatisfy { $0 == 0 })
    }

    func testSaveUpdatesPixelsAndThumbnail() throws {
        let piece = try repo.createPiece(size: .s16)
        var grid = PixelGrid(size: .s16)
        Pencil.paint(on: &grid, at: (0, 0), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        let layer = Layer(name: "Layer 1", pixels: grid.data)
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        try repo.saveFrame(piece: piece, frame)
        let savedFrame = try repo.loadFrame(piece: piece)
        XCTAssertEqual(savedFrame.layers[0].pixels, grid.data)
        XCTAssertGreaterThan(piece.thumbnail.count, 0)
    }

    func testDuplicateCopiesPixelsAndAppendsCopy() throws {
        let original = try repo.createPiece(size: .s16)
        original.name = "Hero"
        var grid = PixelGrid(size: .s16)
        Pencil.paint(on: &grid, at: (1, 1), color: RGBA(r: 9, g: 9, b: 9, a: 255))
        let layer = Layer(name: "Layer 1", pixels: grid.data)
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        try repo.saveFrame(piece: original, frame)

        let dup = try repo.duplicate(piece: original)
        XCTAssertNotEqual(dup.id, original.id)
        let dupFrame = try repo.loadFrame(piece: dup)
        let origFrame = try repo.loadFrame(piece: original)
        XCTAssertEqual(dupFrame.layers[0].pixels, origFrame.layers[0].pixels)
        XCTAssertEqual(dup.name, "Hero copy")
    }

    func testDeleteRemovesPiece() throws {
        let piece = try repo.createPiece(size: .s16)
        try repo.delete(piece: piece)
        let remaining = try repo.allPieces()
        XCTAssertFalse(remaining.contains(where: { $0.id == piece.id }))
    }
}
