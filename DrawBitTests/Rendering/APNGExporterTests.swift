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

    func testEmptyFramesReturnsNil() {
        XCTAssertNil(APNGExporter.export(frames: [], size: .s32, scale: 1, fps: 12))
    }

    func testInvalidScaleReturnsNil() {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        XCTAssertNil(APNGExporter.export(frames: frames, size: .s32, scale: 0, fps: 12))
    }

    func testInvalidFPSReturnsNil() {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        XCTAssertNil(APNGExporter.export(frames: frames, size: .s32, scale: 1, fps: 0))
    }

    func testSingleFrameExports() throws {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        let data = try XCTUnwrap(APNGExporter.export(frames: frames, size: .s32, scale: 1, fps: 12))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(src), 1)
    }

    /// APNG preserves alpha (unlike GIF). Verify a transparent pixel survives the round-trip.
    func testAPNGPreservesAlpha() throws {
        // Frame with all-transparent pixels (alpha 0).
        let bytes = CanvasSize.s32.byteCount
        let frame = makeFrame(name: "F", byteCount: bytes, fill: 0)  // all RGBA = 0
        let data = try XCTUnwrap(APNGExporter.export(frames: [frame], size: .s32, scale: 1, fps: 12))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let alphaInfo = img.alphaInfo
        XCTAssertNotEqual(alphaInfo, .none,
                          "APNG must preserve alpha channel; saw \(alphaInfo)")
    }
}
