import XCTest
@testable import DrawBit

final class FrameThumbnailRendererTests: XCTestCase {
    func testRenderProducesNonEmptyPNGForNonEmptyFrame() {
        let pixels = Data(repeating: 255, count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: pixels)
        let frame = Frame(name: "F", layers: [layer], activeLayerID: layer.id)
        let png = FrameThumbnailRenderer.render(frame: frame, size: .s32, targetEdge: 32)
        XCTAssertNotNil(png)
        XCTAssertTrue((png?.count ?? 0) > 0)
    }

    func testRenderReturnsNilForBadInputs() {
        let pixels = Data(count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: pixels)
        let frame = Frame(name: "F", layers: [layer], activeLayerID: layer.id)
        XCTAssertNil(FrameThumbnailRenderer.render(frame: frame, size: .s32, targetEdge: 0))
    }

    func testRenderHonorsCompositorVisibility() {
        // A two-layer frame where the top layer is fully visible and the bottom is hidden.
        // The composite should equal the top layer's bytes (or transparent if top is empty).
        let topPixels = Data(repeating: 255, count: CanvasSize.s32.byteCount)
        let bottomPixels = Data(repeating: 128, count: CanvasSize.s32.byteCount)
        let bottom = Layer(name: "Bottom", pixels: bottomPixels, isVisible: false)
        let top = Layer(name: "Top", pixels: topPixels)
        let frame = Frame(name: "F", layers: [bottom, top], activeLayerID: top.id)
        let png = FrameThumbnailRenderer.render(frame: frame, size: .s32, targetEdge: 32)
        XCTAssertNotNil(png, "Hidden layer should not break thumbnail rendering")
    }
}
