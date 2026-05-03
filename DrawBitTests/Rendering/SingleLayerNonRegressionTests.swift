import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DrawBit

final class SingleLayerNonRegressionTests: XCTestCase {
    /// Reference v1-style export: takes a raw PixelGrid and produces a PNG via the historic
    /// path (CGImage made from PixelGrid bytes directly, drawn into a CGContext at the target
    /// scale). This is held alongside the new code for the lifetime of the layers work and
    /// removed in a follow-up commit once all stages have shipped.
    private func v1ExportPNG(grid: PixelGrid, scale: Int) -> Data? {
        let dim = grid.dimension
        guard scale >= 1 else { return nil }
        guard let provider = CGDataProvider(data: grid.data as CFData) else { return nil }
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info: CGBitmapInfo = [CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)]
        guard let src = CGImage(width: dim, height: dim, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: dim * 4, space: cs, bitmapInfo: info, provider: provider,
                                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return nil
        }
        let outEdge = dim * scale
        guard let ctx = CGContext(data: nil, width: outEdge, height: outEdge, bitsPerComponent: 8,
                                  bytesPerRow: outEdge * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: outEdge, height: outEdge))
        guard let img = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private func patternedGrid(size: CanvasSize) -> PixelGrid {
        var data = Data(count: size.byteCount)
        let dim = size.dimension
        for y in 0..<dim {
            for x in 0..<dim {
                let i = (y * dim + x) * 4
                data[i    ] = UInt8((x * 8) & 0xFF)
                data[i + 1] = UInt8((y * 8) & 0xFF)
                data[i + 2] = UInt8((x ^ y) & 0xFF)
                data[i + 3] = ((x + y) % 3 == 0) ? 0 : 255
            }
        }
        return PixelGrid(data: data, size: size)
    }

    func testSingleLayerExportMatchesV1ForAllSizesAndScales() {
        for size in [CanvasSize.s16, .s32, .s64, .s128] {
            let grid = patternedGrid(size: size)
            let layer = Layer(name: "Layer 1", pixels: grid.data)
            let goodFrame = Frame(layers: [layer], activeLayerID: layer.id)

            for scale in [1, 2, 4, 8] {
                guard let v1 = v1ExportPNG(grid: grid, scale: scale) else {
                    XCTFail("v1 export failed for \(size) @ \(scale)x"); continue
                }
                guard let v2 = PNGExporter.export(frame: goodFrame, size: size, scale: scale) else {
                    XCTFail("v2 export failed for \(size) @ \(scale)x"); continue
                }
                XCTAssertEqual(v1, v2,
                    "PNG bytes diverged at \(size.displayName) @ \(scale)x — non-regression failed")
            }
        }
    }
}
