import XCTest
import SwiftData
@testable import DrawBit

@MainActor
final class MigrationTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Piece.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testV1RawBlobMigratesToSingleLayerFrameOnLoad() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let piece = Piece(size: .s32)
        // Force the piece into v1 shape: overwrite frameData with raw RGBA bytes (no DBFR magic).
        let v1 = Data(repeating: 0xAA, count: CanvasSize.s32.byteCount)
        piece.frameData = v1
        ctx.insert(piece)
        try ctx.save()

        let repo = PieceRepository(context: ctx)
        let frame = try repo.loadFrame(piece: piece)
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.layers[0].pixels, v1)
        XCTAssertTrue(FrameCodec.hasV2SequenceMagicPrefix(piece.frameData),
                      "loadFrame must persist the migrated v2 blob back to disk")
    }

    func testEagerMigrationConvertsAllPieces() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let p1 = Piece(size: .s16)
        let p2 = Piece(size: .s32)
        p1.frameData = Data(repeating: 0x11, count: CanvasSize.s16.byteCount)
        p2.frameData = Data(repeating: 0x22, count: CanvasSize.s32.byteCount)
        ctx.insert(p1); ctx.insert(p2)
        try ctx.save()

        let repo = PieceRepository(context: ctx)
        try repo.migrateLegacyPiecesIfNeeded()

        XCTAssertTrue(FrameCodec.hasV2SequenceMagicPrefix(p1.frameData))
        XCTAssertTrue(FrameCodec.hasV2SequenceMagicPrefix(p2.frameData))
    }

    func testEagerMigrationIsIdempotent() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let piece = Piece(size: .s32)
        ctx.insert(piece)
        try ctx.save()
        let initialBlob = piece.frameData

        let repo = PieceRepository(context: ctx)
        try repo.migrateLegacyPiecesIfNeeded()
        try repo.migrateLegacyPiecesIfNeeded()

        XCTAssertEqual(piece.frameData, initialBlob, "second run must be a no-op")
    }

    /// Smoke test for the `SchemaMigrationPlan` plumbing added in
    /// `DrawBitSchema.swift`. A container built with the plan should open the
    /// V1 schema, accept inserts, and round-trip a piece through save/load.
    /// If `DrawBitMigrationPlan` ever gets a misconfigured stage, this is the
    /// canary — it fails before users see `loadIssueModelContainer`.
    func testSchemaMigrationPlanContainerOpensAndRoundTripsPiece() throws {
        let schema = Schema(versionedSchema: DrawBitSchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: DrawBitMigrationPlan.self,
            configurations: [config]
        )
        let ctx = ModelContext(container)

        let piece = Piece(size: .s16)
        ctx.insert(piece)
        try ctx.save()

        // Round-trip: fetch the inserted piece back and verify its frame loads.
        let pieces = try ctx.fetch(FetchDescriptor<Piece>())
        XCTAssertEqual(pieces.count, 1)
        let repo = PieceRepository(context: ctx)
        let frame = try repo.loadFrame(piece: pieces[0])
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.layers[0].pixels.count, CanvasSize.s16.byteCount)
    }

    /// Exercises the PRODUCTION container path: an ON-DISK store built with the
    /// migration plan. This is the path a real device launch takes and the only
    /// one where a misconfigured plan (e.g. two schemas sharing a checksum) would
    /// abort with "Duplicate version checksums detected". It also proves the
    /// additive reference-photo fields round-trip across a close/reopen of the
    /// same store file via inferred lightweight migration.
    func testOnDiskContainerWithPlanRoundTripsReferenceFields() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drawbit-migration-\(UUID().uuidString).store")
        defer {
            for ext in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent()
                        .appendingPathComponent(url.lastPathComponent + ext))
            }
        }

        let schema = Schema(versionedSchema: DrawBitSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: url)

        // First open: write a piece carrying both reference fields, then let the
        // container deallocate so the file is released.
        let pieceID: UUID
        do {
            let container = try ModelContainer(for: schema,
                                               migrationPlan: DrawBitMigrationPlan.self,
                                               configurations: [config])
            let ctx = ModelContext(container)
            let piece = Piece(size: .s16)
            pieceID = piece.id
            piece.referenceImageData = Data([1, 2, 3])
            piece.referenceOpacity = 0.5
            ctx.insert(piece)
            try ctx.save()
        }

        // Reopen the same on-disk store with the same plan and verify the fields persisted.
        let container2 = try ModelContainer(for: schema,
                                            migrationPlan: DrawBitMigrationPlan.self,
                                            configurations: [config])
        let ctx2 = ModelContext(container2)
        let fetched = try ctx2.fetch(FetchDescriptor<Piece>())
        let p = try XCTUnwrap(fetched.first { $0.id == pieceID })
        XCTAssertEqual(p.referenceImageData, Data([1, 2, 3]))
        XCTAssertEqual(p.referenceOpacity, 0.5, accuracy: 0.0001)
    }
}
