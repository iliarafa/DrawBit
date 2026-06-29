import Foundation

/// Pure transforms on a floating marquee selection's lifted pixels.
///
/// Each operates on an `ExtractedSelection` — a canvas-sized `pixels` grid whose content lives
/// inside `originalBounds` — and returns a fresh selection. No SwiftUI / UIKit / SwiftData, so
/// they're trivially testable (the pure-logic rule).
enum SelectionTransform {
    /// Mirror the selection's content left↔right within its bounds. Bounds are unchanged, so the
    /// floating selection flips in place wherever it currently sits (bounds + dragOffset).
    static func flipHorizontal(_ sel: ExtractedSelection) -> ExtractedSelection {
        let b = sel.originalBounds
        var out = PixelGrid(size: sel.pixels.size)
        for y in b.y..<(b.y + b.height) {
            for c in 0..<b.width {
                let color = sel.pixels.pixel(x: b.x + c, y: y)
                out.setPixel(x: b.x + (b.width - 1 - c), y: y, color: color)
            }
        }
        return ExtractedSelection(originalBounds: b, pixels: out)
    }

    /// Mirror the selection's content top↔bottom within its bounds. Bounds are unchanged.
    static func flipVertical(_ sel: ExtractedSelection) -> ExtractedSelection {
        let b = sel.originalBounds
        var out = PixelGrid(size: sel.pixels.size)
        for r in 0..<b.height {
            for x in b.x..<(b.x + b.width) {
                let color = sel.pixels.pixel(x: x, y: b.y + r)
                out.setPixel(x: x, y: b.y + (b.height - 1 - r), color: color)
            }
        }
        return ExtractedSelection(originalBounds: b, pixels: out)
    }

    /// Rotate the selection's content 90° clockwise, pivoting around `center` (absolute canvas
    /// coords — pass the on-screen display center so it spins where the user sees it). The new
    /// bounds swap width/height and are clamped fully onto the canvas.
    ///
    /// **Fit-or-refuse:** returns `nil` if the rotated selection can't fit the canvas (only
    /// possible on a non-square canvas, e.g. a selection wider than the canvas is tall). The caller
    /// no-ops rather than clipping — DrawBit never silently drops pixels. On a square canvas any
    /// contained selection always fits, so it never refuses there.
    static func rotate90(_ sel: ExtractedSelection, around center: (x: Int, y: Int)) -> ExtractedSelection? {
        let b = sel.originalBounds
        let canvas = sel.pixels.size
        let newW = b.height
        let newH = b.width
        guard newW <= canvas.width, newH <= canvas.height else { return nil }

        // Center the rotated block on `center`, then clamp so it sits fully on the canvas.
        let newX = Swift.min(Swift.max(0, center.x - newW / 2), canvas.width - newW)
        let newY = Swift.min(Swift.max(0, center.y - newH / 2), canvas.height - newH)

        var out = PixelGrid(size: canvas)
        for r in 0..<b.height {
            for c in 0..<b.width {
                // Clockwise: source local (c, r) -> dest local (height-1-r, c).
                let color = sel.pixels.pixel(x: b.x + c, y: b.y + r)
                out.setPixel(x: newX + (b.height - 1 - r), y: newY + c, color: color)
            }
        }
        return ExtractedSelection(originalBounds: PixelRect(x: newX, y: newY, width: newW, height: newH),
                                  pixels: out)
    }
}
