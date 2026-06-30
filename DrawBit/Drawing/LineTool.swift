import Foundation

/// Stamps a straight pixel line onto a COPY of `base`. Because it always starts from `base`, a
/// single call both *restores* the pre-stroke state and *draws* the line — which is exactly what
/// the pencil's "hold to straighten" needs: as the finger re-aims, each update recomputes from the
/// same pre-stroke snapshot, so the freehand wobble is cleanly replaced rather than accumulated.
///
/// Reuses `Pencil.paintLine` (Bresenham). When `mirror` is set, also paints the line reflected
/// across the vertical centerline (`x → width-1-x`), matching the pencil's mirror behavior.
enum LineTool {
    static func apply(to base: Data, size: CanvasSize, from: (Int, Int), to: (Int, Int),
                      color: RGBA, mirror: Bool, brushSize: Int = 1) -> Data {
        var grid = PixelGrid(data: base, size: size)
        stampLine(on: &grid, from: from, to: to, color: color, brushSize: brushSize)
        if mirror {
            let w = size.width - 1
            stampLine(on: &grid, from: (w - from.0, from.1), to: (w - to.0, to.1),
                      color: color, brushSize: brushSize)
        }
        return grid.data
    }

    /// Bresenham line, stamped with a square nib at each point. A 1-px nib is the original
    /// single-pixel `Pencil.paintLine`; larger nibs stamp `Brush.squareCells` per point (gaps are
    /// impossible because consecutive Bresenham points are adjacent). Out-of-bounds cells are
    /// dropped by `PixelGrid.setPixel`.
    private static func stampLine(on grid: inout PixelGrid, from: (Int, Int), to: (Int, Int),
                                  color: RGBA, brushSize: Int) {
        if brushSize <= 1 {
            Pencil.paintLine(on: &grid, from: from, to: to, color: color)
            return
        }
        for p in bresenhamLine(from: from, to: to) {
            for (cx, cy) in Brush.squareCells(centeredAt: p, size: brushSize) {
                grid.setPixel(x: cx, y: cy, color: color)
            }
        }
    }

    /// Whether a line from `from` to `to` lands on a "perfect" pixel angle — horizontal, vertical,
    /// or exact 45° — where the Bresenham staircase resolves to a clean line. Used to fire a detent
    /// (click + haptic) as the held line re-aims through these angles. A zero-length line is not
    /// perfect (so the snap moment, anchor == endpoint, doesn't count).
    static func isPerfectAngle(from: (Int, Int), to: (Int, Int)) -> Bool {
        let a = abs(to.0 - from.0)
        let b = abs(to.1 - from.1)
        guard a != 0 || b != 0 else { return false }
        return a == 0 || b == 0 || a == b
    }
}
