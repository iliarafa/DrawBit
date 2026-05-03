import XCTest
@testable import DrawBit

final class LayerThumbnailRendererTests: XCTestCase {
    func testRendersSingleLayerToTargetEdge() {
        let bytes = Data(count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: bytes)
        let png = LayerThumbnailRenderer.render(layer: layer, size: .s32, targetEdge: 64)
        XCTAssertNotNil(png)
        XCTAssertGreaterThan(png?.count ?? 0, 0)
    }
}
