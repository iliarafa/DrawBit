import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes a `[Frame]` sequence as an Animated PNG (APNG) using ImageIO's
/// multi-image PNG destination. Loops infinitely; per-frame delay is `1.0 / fps`.
///
/// Unlike GIF, APNG carries true 8-bit alpha — pixels with `alpha = 0` round-trip
/// as transparent without quantization. Prefer APNG when the piece relies on
/// transparency. iOS / Safari / Chrome all play APNG natively. Photos shows the
/// first frame as a still preview.
///
/// Color space is explicit sRGB (matches `pixelsToCGImage` and `PNGExporter`),
/// not deviceRGB — on P3 displays deviceRGB silently bakes wide-gamut values
/// into the encoded output.
enum APNGExporter {
    /// Throws `CancellationError` if the surrounding `Task` is cancelled between frames.
    /// Returns `nil` on encode failure (bad inputs, CG context creation, finalize failure).
    static func export(frames: [Frame], size: CanvasSize, scale: Int, fps: Int) throws -> Data? {
        guard !frames.isEmpty, scale >= 1, fps >= 1 else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let outEdge = size.dimension * scale
        let delay = 1.0 / Double(fps)

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, frames.count, nil
        ) else { return nil }

        let fileProps: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
        ]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let frameProps: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]
        ]

        for frame in frames {
            // Allow the caller to bail between frames — for a 60-frame 4× export
            // the per-frame work isn't tiny, so cancellation matters.
            try Task.checkCancellation()
            let buffer = Compositor.composite(frame, size: size)
            guard let source = bufferToCGImage(buffer) else { return nil }
            guard let ctx = CGContext(
                data: nil,
                width: outEdge,
                height: outEdge,
                bitsPerComponent: 8,
                bytesPerRow: outEdge * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: outEdge, height: outEdge))
            guard let scaledImage = ctx.makeImage() else { return nil }
            CGImageDestinationAddImage(dest, scaledImage, frameProps as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
