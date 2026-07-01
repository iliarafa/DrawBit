import Foundation

/// Pre-flight check for `ShareSheet` — given a chosen (format, canvas size, scale,
/// frame count), tells the UI whether the resulting export would either
///
/// 1. blow past the practical iOS CGContext allocation cap (~8192 × 8192 — beyond
///    that, `CGContext(width:height:…)` very often returns `nil`), or
/// 2. for animated formats, accumulate more raw uncompressed frame data than the
///    encoder can hold without real jetsam risk.
///
/// The exporters in `DrawBit/Rendering/` already return `nil` correctly when CG
/// can't allocate — the bug this guards against is purely in `ShareSheet`: the
/// share UI silently does nothing on that nil, so the user sees no error banner,
/// no toast, no share popover. Worst case today is `SpriteSheetExporter` at
/// `s128 × scale=16 × 64 frames` → an 8 × 8 grid of 2048 px cells = 16384 ×
/// 16384, which CG won't allocate. We gray that tile out instead.
enum ExportSizeBudget {
    /// Hard cap on either dimension of a single CGContext (8192 px). Beyond this
    /// `CGContext.init` reliably fails on iOS — confirmed by the sprite-sheet
    /// worst case noted above. Edge-equals-cap is treated as still safe (≤).
    static let maxContextEdge: Int = 8192

    /// Soft cap on the cumulative raw RGBA bytes an animated encoder
    /// (`GIFExporter` / `APNGExporter`) walks through before finalize — past
    /// ~256 MB the app is at real jetsam risk during the encode. Each
    /// individual per-frame CGContext inside that loop is already bounded by
    /// `maxContextEdge`; this guards the accumulated `NSMutableData` /
    /// per-frame snapshots living in memory at the same time.
    static let maxAnimatedTotalBytes: Int = 256 * 1024 * 1024

    /// Mirror of the four output formats `ShareSheet.ExportFormat` exposes — kept
    /// in a separate enum here so this file stays Foundation-only and is trivial
    /// to test without pulling in SwiftUI or any view dependency.
    enum Format {
        case png, gif, apng, spriteSheet, film
    }

    /// Worst-case output dimensions in pixels. PNG / GIF / APNG produce a single
    /// `cellEdge × cellEdge` context per frame; sprite sheet packs N cells into
    /// a square-ish grid that matches `SpriteSheetExporter.export`'s layout
    /// formula exactly.
    static func outputDimensions(
        format: Format,
        canvasWidth: Int,
        canvasHeight: Int,
        scale: Int,
        frameCount: Int
    ) -> (width: Int, height: Int) {
        let cellW = max(0, canvasWidth) * max(0, scale)
        let cellH = max(0, canvasHeight) * max(0, scale)
        switch format {
        case .png, .gif, .apng, .film:
            // Film is a single-cell frame per keyframe (the writer streams them);
            // its worst-case allocation is one output-sized context, same as PNG.
            return (cellW, cellH)
        case .spriteSheet:
            let (cols, rows) = spriteSheetGrid(frameCount: frameCount)
            return (cellW * cols, cellH * rows)
        }
    }

    /// Same `columns = round(sqrt(N))`, `rows = ceil(N / columns)` math as
    /// `SpriteSheetExporter.export` (`DrawBit/Rendering/SpriteSheetExporter.swift:28-33`).
    /// Returns (0, 0) for an empty frame list — the exporter would already
    /// short-circuit to `nil`, the predicate just needs to not crash.
    static func spriteSheetGrid(frameCount: Int) -> (cols: Int, rows: Int) {
        guard frameCount > 0 else { return (0, 0) }
        let cols = max(1, min(frameCount,
                              Int(Double(frameCount).squareRoot().rounded())))
        let rows = (frameCount + cols - 1) / cols
        return (cols, rows)
    }

    /// `true` if a real export at this (format, canvasEdge, scale, frameCount) is
    /// likely to fail or jetsam. `ShareSheet` should disable the corresponding
    /// scale tile and surface a "TOO BIG" sublabel when this returns `true`.
    /// Empty / zero-frame inputs are treated as safe (nothing to allocate).
    static func isOverBudget(
        format: Format,
        canvasWidth: Int,
        canvasHeight: Int,
        scale: Int,
        frameCount: Int
    ) -> Bool {
        guard frameCount > 0 else { return false }
        let cellW = max(0, canvasWidth) * max(0, scale)
        let cellH = max(0, canvasHeight) * max(0, scale)
        let (outW, outH) = outputDimensions(
            format: format, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
            scale: scale, frameCount: frameCount
        )
        if outW > maxContextEdge || outH > maxContextEdge {
            return true
        }
        switch format {
        case .gif, .apng:
            // Per-frame context is bounded by `cellW × cellH × 4`; the accumulated
            // encoder state is roughly proportional to `frameCount × that`. Guard
            // against multiplication overflow on absurd inputs so it never traps.
            let perFrameBytes = cellW &* cellH &* 4
            let (total, overflow) = perFrameBytes
                .multipliedReportingOverflow(by: frameCount)
            if overflow { return true }
            return total > maxAnimatedTotalBytes
        case .png, .spriteSheet, .film:
            // Film (MP4) streams frame-by-frame through AVAssetWriter, so there's no
            // accumulated raw-RGBA jetsam risk like GIF/APNG — only the per-frame
            // context, already bounded by `maxContextEdge` above.
            return false
        }
    }
}
