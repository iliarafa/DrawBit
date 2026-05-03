import Foundation
import SwiftData

@Model
final class Piece {
    @Attribute(.unique) var id: UUID
    var name: String?
    var sizeRaw: Int

    /// Versioned blob holding the entire Frame (layers + active layer id).
    /// External storage keeps the row light when the blob grows with multiple layers.
    @Attribute(.externalStorage) var frameData: Data

    var thumbnail: Data
    var createdAt: Date
    var updatedAt: Date

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
        // New pieces start as a single empty layer wrapped in a Frame and encoded.
        let layer = Layer(name: "Layer 1", pixels: Data(count: size.byteCount))
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        self.frameData = FrameCodec.encode(frame)
        self.thumbnail = Data()
        self.createdAt = now
        self.updatedAt = now
    }
}
