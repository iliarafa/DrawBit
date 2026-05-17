import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DrawBit

/// Round-trip + smoke coverage for `PNGExporter.export(frame:size:scale:)` on a
/// single-layer frame.
///
/// Originally (Layers v2 Stage 1) this file compared the new frame-based export
/// against a hand-rolled v1 reference path to prove byte-identity for all four
/// canvas sizes × four export scales. With Layers v2 and Animation v1 both shipped
/// and the export path stable across both features, the v1 reference is gone and
/// this file now tests the export path on its own terms:
///
/// 1. A pixel-byte decode-round-trip at scale 1, which catches any silent corruption
///    in the encode/decode chain (color space drift, premultiplication bugs, etc.).
/// 2. A smoke test that every supported size × scale combination produces non-empty
///    PNG bytes, catching catastrophic failures in any combo.
final class SingleLayerNonRegressionTests: XCTestCase {
    /// Patterned grid where transparent pixels are also RGB-zero. This mirrors what
    /// the app itself produces (the eraser writes `RGBA.transparent` = all zero), and
    /// matches the round-trip property of `.premultipliedLast` Core Graphics contexts,
    /// which zero the RGB channels of alpha-0 pixels on draw.
    private func patternedGrid(size: CanvasSize) -> PixelGrid {
        var data = Data(count: size.byteCount)
        let dim = size.dimension
        for y in 0..<dim {
            for x in 0..<dim {
                let i = (y * dim + x) * 4
                let opaque = (x + y) % 3 != 0
                data[i    ] = opaque ? UInt8((x * 8) & 0xFF) : 0
                data[i + 1] = opaque ? UInt8((y * 8) & 0xFF) : 0
                data[i + 2] = opaque ? UInt8((x ^ y) & 0xFF) : 0
                data[i + 3] = opaque ? 255 : 0
            }
        }
        return PixelGrid(data: data, size: size)
    }

    /// Encode a single-layer frame to PNG, decode it back, rasterize into a known
    /// RGBA buffer, and assert pixel bytes are exactly preserved. Stronger than
    /// the historic v1-vs-v2 byte comparison because it proves correctness end-to-end
    /// rather than just "matches the other implementation".
    func testSingleLayerExportRoundTripsAtScale1() throws {
        for size in [CanvasSize.s16, .s32, .s64, .s128] {
            let grid = patternedGrid(size: size)
            let layer = Layer(name: "Layer 1", pixels: grid.data)
            let frame = Frame(layers: [layer], activeLayerID: layer.id)

            let png = try XCTUnwrap(
                PNGExporter.export(frame: frame, size: size, scale: 1),
                "Export returned nil for \(size.displayName)"
            )

            // Decode the PNG and rasterize into a known-shape RGBA buffer.
            let src = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
            let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))

            let dim = size.dimension
            let bytesPerRow = dim * 4
            var out = [UInt8](repeating: 0, count: bytesPerRow * dim)
            out.withUnsafeMutableBytes { buf in
                guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
                      let ctx = CGContext(
                        data: buf.baseAddress,
                        width: dim, height: dim,
                        bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                        space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      )
                else {
                    XCTFail("Failed to make read-back context for \(size.displayName)")
                    return
                }
                ctx.interpolationQuality = .none
                ctx.setShouldAntialias(false)
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: dim, height: dim))
            }

            XCTAssertEqual(out, [UInt8](grid.data),
                "Pixel bytes diverged after PNG round-trip for \(size.displayName)")
        }
    }

    /// Smoke test: every supported size × scale combination produces a non-empty
    /// PNG. Catches a regression where one combo silently returns nil (e.g. a
    /// CGContext failure for a specific dimension).
    func testSingleLayerExportProducesValidPNGAtAllSizesAndScales() {
        for size in [CanvasSize.s16, .s32, .s64, .s128] {
            let grid = patternedGrid(size: size)
            let layer = Layer(name: "Layer 1", pixels: grid.data)
            let frame = Frame(layers: [layer], activeLayerID: layer.id)

            for scale in [1, 2, 4, 8] {
                let png = PNGExporter.export(frame: frame, size: size, scale: scale)
                XCTAssertNotNil(png, "Export returned nil for \(size.displayName) @ \(scale)x")
                XCTAssertGreaterThan(png?.count ?? 0, 0,
                                     "Export returned empty Data for \(size.displayName) @ \(scale)x")
            }
        }
    }
}
