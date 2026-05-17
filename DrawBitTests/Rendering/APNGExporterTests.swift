import XCTest
import ImageIO
@testable import DrawBit

final class APNGExporterTests: XCTestCase {
    private func makeFrame(name: String, byteCount: Int, fill: UInt8 = 255) -> Frame {
        let layer = Layer(name: "L", pixels: Data(repeating: fill, count: byteCount))
        return Frame(name: name, layers: [layer], activeLayerID: layer.id)
    }

    func testExportProducesAPNGWithFrameCount() throws {
        let bytes = CanvasSize.s32.byteCount
        let frames = (1...3).map { makeFrame(name: "F\($0)", byteCount: bytes) }
        let data = try XCTUnwrap(APNGExporter.export(frames: frames, size: .s32, scale: 2, fps: 24))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(src), 3)
        XCTAssertEqual(CGImageSourceGetType(src), "public.png" as CFString)
    }

    func testExportEncodesAPNGLoopCountInfinite() throws {
        let bytes = CanvasSize.s32.byteCount
        let frames = (1...2).map { makeFrame(name: "F\($0)", byteCount: bytes) }
        let data = try XCTUnwrap(APNGExporter.export(frames: frames, size: .s32, scale: 1, fps: 24))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = CGImageSourceCopyProperties(src, nil) as? [CFString: Any]
        let png = props?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let loop = png?[kCGImagePropertyAPNGLoopCount] as? Int
        XCTAssertEqual(loop, 0, "loop count of 0 means infinite")
    }

    func testExportEncodesAPNGPerFrameDelay() throws {
        let bytes = CanvasSize.s32.byteCount
        let frames = (1...2).map { makeFrame(name: "F\($0)", byteCount: bytes) }
        let data = try XCTUnwrap(APNGExporter.export(frames: frames, size: .s32, scale: 1, fps: 8))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let png = props?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let delay = png?[kCGImagePropertyAPNGDelayTime] as? Double
        XCTAssertNotNil(delay)
        XCTAssertEqual(delay ?? 0, 0.125, accuracy: 0.01)
    }

    func testExportScalesToTargetEdge() throws {
        let bytes = CanvasSize.s32.byteCount
        let frames = [makeFrame(name: "F", byteCount: bytes)]
        let data = try XCTUnwrap(APNGExporter.export(frames: frames, size: .s32, scale: 4, fps: 12))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 32 * 4)
        XCTAssertEqual(img.height, 32 * 4)
    }

    func testEmptyFramesReturnsNil() throws {
        XCTAssertNil(try APNGExporter.export(frames: [], size: .s32, scale: 1, fps: 12))
    }

    func testInvalidScaleReturnsNil() throws {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        XCTAssertNil(try APNGExporter.export(frames: frames, size: .s32, scale: 0, fps: 12))
    }

    func testInvalidFPSReturnsNil() throws {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        XCTAssertNil(try APNGExporter.export(frames: frames, size: .s32, scale: 1, fps: 0))
    }

    func testSingleFrameExports() throws {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        let data = try XCTUnwrap(APNGExporter.export(frames: frames, size: .s32, scale: 1, fps: 12))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(src), 1)
    }

    /// APNG preserves alpha (unlike GIF). Verify a transparent pixel survives the
    /// round-trip at the byte level — not just that the encoder declared an alpha
    /// channel. Construct a 4-pixel frame mixing transparent and opaque; encode,
    /// decode, draw the decoded image into a known-shape RGBA buffer, and assert
    /// the alpha bytes are preserved at exact-zero and exact-255.
    func testAPNGPreservesAlphaAtPixelLevel() throws {
        // Build a 16×16 frame manually: pixel (0,0) opaque red, pixel (1,0) transparent.
        var pixels = Data(count: CanvasSize.s16.byteCount)
        // (0,0): RGBA = 255, 0, 0, 255 (opaque red)
        pixels[0] = 255; pixels[1] = 0; pixels[2] = 0; pixels[3] = 255
        // (1,0): RGBA = 0, 0, 0, 0 (fully transparent)
        // (already zero from Data(count:))
        let layer = Layer(name: "L", pixels: pixels)
        let frame = Frame(name: "F", layers: [layer], activeLayerID: layer.id)
        let data = try XCTUnwrap(APNGExporter.export(frames: [frame], size: .s16, scale: 1, fps: 12))

        // Decode and rasterize into a known RGBA buffer so we can read pixel bytes.
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))

        let dim = 16
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
                XCTFail("failed to make read-back context")
                return
            }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: dim, height: dim))
        }

        // Pixel (0,0) at offset 0: should still be opaque red.
        XCTAssertEqual(out[3], 255, "opaque pixel must round-trip with alpha=255")
        XCTAssertEqual(out[0], 255, "opaque red R")
        // Pixel (1,0) at offset 4: should still be fully transparent.
        XCTAssertEqual(out[7], 0, "transparent pixel must round-trip with alpha=0")
    }
}
