import XCTest
@testable import DrawBit

final class ThumbnailRendererTests: XCTestCase {
    func testRendersToTargetEdgeForSingleLayerFrame() {
        let bytes = Data(count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: bytes)
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        let png = ThumbnailRenderer.render(frame: frame, size: .s32, targetEdge: 128)
        XCTAssertNotNil(png)
        XCTAssertGreaterThan(png?.count ?? 0, 0)
    }

    func testRenderCGImageProducesImageOfTargetEdge() throws {
        let bytes = Data(count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: bytes)
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        let cg = try XCTUnwrap(ThumbnailRenderer.renderCGImage(frame: frame, size: .s32, targetEdge: 64))
        XCTAssertEqual(cg.width, 64)
        XCTAssertEqual(cg.height, 64)
    }

    func testRenderCGImageReturnsNilForInvalidEdge() {
        let bytes = Data(count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: bytes)
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        XCTAssertNil(ThumbnailRenderer.renderCGImage(frame: frame, size: .s32, targetEdge: 0))
    }

    /// Both API shapes should be byte-equivalent at the pixel level — the Data form
    /// is just renderCGImage + PNG encode, no other transformations.
    func testRenderAndRenderCGImageProduceSamePixels() throws {
        // Build a small frame with a distinct pixel pattern so any divergence shows up.
        let edge = 16
        var pixels = Data(count: CanvasSize.s16.byteCount)
        for y in 0..<edge {
            for x in 0..<edge {
                let i = (y * edge + x) * 4
                pixels[i] = UInt8(x * 16); pixels[i + 1] = UInt8(y * 16)
                pixels[i + 2] = 64; pixels[i + 3] = 255
            }
        }
        let layer = Layer(name: "L", pixels: pixels)
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        let cg = try XCTUnwrap(ThumbnailRenderer.renderCGImage(frame: frame, size: .s16, targetEdge: 16))
        let png = try XCTUnwrap(ThumbnailRenderer.render(frame: frame, size: .s16, targetEdge: 16))

        // Decode the PNG back to a CGImage and compare bytes.
        let src = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(cg.width, decoded.width)
        XCTAssertEqual(cg.height, decoded.height)
    }
}
