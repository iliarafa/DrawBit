import XCTest
import SwiftData
@testable import DrawBit

@MainActor
final class PieceRepositoryTests: XCTestCase {
    var container: ModelContainer!
    var modelContext: ModelContext!
    var repo: PieceRepository!

    override func setUpWithError() throws {
        let schema = Schema([Piece.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        modelContext = ModelContext(container)
        repo = PieceRepository(context: modelContext)
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

    func testLoadFramesReturnsSequenceWithDefaults() throws {
        let piece = try repo.createPiece(size: .s32)
        let result = try repo.loadFrames(piece: piece)
        XCTAssertEqual(result.frames.count, 1)
        XCTAssertEqual(result.activeFrameIndex, 0)
        XCTAssertEqual(result.fps, 12)
    }

    func testSaveFramesRoundTrips() throws {
        let piece = try repo.createPiece(size: .s32)
        var (frames, _, _) = try repo.loadFrames(piece: piece)
        frames[0].addLayer(name: "Layer 2")
        try repo.saveFrames(piece: piece, frames: frames, activeFrameIndex: 0, fps: 24)

        let reloaded = try repo.loadFrames(piece: piece)
        XCTAssertEqual(reloaded.frames[0].layers.count, 2)
        XCTAssertEqual(reloaded.fps, 24)
    }

    func testLoadFramesMigratesLegacyV1Blob() throws {
        let piece = try repo.createPiece(size: .s32)
        // Force-write a legacy V1 blob (single Frame format) directly:
        let layer = Layer(name: "Layer 1", pixels: Data(count: CanvasSize.s32.byteCount))
        let legacyFrame = Frame(layers: [layer], activeLayerID: layer.id)
        piece.frameData = FrameCodec.encode(legacyFrame)
        try modelContext.save()

        let reloaded = try repo.loadFrames(piece: piece)
        XCTAssertEqual(reloaded.frames.count, 1)
        XCTAssertTrue(FrameCodec.hasV2SequenceMagicPrefix(piece.frameData),
                      "Loading a V1 blob should re-save as a V2 sequence")
    }

    func testSaveReferenceRoundTrips() throws {
        let piece = try repo.createPiece(size: .s16)
        let data = Data([1, 2, 3, 4, 5])
        try repo.saveReference(piece: piece, imageData: data, opacity: 0.5)

        let loaded = try XCTUnwrap(try repo.allPieces().first { $0.id == piece.id })
        XCTAssertEqual(loaded.referenceImageData, data)
        XCTAssertEqual(loaded.referenceOpacity, 0.5, accuracy: 0.0001)
    }

    func testSaveReferenceNilClearsImage() throws {
        let piece = try repo.createPiece(size: .s16)
        try repo.saveReference(piece: piece, imageData: Data([7, 7]), opacity: 0.4)
        try repo.saveReference(piece: piece, imageData: nil, opacity: 0.4)
        XCTAssertNil(piece.referenceImageData)
    }

    func testDuplicateCopiesReference() throws {
        let piece = try repo.createPiece(size: .s16)
        try repo.saveReference(piece: piece, imageData: Data([9, 9]), opacity: 0.6)
        let dup = try repo.duplicate(piece: piece)
        XCTAssertEqual(dup.referenceImageData, Data([9, 9]))
        XCTAssertEqual(dup.referenceOpacity, 0.6, accuracy: 0.0001)
    }
}
