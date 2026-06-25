import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes a `[Frame]` sequence as an animated GIF using ImageIO's multi-image
/// destination. The output loops infinitely; per-frame delay is `1.0 / fps`.
///
/// **Alpha caveat:** GIF has a single transparent palette index — not real alpha.
/// ImageIO's encoder will pick a transparent slot itself, but pixels with partial
/// alpha get clipped to either fully-opaque or fully-transparent. DrawBit's pixel
/// model is straight 0-or-255 alpha (`Eraser` writes `RGBA.transparent` exactly,
/// drawing tools never produce partial alpha — see `CLAUDE.md`), so this works
/// correctly. APNG is the right choice when alpha precision matters; see
/// `APNGExporter`.
///
/// **Color space:** sRGB explicitly (matches `pixelsToCGImage` and `PNGExporter`),
/// not deviceRGB — on P3 displays deviceRGB silently bakes wide-gamut values into
/// the encoded output.
enum GIFExporter {
    /// Throws `CancellationError` if the surrounding `Task` is cancelled between frames.
    /// Returns `nil` on encode failure (bad inputs, CG context creation, finalize failure).
    static func export(frames: [Frame], size: CanvasSize, scale: Int, fps: Int) throws -> Data? {
        guard !frames.isEmpty, scale >= 1, fps >= 1 else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let outW = size.width * scale
        let outH = size.height * scale
        let delay = 1.0 / Double(fps)

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.gif.identifier as CFString, frames.count, nil
        ) else { return nil }

        let fileProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
        ]

        for frame in frames {
            // Allow the caller to bail between frames — for a 60-frame 4× export
            // the per-frame work isn't tiny, so cancellation matters.
            try Task.checkCancellation()
            let buffer = Compositor.composite(frame, size: size)
            guard let source = bufferToCGImage(buffer) else { return nil }
            guard let ctx = CGContext(
                data: nil,
                width: outW,
                height: outH,
                bitsPerComponent: 8,
                bytesPerRow: outW * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: outW, height: outH))
            guard let scaledImage = ctx.makeImage() else { return nil }
            CGImageDestinationAddImage(dest, scaledImage, frameProps as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
