import CoreGraphics

/// Maps a point in canvas-local (base, 1×) coordinates to its on-screen position under the
/// editor's view transform. Reproduces exactly the composite `CanvasView` applies to the pixel
/// image — `.scaleEffect(scale).rotationEffect(rotation).offset(translation)` about the viewport
/// centre — and is the precise inverse of `CanvasHostView.pixelCoord(for:)`'s screen→pixel walk.
///
/// Used to redraw vector overlays (grid, marquee chrome) directly at viewport resolution rather
/// than rasterising them small and stretching with `.scaleEffect` (which blurs). Transforming the
/// path's *points* — not the `GraphicsContext` — keeps stroke widths in screen points, so a 1pt
/// hairline stays a crisp 1pt at any zoom while landing pixel-locked to the art.
///
/// A base point `p` maps to screen via `p.applying(canvasToScreenTransform(...))`, i.e.
/// `screen = R(rotation)·scale·(p − base/2) + viewport/2 + translation`.
func canvasToScreenTransform(base: CGSize, viewport: CGSize,
                             scale: CGFloat, rotation: CGFloat,
                             translation: CGSize) -> CGAffineTransform {
    CGAffineTransform(translationX: viewport.width / 2 + translation.width,
                      y: viewport.height / 2 + translation.height)
        .rotated(by: rotation)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -base.width / 2, y: -base.height / 2)
}

/// Opacity for the *interior* pixel grid given the on-screen size of one cell (points). As a cell
/// shrinks, its 1pt lines cover a bigger fraction of it, so a dense grid merges into a bright gray
/// wash. Fade the lines down as cells shrink so a dense/medium canvas (small cells filling the
/// viewport) reads as a calm guide rather than a wash, reaching full strength only when you're
/// zoomed in enough to target individual cells, and hide entirely once they're too small to use.
/// Linear ramp: hidden ≤4pt, full ≥20pt — so medium/dense canvases sit partway (e.g. a 96×54 at fit,
/// ~15pt cells, lands ~0.69). The canvas border is drawn separately and stays visible so bounds read
/// even when this is 0.
func gridLineAlpha(screenCellPoints c: CGFloat) -> Double {
    let lo: CGFloat = 4, hi: CGFloat = 20
    return Double(max(0, min(1, (c - lo) / (hi - lo))))
}

/// Opacity for the canvas *border*. The border reads like a grid line (drawn in the same grey, and
/// fading with `gridLineAlpha`) so it stops framing the canvas — but it never drops below `floor`,
/// so a faint outline survives once the interior grid hides (zoomed out) and an empty canvas's
/// bounds still read.
func borderLineAlpha(screenCellPoints c: CGFloat) -> Double {
    let floor = 0.45
    return max(gridLineAlpha(screenCellPoints: c), floor)
}
