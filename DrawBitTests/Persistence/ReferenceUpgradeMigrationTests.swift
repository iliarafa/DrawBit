import XCTest
import SwiftData
@testable import DrawBit

/// Verifies the REAL upgrade path a shipped user takes: an on-disk store written by the
/// pre-reference build (a `Piece` with NO `referenceImageData` / `referenceOpacity`,
/// schema version 1.0.0) must open under the current production schema + migration plan
/// and gain the two new fields via inferred lightweight migration — without the
/// `loadIssueModelContainer` crash, and without losing existing data.
///
/// `MigrationTests.testOnDiskContainerWithPlanRoundTripsReferenceFields` only proves a
/// store *created by the current code* round-trips; it cannot catch a real old→new
/// upgrade failure. This test fabricates a faithful old-shape store to cover that gap.
@MainActor
final class ReferenceUpgradeMigrationTests: XCTestCase {

    /// Frozen snapshot of the pre-reference schema: `Piece` exactly as shipped through
    /// layers v2 + animation v1 (no reference fields), plus the unchanged `AppSettings`.
    /// Nested `@Model` types map to entity names "Piece" / "AppSettings" — matching the
    /// production entities so SwiftData correlates them for migration.
    enum LegacyV0Schema: VersionedSchema {
        static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
        static var models: [any PersistentModel.Type] { [Piece.self, AppSettings.self] }

        @Model final class Piece {
            @Attribute(.unique) var id: UUID
            var name: String?
            var sizeRaw: Int
            @Attribute(.externalStorage, originalName: "pixels") var frameData: Data
            var thumbnail: Data
            var createdAt: Date
            var updatedAt: Date

            init(id: UUID, sizeRaw: Int, frameData: Data,
                 thumbnail: Data, createdAt: Date, updatedAt: Date) {
                self.id = id
                self.name = nil
                self.sizeRaw = sizeRaw
                self.frameData = frameData
                self.thumbnail = thumbnail
                self.createdAt = createdAt
                self.updatedAt = updatedAt
            }
        }

        @Model final class AppSettings {
            var recentColors: [String]
            var lastUsedToolRaw: String
            init() {
                self.recentColors = []
                self.lastUsedToolRaw = "pencil"
            }
        }
    }

    func testUpgradeFromPreReferenceStoreMigratesAndDefaults() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drawbit-upgrade-\(UUID().uuidString).store")
        defer {
            let base = url.deletingLastPathComponent()
            for ext in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(
                    at: base.appendingPathComponent(url.lastPathComponent + ext))
            }
        }

        let pieceID = UUID()
        // A valid V2 sequence blob so the migrated piece's frame still loads afterwards.
        let frameBlob: Data = {
            let layer = Layer(name: "Layer 1", pixels: Data(count: CanvasSize.s16.byteCount))
            let frame = Frame(layers: [layer], activeLayerID: layer.id)
            return FrameCodec.encodeSequence(frames: [frame], activeFrameIndex: 0,
                                             fps: FrameCodec.defaultFPS)
        }()

        // 1. Write a store in the OLD shape (no reference fields), version 1.0.0.
        do {
            let schema = Schema(versionedSchema: LegacyV0Schema.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)
            let legacy = LegacyV0Schema.Piece(
                id: pieceID,
                sizeRaw: CanvasSize.s16.rawValue,
                frameData: frameBlob,
                thumbnail: Data(),
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
            ctx.insert(legacy)
            try ctx.save()
        }

        // 2. Reopen the SAME store with the PRODUCTION schema + plan — exactly as
        //    DrawBitApp builds its container. Must not throw loadIssueModelContainer.
        let schema = Schema(versionedSchema: DrawBitSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema,
                                           migrationPlan: DrawBitMigrationPlan.self,
                                           configurations: [config])
        let ctx = ModelContext(container)

        let pieces = try ctx.fetch(FetchDescriptor<Piece>())
        XCTAssertEqual(pieces.count, 1, "the pre-existing piece must survive the upgrade")
        let p = try XCTUnwrap(pieces.first { $0.id == pieceID })

        // New fields appear with their defaults.
        XCTAssertNil(p.referenceImageData)
        XCTAssertEqual(p.referenceOpacity, 0.35, accuracy: 0.0001)

        // Old data is intact and still decodes.
        XCTAssertEqual(p.frameData, frameBlob)
        let repo = PieceRepository(context: ctx)
        let frame = try repo.loadFrame(piece: p)
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.layers[0].pixels.count, CanvasSize.s16.byteCount)
    }
}
