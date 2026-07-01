import XCTest
import SwiftData
@testable import DrawBit

/// A store written by the CURRENT shipped build (reference fields present, but NO
/// `timelapseData`) must open under the updated live model and gain the optional
/// column via inferred lightweight migration — no crash, existing data intact.
@MainActor
final class TimelapseUpgradeMigrationTests: XCTestCase {
    enum PreTimelapseSchema: VersionedSchema {
        static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
        static var models: [any PersistentModel.Type] { [Piece.self, AppSettings.self] }

        @Model final class Piece {
            @Attribute(.unique) var id: UUID
            var name: String?
            var sizeRaw: Int
            var heightRaw: Int = 0
            @Attribute(.externalStorage, originalName: "pixels") var frameData: Data
            var thumbnail: Data
            var createdAt: Date
            var updatedAt: Date
            @Attribute(.externalStorage) var referenceImageData: Data?
            var referenceOpacity: Double = 0.35
            init(id: UUID, sizeRaw: Int, frameData: Data, thumbnail: Data,
                 createdAt: Date, updatedAt: Date) {
                self.id = id; self.name = nil; self.sizeRaw = sizeRaw
                self.frameData = frameData; self.thumbnail = thumbnail
                self.createdAt = createdAt; self.updatedAt = updatedAt
            }
        }
        @Model final class AppSettings {
            var recentColors: [String]
            var lastUsedToolRaw: String
            init() { self.recentColors = []; self.lastUsedToolRaw = "pencil" }
        }
    }

    func testUpgradeFromPreTimelapseStoreDefaultsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drawbit-tl-\(UUID().uuidString).store")
        defer {
            let base = url.deletingLastPathComponent()
            for ext in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(
                    at: base.appendingPathComponent(url.lastPathComponent + ext))
            }
        }
        let pieceID = UUID()
        let frameBlob: Data = {
            let layer = Layer(name: "Layer 1", pixels: Data(count: CanvasSize.s16.byteCount))
            let frame = Frame(layers: [layer], activeLayerID: layer.id)
            return FrameCodec.encodeSequence(frames: [frame], activeFrameIndex: 0,
                                             fps: FrameCodec.defaultFPS)
        }()

        do {
            let schema = Schema(versionedSchema: PreTimelapseSchema.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)
            let p = PreTimelapseSchema.Piece(id: pieceID, sizeRaw: 16, frameData: frameBlob,
                                             thumbnail: Data(), createdAt: Date(), updatedAt: Date())
            ctx.insert(p)
            try ctx.save()
        }

        // Reopen under the CURRENT production schema + plan.
        let schema = Schema(versionedSchema: DrawBitSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema,
                                           migrationPlan: DrawBitMigrationPlan.self,
                                           configurations: [config])
        let ctx = ModelContext(container)
        let pieces = try ctx.fetch(FetchDescriptor<Piece>())
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces.first?.id, pieceID)
        XCTAssertNil(pieces.first?.timelapseData, "new optional column defaults nil")
    }
}
