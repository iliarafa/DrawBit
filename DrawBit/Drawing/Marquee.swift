import Foundation

struct ExtractedSelection: Equatable {
    let originalBounds: PixelRect
    let pixels: PixelGrid
}

enum Marquee {
    /// Copy every opaque pixel inside `rect` into a canvas-sized grid (transparent elsewhere)
    /// and clear those same pixels from `grid`. Returns nil if no opaque pixels were found,
    /// in which case `grid` is unchanged.
    static func extractAndCut(grid: inout PixelGrid, rect: PixelRect) -> ExtractedSelection? {
        guard let clipped = rect.clipped(toCanvasWidth: grid.width, height: grid.height) else { return nil }
        var pixels = PixelGrid(size: grid.size)
        var found = false
        for y in clipped.y..<(clipped.y + clipped.height) {
            for x in clipped.x..<(clipped.x + clipped.width) {
                let p = grid.pixel(x: x, y: y)
                if p.a > 0 {
                    pixels.setPixel(x: x, y: y, color: p)
                    grid.setPixel(x: x, y: y, color: .transparent)
                    found = true
                }
            }
        }
        guard found else { return nil }
        return ExtractedSelection(originalBounds: clipped, pixels: pixels)
    }

    /// Blit non-transparent cells of `selection.pixels` (within `selection.originalBounds`)
    /// into `grid`, shifted by `offset`. Cells that fall outside the canvas are dropped.
    static func commit(into grid: inout PixelGrid, selection: ExtractedSelection, offset: (dx: Int, dy: Int)) {
        let b = selection.originalBounds
        for y in b.y..<(b.y + b.height) {
            for x in b.x..<(b.x + b.width) {
                let p = selection.pixels.pixel(x: x, y: y)
                if p.a > 0 {
                    grid.setPixel(x: x + offset.dx, y: y + offset.dy, color: p)
                }
            }
        }
    }
}
