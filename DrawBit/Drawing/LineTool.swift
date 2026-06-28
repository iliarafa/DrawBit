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
                      color: RGBA, mirror: Bool) -> Data {
        var grid = PixelGrid(data: base, size: size)
        Pencil.paintLine(on: &grid, from: from, to: to, color: color)
        if mirror {
            let w = size.width - 1
            Pencil.paintLine(on: &grid, from: (w - from.0, from.1), to: (w - to.0, to.1), color: color)
        }
        return grid.data
    }
}
