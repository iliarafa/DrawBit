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

    func testEmptyFramesReturnsNil() {
        XCTAssertNil(GIFExporter.export(frames: [], size: .s32, scale: 1, fps: 12))
    }

    func testInvalidScaleReturnsNil() {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        XCTAssertNil(GIFExporter.export(frames: frames, size: .s32, scale: 0, fps: 12))
    }

    func testInvalidFPSReturnsNil() {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        XCTAssertNil(GIFExporter.export(frames: frames, size: .s32, scale: 1, fps: 0))
    }

    func testSingleFrameExports() throws {
        let frames = [makeFrame(name: "F", byteCount: CanvasSize.s32.byteCount)]
        let data = try XCTUnwrap(GIFExporter.export(frames: frames, size: .s32, scale: 1, fps: 12))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(src), 1)
    }
}
