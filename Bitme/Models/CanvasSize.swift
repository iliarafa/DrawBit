import Foundation

enum CanvasSize: Int, CaseIterable, Codable, Identifiable {
    case s16 = 16
    case s32 = 32
    case s64 = 64
    case s128 = 128

    var id: Int { rawValue }
    var dimension: Int { rawValue }
    var pixelCount: Int { dimension * dimension }
    var byteCount: Int { pixelCount * 4 }

    var displayName: String { "\(dimension) × \(dimension)" }
}
