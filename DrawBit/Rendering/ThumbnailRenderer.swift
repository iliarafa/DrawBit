import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ThumbnailRenderer {
    /// PNG-encoded thumbnail bytes. Used by `PieceRepository` to persist a piece's
    /// gallery thumbnail. UI views should prefer `renderCGImage` to skip the
    /// encode/decode roundtrip.
    static func render(frame: Frame, size: CanvasSize, targetEdge: Int) -> Data? {
        guard let image = renderCGImage(frame: frame, size: size, targetEdge: targetEdge) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Composited + downsampled CGImage at the requested edge length. UI hot paths
    /// (FrameRow, LayerRow, anywhere a thumbnail is rebuilt every layout pass)
    /// should call this and wrap with `UIImage(cgImage:)` rather than going through
    /// the PNG bytes — encoding + decoding adds ~3× overhead per call for no gain
    /// when the consumer is an in-process UIImage.
    static func renderCGImage(frame: Frame, size: CanvasSize, targetEdge: Int) -> CGImage? {
        guard targetEdge > 0 else { return nil }
        let buffer = Compositor.composite(frame, size: size)
        guard let source = bufferToCGImage(buffer) else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        // Preserve the canvas aspect: `targetEdge` is the LONGEST edge; the short edge
        // scales down proportionally. Square → targetEdge×targetEdge (unchanged). The
        // gallery tile then letterboxes a non-square thumbnail against its own dark
        // background (no bands baked into the image).
        let longest = max(size.width, size.height)
        let outW = max(1, targetEdge * size.width / longest)
        let outH = max(1, targetEdge * size.height / longest)

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

        return ctx.makeImage()
    }
}
