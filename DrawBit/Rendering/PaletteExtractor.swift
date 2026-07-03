import Foundation

/// Pulls the distinct colors actually used in a frame, for the "grab colors from this piece"
/// palette-seeding feature. Pure Rendering-layer code (Foundation only) so it's unit-testable.
enum PaletteExtractor {
    /// Distinct opaque (`a == 255`) colors in first-seen (row-major) order, capped at `limit`.
    /// Returns uppercase hex without a leading '#', matching `ColorPalette.colors`.
    static func colors(in frame: Frame, size: CanvasSize, limit: Int = 64) -> [String] {
        let grid = PixelGrid(data: Compositor.composite(frame, size: size).data, size: size)
        var seen = Set<String>()
        var ordered: [String] = []
        for y in 0..<size.height {
            for x in 0..<size.width {
                let p = grid.pixel(x: x, y: y)
                guard p.a == 255 else { continue }
                let hex = String(format: "%02X%02X%02X", p.r, p.g, p.b)
                if seen.insert(hex).inserted {
                    ordered.append(hex)
                    if ordered.count == limit { return ordered }
                }
            }
        }
        return ordered
    }
}
