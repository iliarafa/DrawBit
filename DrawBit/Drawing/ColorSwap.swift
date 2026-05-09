import Foundation

enum ColorSwap {
    /// Replace every pixel matching `from` with `to` across the entire grid.
    /// Connectivity-agnostic, unlike Fill — affects disjoint regions in one pass.
    static func swap(on grid: inout PixelGrid, from: RGBA, to: RGBA) {
        if from == to { return }
        let dim = grid.dimension
        for y in 0..<dim {
            for x in 0..<dim where grid.pixel(x: x, y: y) == from {
                grid.setPixel(x: x, y: y, color: to)
            }
        }
    }
}
