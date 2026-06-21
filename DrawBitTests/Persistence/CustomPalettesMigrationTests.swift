import XCTest
import SwiftData
@testable import DrawBit

/// Proves the real upgrade path for the custom-palettes feature: an on-disk store written
/// before `AppSettings.customPalettes` existed must reopen under the production schema and gain
/// the new field via inferred lightweight migration — `customPalettes == []` — without crashing
/// and without losing existing `AppSettings` data. This is also the canary that confirms a
/// `[ColorPalette]` (array-of-Codable) property is lightweight-migratable in SwiftData.
@MainActor
final class CustomPalettesMigrationTests: XCTestCase {

    /// Frozen pre-palettes shape: `AppSettings` with NO `customPalettes`, plus a `Piece` in the
    /// shape shipped before this feature. Entity names "Piece"/"AppSettings" match production so
    /// SwiftData correlates them for migration.
    enum LegacyPaletteSchema: VersionedSchema {
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

    func testUpgradeFromPrePalettesStoreDefaultsToEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drawbit-palettes-\(UUID().uuidString).store")
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

        // 1. Write a store in the OLD shape (no customPalettes column), version 1.0.0.
        do {
            let schema = Schema(versionedSchema: LegacyPaletteSchema.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)
            let legacyPiece = LegacyPaletteSchema.Piece(
                id: UUID(),
                sizeRaw: CanvasSize.s16.rawValue,
                frameData: frameBlob,
                thumbnail: Data(),
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
            ctx.insert(legacyPiece)
            let legacySettings = LegacyPaletteSchema.AppSettings()
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
        XCTAssertEqual(s.customPalettes, [], "new field defaults to empty after migration")
        XCTAssertEqual(s.recentColors, ["#ABCDEF"], "old AppSettings data must be intact")
    }
}
