import Foundation
import SwiftData

@Model
final class Piece {
    @Attribute(.unique) var id: UUID
    var name: String?
    var sizeRaw: Int

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

    var size: CanvasSize {
        get { CanvasSize(rawValue: sizeRaw) ?? .s32 }
        set { sizeRaw = newValue.rawValue }
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
        self.sizeRaw = size.rawValue
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
