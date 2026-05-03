import CoreGraphics
import Foundation

/// Compatibility shim: wraps a PixelGrid directly as a single-layer CGImage.
/// CanvasView still uses this name; Task 1.14 will migrate CanvasView to Compositor.
func pixelsToCGImage(_ grid: PixelGrid) -> CGImage? {
    let layer = Layer(name: "Layer 1", pixels: grid.data)
    let frame = Frame(layers: [layer], activeLayerID: layer.id)
    let buffer = Compositor.composite(frame, size: grid.size)
    return bufferToCGImage(buffer)
}

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
