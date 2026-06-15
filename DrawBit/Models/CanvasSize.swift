import Foundation

enum CanvasSize: Int, CaseIterable, Codable, Identifiable {
    // Odd sizes have a true center pixel (e.g. col/row 7 on a 15-grid), which
    // even sizes can't offer. Interleaved with the even sizes so the New Piece
    // picker reads small-to-large.
    case s15 = 15
    case s16 = 16
    case s31 = 31
    case s32 = 32
    case s63 = 63
    case s64 = 64
    case s128 = 128

    var id: Int { rawValue }
    var dimension: Int { rawValue }
    var pixelCount: Int { dimension * dimension }
    var byteCount: Int { pixelCount * 4 }

    var displayName: String { "\(dimension) × \(dimension)" }
}
