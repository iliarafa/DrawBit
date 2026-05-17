import XCTest
import ImageIO
@testable import DrawBit

final class GIFExporterTests: XCTestCase {
    private func makeFrame(name: String, byteCount: Int, fill: UInt8 = 255) -> Frame {
        let layer = Layer(name: "L", pixels: Data(repeating: fill, count: byteCount))
        return Frame(name: name, layers: [layer], activeLayerID: layer.id)
    }

    func testExportProducesGIFWithFrameCount() throws {
        let bytes = CanvasSize.s32.byteCount
        let frames = (1...4).map { makeFrame(name: "F\($0)", byteCount: bytes) }
        let data = try XCTUnwrap(GIFExporter.export(frames: frames, size: .s32, scale: 4, fps: 12))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(src), 4)
        XCTAssertEqual(CGImageSourceGetType(src), "com.compuserve.gif" as CFString)
    }

    func testExportEncodesLoopCountInfinite() throws {
        let bytes = CanvasSize.s32.byteCount
        let frames = (1...2).map { makeFrame(name: "F\($0)", byteCount: bytes) }
        let data = try XCTUnwrap(GIFExporter.export(frames: frames, size: .s32, scale: 1, fps: 24))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = CGImageSourceCopyProperties(src, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let loop = gif?[kCGImagePropertyGIFLoopCount] as? Int
        XCTAssertEqual(loop, 0, "loop count of 0 means infinite")
    }

    func testExportEncodesPerFrameDelayMatchingFPS() throws {
        let bytes = CanvasSize.s32.byteCount
        let frames = (1...2).map { makeFrame(name: "F\($0)", byteCount: bytes) }
        let data = try XCTUnwrap(GIFExporter.export(frames: frames, size: .s32, scale: 1, fps: 10))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = gif?[kCGImagePropertyGIFDelayTime] as? Double
        XCTAssertNotNil(delay)
        // Stored may differ in fp precision; assert close to 1/10 = 0.1.
        XCTAssertEqual(delay ?? 0, 0.1, accuracy: 0.01)
    }

    func testExportScalesToTargetEdge() throws {
        let bytes = CanvasSize.s32.byteCount
        let frames = [makeFrame(name: "F", byteCount: bytes)]
        let data = try XCTUnwrap(GIFExporter.export(frames: frames, size: .s32, scale: 4, fps: 12))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 32 * 4)
        XCTAssertEqual(img.height, 32 * 4)
    }

    func testEmptyFramesReturnsNil() throws {
        XCTAssertNil(try GIFExporter.export(frames: [], size: .s32, scale: 1, fps: 12))
    }

    func testInvalidScaleReturnsNil() throws {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        XCTAssertNil(try GIFExporter.export(frames: frames, size: .s32, scale: 0, fps: 12))
    }

    func testInvalidFPSReturnsNil() throws {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        XCTAssertNil(try GIFExporter.export(frames: frames, size: .s32, scale: 1, fps: 0))
    }

    func testSingleFrameExports() throws {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        let data = try XCTUnwrap(GIFExporter.export(frames: frames, size: .s32, scale: 1, fps: 12))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(src), 1)
    }

    /// GIF has only a single transparent palette index (no real alpha), but
    /// DrawBit's pixel model is binary 0-or-255 alpha, which maps cleanly onto
    /// that. Verify ImageIO's encoder picks up the transparent pixels and
    /// round-trips them as transparent at the byte level.
    func testGIFPreservesBinaryTransparency() throws {
        // 16×16 frame: pixel (0,0) opaque green, pixel (1,0) transparent.
        var pixels = Data(count: CanvasSize.s16.byteCount)
        pixels[0] = 0; pixels[1] = 200; pixels[2] = 0; pixels[3] = 255
        let layer = Layer(name: "L", pixels: pixels)
        let frame = Frame(name: "F", layers: [layer], activeLayerID: layer.id)
        let data = try XCTUnwrap(GIFExporter.export(frames: [frame], size: .s16, scale: 1, fps: 12))

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
        XCTAssertEqual(out[3], 255, "opaque pixel must remain opaque after GIF round-trip")
        XCTAssertEqual(out[7], 0, "transparent pixel must remain transparent after GIF round-trip")
    }
}
