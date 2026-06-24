import Foundation

/// A pixel-grid size. Square by default (N×N) but supports fixed-ratio non-square
/// canvases (16:9 / 9:16) via `init(ratio:longestEdge:)`. The drawing/rendering stack
/// keys off `width`/`height`; `dimension` remains as a square-only back-compat alias.
struct CanvasSize: Hashable, Codable, Identifiable {
    let width: Int
    let height: Int

    static let minDimension = 8
    static let maxDimension = 256

    private static func clamp(_ v: Int) -> Int {
        Swift.min(maxDimension, Swift.max(minDimension, v))
    }

    /// Square N×N. Clamps to `[minDimension, maxDimension]`.
    init(_ dimension: Int) {
        let d = Self.clamp(dimension)
        self.width = d
        self.height = d
    }

    /// Arbitrary width×height; each axis clamps independently.
    init(width: Int, height: Int) {
        self.width = Self.clamp(width)
        self.height = Self.clamp(height)
    }

    /// Fixed aspect ratios offered by the New Piece picker.
    enum Ratio: Hashable, Codable {
        case square      // 1:1
        case r16x9       // landscape
        case r9x16       // portrait
    }

    /// Build an exact-integer-ratio size from a chosen longest edge. The long edge snaps
    /// down to a clean multiple of the ratio's larger term so the short edge stays an exact
    /// integer (e.g. 16:9 longestEdge 200 → k=12 → 192×108, a true 16:9 grid).
    init(ratio: Ratio, longestEdge: Int) {
        let (wTerm, hTerm): (Int, Int)
        switch ratio {
        case .square: (wTerm, hTerm) = (1, 1)
        case .r16x9:  (wTerm, hTerm) = (16, 9)
        case .r9x16:  (wTerm, hTerm) = (9, 16)
        }
        let maxTerm = Swift.max(wTerm, hTerm)
        let k = Swift.max(1, Self.clamp(longestEdge) / maxTerm)
        self.init(width: wTerm * k, height: hTerm * k)
    }

    var id: String { "\(width)x\(height)" }
    /// Square-only back-compat alias (== `width`). Non-square call sites must migrate to width/height.
    var dimension: Int { width }
    /// Back-compat alias for the old Int-raw enum value (== `width`); keeps preset accessibility IDs.
    var rawValue: Int { width }
    var isSquare: Bool { width == height }
    var longestEdge: Int { Swift.max(width, height) }
    var pixelCount: Int { width * height }
    var byteCount: Int { pixelCount * 4 }
    var displayName: String { "\(width) × \(height)" }

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

    // Encode as a bare Int when square (matching the old Int-raw enum's wire format),
    // else as a {width,height} pair. Decode accepts either. Not used on disk today.
    private enum CodingKeys: String, CodingKey { case width, height }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(Int.self) {
            self.init(single)
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(width: try c.decode(Int.self, forKey: .width),
                      height: try c.decode(Int.self, forKey: .height))
        }
    }

    func encode(to encoder: Encoder) throws {
        if isSquare {
            var c = encoder.singleValueContainer()
            try c.encode(width)
        } else {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(width, forKey: .width)
            try c.encode(height, forKey: .height)
        }
    }
}
