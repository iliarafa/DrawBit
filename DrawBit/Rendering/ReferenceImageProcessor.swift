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
    static func process(_ data: Data, maxEdge: Int = maxEdge, quality: CGFloat = 0.8) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData,
                                                          UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, thumb,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
