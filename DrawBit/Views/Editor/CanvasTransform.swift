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
