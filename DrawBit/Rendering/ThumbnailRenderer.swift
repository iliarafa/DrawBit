import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ThumbnailRenderer {
    static func render(frame: Frame, size: CanvasSize, targetEdge: Int) -> Data? {
        let buffer = Compositor.composite(frame, size: size)
        guard let source = bufferToCGImage(buffer) else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: targetEdge,
            height: targetEdge,
            bitsPerComponent: 8,
            bytesPerRow: targetEdge * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: targetEdge, height: targetEdge))

        guard let image = ctx.makeImage() else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
