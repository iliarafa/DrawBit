import Foundation
import SwiftData

@Model
final class Piece {
    @Attribute(.unique) var id: UUID
    var name: String?
    var sizeRaw: Int
    var pixels: Data
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
        self.pixels = Data(count: size.byteCount)
        self.thumbnail = Data()
        self.createdAt = now
        self.updatedAt = now
    }
}
