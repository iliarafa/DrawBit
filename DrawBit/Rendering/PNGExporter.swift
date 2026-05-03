import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PNGExporter {
    static func export(frame: Frame, size: CanvasSize, scale: Int) -> Data? {
        guard scale >= 1 else { return nil }
        let buffer = Compositor.composite(frame, size: size)
        guard let source = bufferToCGImage(buffer) else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let outEdge = size.dimension * scale
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
