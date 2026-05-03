import CoreGraphics
import Foundation

/// Wraps a CompositedBuffer's raw RGBA bytes in a CGImage. Uses sRGB explicitly (NEVER deviceRGB) so
/// rendering and export are consistent across iPad models including P3 displays.
func bufferToCGImage(_ buffer: CompositedBuffer) -> CGImage? {
    let dim = buffer.size.dimension
    let bytesPerRow = dim * 4

    guard let provider = CGDataProvider(data: buffer.data as CFData) else { return nil }
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let bitmapInfo: CGBitmapInfo = [
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    ]

    return CGImage(
        width: dim,
        height: dim,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}
