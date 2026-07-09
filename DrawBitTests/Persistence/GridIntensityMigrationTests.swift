import XCTest
import SwiftData
@testable import DrawBit

/// Proves the real upgrade path for the grid-intensity preference: an on-disk store written before
/// `AppSettings.gridIntensityRaw` existed must reopen under the production schema and gain the new
/// field via inferred lightweight migration — defaulting to `.soft` — without crashing and without
/// losing existing `AppSettings` data. Mirrors `CustomPalettesMigrationTests`; the additive
/// defaulted `Int` column rides the single live schema (no new `VersionedSchema`).
@MainActor
final class GridIntensityMigrationTests: XCTestCase {

    /// Frozen pre-grid-intensity shape: `AppSettings` with NO `gridIntensityRaw` (and no
    /// customPalettes), plus a `Piece` in the shape shipped before this feature. Entity names match
    /// production so SwiftData correlates them for migration.
    enum LegacyGridSchema: VersionedSchema {
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

    func testUpgradeFromPreGridStoreDefaultsToSoft() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drawbit-grid-\(UUID().uuidString).store")
        defer {
            let base = url.deletingLastPathComponent()
            for ext in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(
                    at: base.appendingPathComponent(url.lastPathComponent + ext))
            }
        }

        let frameBlob: Data = {
            let layer = Layer(name: "Layer 1", pixels: Data(count: CanvasSize.s16.byteCount))
            let frame = Frame(layers: [layer], activeLayerID: layer.id)
            return FrameCodec.encodeSequence(frames: [frame], activeFrameIndex: 0,
                                             fps: FrameCodec.defaultFPS)
        }()

        // 1. Write a store in the OLD shape (no gridIntensityRaw column), version 1.0.0.
        do {
            let schema = Schema(versionedSchema: LegacyGridSchema.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)
            let legacyPiece = LegacyGridSchema.Piece(
                id: UUID(),
                sizeRaw: CanvasSize.s16.rawValue,
                frameData: frameBlob,
                thumbnail: Data(),
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
            ctx.insert(legacyPiece)
            let legacySettings = LegacyGridSchema.AppSettings()
            legacySettings.recentColors = ["#ABCDEF"]
            ctx.insert(legacySettings)
            try ctx.save()
        }

        // 2. Reopen with the PRODUCTION schema + plan. Must not throw, and the new field defaults.
        let schema = Schema(versionedSchema: DrawBitSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema,
                                           migrationPlan: DrawBitMigrationPlan.self,
                                           configurations: [config])
        let ctx = ModelContext(container)

        let settings = try ctx.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(settings.count, 1, "the pre-existing AppSettings must survive the upgrade")
        let s = try XCTUnwrap(settings.first)
        XCTAssertEqual(s.gridIntensity, .soft, "new grid-intensity field defaults to SOFT after migration")
        XCTAssertEqual(s.recentColors, ["#ABCDEF"], "old AppSettings data must be intact")
    }
}
