import Foundation

/// A square pixel-grid size (N×N). The New Piece picker offers a curated set of
/// `presets`, but any N in `[minDimension, maxDimension]` is valid — the whole
/// drawing/rendering stack keys off `dimension`, so custom (non-preset) squares work
/// everywhere, and mirror symmetry's `dimension - 1 - x` is unaffected.
struct CanvasSize: Hashable, Codable, Identifiable {
    let dimension: Int

    static let minDimension = 8
    static let maxDimension = 256

    /// Clamps to `[minDimension, maxDimension]` so a stray custom value can never
    /// produce an out-of-range grid.
    init(_ dimension: Int) {
        self.dimension = Swift.min(Self.maxDimension, Swift.max(Self.minDimension, dimension))
    }

    var id: Int { dimension }
    /// Back-compat alias for the old `Int`-raw enum value (always == `dimension`).
    var rawValue: Int { dimension }
    var pixelCount: Int { dimension * dimension }
    var byteCount: Int { pixelCount * 4 }
    var displayName: String { "\(dimension) × \(dimension)" }

    // Named constants for the historical presets. The odd ones (15/31/63) are no
    // longer in the picker — Custom covers true-center grids — but they stay so old
    // pieces saved at those sizes still reopen and tests keep their fixtures.
    static let s15 = CanvasSize(15)
    static let s16 = CanvasSize(16)
    static let s31 = CanvasSize(31)
    static let s32 = CanvasSize(32)
    static let s63 = CanvasSize(63)
    static let s64 = CanvasSize(64)
    static let s128 = CanvasSize(128)

    /// The curated sizes shown in the New Piece picker (Custom handles the rest).
    static let presets: [CanvasSize] = [s16, s32, s64, s128]

    // Encode as a bare Int, matching the old Int-raw enum's wire format.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dimension)
    }
}
