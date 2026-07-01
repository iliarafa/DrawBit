import Foundation
import SwiftData

@Model
final class Piece {
    @Attribute(.unique) var id: UUID
    var name: String?
    /// Canvas width in pixels. (Historically the single square dimension; kept under the
    /// same column name so old square stores migrate without a rename.)
    var sizeRaw: Int
    /// Canvas height in pixels. Defaulted (`0`) so pre-non-square stores ride inferred
    /// lightweight migration; `0` is read as "square" ⇒ height = width. New pieces always
    /// store the real height. Do NOT add a second live `VersionedSchema` (see CLAUDE.md).
    var heightRaw: Int = 0

    /// Versioned blob holding the entire Frame (layers + active layer id) for V1,
    /// and the encoded sequence (DBFR/DBFS) for V2+. External storage keeps the
    /// row light when the blob grows with multiple layers.
    ///
    /// `originalName: "pixels"` lets SwiftData auto-rename the column for any
    /// pre-Stage-1 store that called it `pixels` (raw single-layer bytes). Public
    /// distribution never shipped that build, but internal test devices might
    /// still have it. The bytes themselves are converted V1→V2 lazily by
    /// `PieceRepository.loadFrames`; this attribute handles only the column
    /// rename so SwiftData can open the store at all.
    @Attribute(.externalStorage, originalName: "pixels") var frameData: Data

    var thumbnail: Data
    var createdAt: Date
    var updatedAt: Date

    /// Optional tracing reference photo, stored as a size-capped JPEG (see
    /// `ReferenceImageProcessor`). Display-only: never composited, never exported.
    /// External storage keeps the row light. Nil = no reference.
    @Attribute(.externalStorage) var referenceImageData: Data?

    /// Fade applied to the reference photo behind the canvas, 0...1. Persisted so a
    /// piece reopens as the user left it. Default chosen for a readable lightbox look.
    var referenceOpacity: Double = 0.35

    /// Optional saved time-lapse recording — a `TimelapseCodec` blob (a list of
    /// zlib-compressed composited keyframes). Display/export-only: never part of
    /// `frameData`, never composited into a normal export. External storage keeps
    /// the row light. Additive optional column → inferred lightweight migration
    /// (no new schema; see `DrawBitSchema.swift`).
    @Attribute(.externalStorage) var timelapseData: Data?

    var size: CanvasSize {
        get { CanvasSize(width: sizeRaw, height: heightRaw == 0 ? sizeRaw : heightRaw) }
        set {
            sizeRaw = newValue.width
            heightRaw = newValue.height
        }
    }

    var effectiveName: String {
        if let name, !name.isEmpty { return name }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return "\(size.displayName) · \(df.string(from: createdAt))"
    }

    init(size: CanvasSize) {
        let now = Date()
        self.id = UUID()
        self.name = nil
        self.sizeRaw = size.width
        self.heightRaw = size.height
        let layer = Layer(name: "Layer 1", pixels: Data(count: size.byteCount))
        let frame = Frame(name: "Frame 1", layers: [layer], activeLayerID: layer.id)
        self.frameData = FrameCodec.encodeSequence(frames: [frame],
                                                    activeFrameIndex: 0,
                                                    fps: FrameCodec.defaultFPS)
        self.thumbnail = Data()
        self.createdAt = now
        self.updatedAt = now
    }
}
