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
}
