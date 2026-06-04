import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Pure helper that re-encodes an arbitrary imported image into a size-capped JPEG,
/// suitable for storing as a piece's tracing reference. Lives in the Rendering layer:
/// imports only Foundation / ImageIO / CoreGraphics — no UIKit, no SwiftData — per the
/// pure-logic rule. The display `UIImage` is built in the State/View layer from this Data.
enum ReferenceImageProcessor {
    /// Longest-edge cap (px) for the stored reference. 1024 is ample detail behind a
    /// canvas of at most 128px and keeps external-storage blobs small.
    static let maxEdge = 1024

    /// Downscales `data` so its longest edge is <= `maxEdge` and re-encodes as JPEG.
    /// Never upscales: a source already within the cap is returned at its native size.
    /// Returns nil if `data` can't be decoded as an image.
    static func process(_ data: Data, maxEdge: Int = Self.maxEdge, quality: CGFloat = 0.8) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        // Re-draw into an explicit sRGB context so the stored JPEG is always sRGB, never
        // wide-gamut. The rest of the Rendering layer pins sRGB for the same reason (see
        // PNGExporter / ThumbnailRenderer); a Display-P3 source would otherwise carry its
        // wide-gamut profile into the reference and drift from the axis-aligned exports.
        // Dimensions are preserved (context matches the thumbnail's pixel size).
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil,
                                  width: thumb.width,
                                  height: thumb.height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: thumb.width, height: thumb.height))
        guard let normalized = ctx.makeImage() else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData,
                                                          UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, normalized,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
