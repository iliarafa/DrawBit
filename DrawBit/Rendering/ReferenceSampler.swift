import CoreGraphics
import Foundation
import ImageIO

/// Renders the tracing reference image down onto the canvas grid so the eyedropper can sample it.
/// Pure CoreGraphics: explicit sRGB, nearest-neighbor, aspect-fit + centered (matches the
/// `.scaledToFit()` backdrop in `CanvasView`). Letterbox/pillarbox areas stay transparent; the
/// image area is opaque with the reference's true colors; alpha is forced to 0/255 to preserve the
/// straight-alpha invariant. The result is transient (sampled on pick) — never a `Layer`, never exported.
enum ReferenceSampler {
    /// The aspect-fit, centered rect for an `imageW × imageH` image inside a `canvasW × canvasH` grid.
    static func aspectFitRect(imageW: Int, imageH: Int, canvasW: Int, canvasH: Int) -> CGRect {
        guard imageW > 0, imageH > 0, canvasW > 0, canvasH > 0 else { return .zero }
        let iw = CGFloat(imageW), ih = CGFloat(imageH), cw = CGFloat(canvasW), ch = CGFloat(canvasH)
        let scale = min(cw / iw, ch / ih)
        let fw = iw * scale, fh = ih * scale
        return CGRect(x: (cw - fw) / 2, y: (ch - fh) / 2, width: fw, height: fh)
    }

    static func renderToCanvasGrid(_ image: CGImage, size: CanvasSize) -> Data {
        let w = size.width, h = size.height
        var out = Data(count: size.byteCount)   // zeroed → letterbox stays transparent
        out.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let srgb = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: srgb,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)
            // No vertical flip: a top-left CGImage (raw provider or CGImageSource-decoded) drawn into
            // this bitmap context lands top-down in memory, matching PixelGrid and the on-screen
            // backdrop. (A flip here mirrors it — see ReferenceSamplerTests.testRenderOrientation…)
            ctx.draw(image, in: aspectFitRect(imageW: image.width, imageH: image.height,
                                              canvasW: w, canvasH: h))
        }
        enforceBinaryAlpha(&out)
        return out
    }

    static func renderToCanvasGrid(_ imageData: Data, size: CanvasSize) -> Data? {
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return renderToCanvasGrid(image, size: size)
    }

    /// Quantize every alpha byte to 0 or 255. The reference is an opaque JPEG in practice; this
    /// guards any anti-aliased/transparent edge from drifting into partial alpha.
    private static func enforceBinaryAlpha(_ data: inout Data) {
        data.withUnsafeMutableBytes { raw in
            guard let p = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var i = 3
            while i < raw.count {
                if p[i] >= 128 {
                    p[i] = 255
                } else {
                    p[i - 3] = 0; p[i - 2] = 0; p[i - 1] = 0; p[i] = 0
                }
                i += 4
            }
        }
    }
}
