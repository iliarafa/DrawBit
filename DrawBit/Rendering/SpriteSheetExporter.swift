import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Composes a `[Frame]` sequence into a single PNG sprite sheet using a best-fit
/// square-ish grid. Frames are laid out left-to-right, top-to-bottom in input order.
///
/// **Layout formula** (after Piskel's `PngExportController`):
/// ```
/// columns = clamp(round(sqrt(N / aspectRatio)), 1, N)
/// rows    = ceil(N / columns)
/// ```
/// DrawBit canvases are square, so `aspectRatio = 1`. Empty cells (when N isn't a
/// perfect column-count multiple) are fully transparent — matches the alpha
/// invariant from `Compositor`.
///
/// **Color space:** sRGB explicitly (matches `PNGExporter`, `GIFExporter`,
/// `APNGExporter`), not deviceRGB.
///
/// **Nearest-neighbor:** `interpolationQuality = .none` and antialiasing off on
/// the upscale context.
enum SpriteSheetExporter {
    /// Best-fit square-ish grid for `count` frames. Shared with the export-sheet preview so the
    /// preview layout matches the written sheet exactly. Square canvas → `aspectRatio = 1`:
    /// `columns = clamp(round(sqrt(N)), 1, N)`, `rows = ceil(N / columns)`.
    static func grid(count: Int) -> (columns: Int, rows: Int) {
        guard count > 0 else { return (1, 1) }
        let columns = max(1, min(count, Int(Double(count).squareRoot().rounded())))
        let rows = (count + columns - 1) / columns
        return (columns, rows)
    }

    static func export(frames: [Frame], size: CanvasSize, scale: Int) -> Data? {
        guard !frames.isEmpty, scale >= 1 else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let count = frames.count
        let (columns, rows) = grid(count: count)
        let cellWidth = size.width * scale
        let cellHeight = size.height * scale
        let outWidth = cellWidth * columns
        let outHeight = cellHeight * rows

        guard let ctx = CGContext(
            data: nil,
            width: outWidth,
            height: outHeight,
            bitsPerComponent: 8,
            bytesPerRow: outWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)

        // CGContext's coordinate system is bottom-up — but the user mental model
        // (and Piskel's) is top-down. Flip vertically by computing y from the bottom.
        for (idx, frame) in frames.enumerated() {
            let col = idx % columns
            let row = idx / columns
            let buffer = Compositor.composite(frame, size: size)
            guard let cg = bufferToCGImage(buffer) else { return nil }
            let x = col * cellWidth
            // Top-left at (col, row) in display coords; CGContext y=0 is the bottom,
            // so flip: y = outHeight - (row + 1) * cellHeight.
            let y = outHeight - (row + 1) * cellHeight
            ctx.draw(cg, in: CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
        }

        guard let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
