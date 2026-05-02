import XCTest
@testable import DrawBit

final class LayerTests: XCTestCase {
    func testLayerIsEquatableOnAllFields() {
        let id = UUID()
        let pixels = Data(repeating: 0, count: CanvasSize.s32.byteCount)
        let a = Layer(id: id, name: "Layer 1", pixels: pixels, isVisible: true, isLocked: false)
        let b = Layer(id: id, name: "Layer 1", pixels: pixels, isVisible: true, isLocked: false)
        XCTAssertEqual(a, b)
    }

    func testLayerNotEqualWhenAnyFieldDiffers() {
        let id = UUID()
        let pixels = Data(repeating: 0, count: CanvasSize.s32.byteCount)
        let a = Layer(id: id, name: "Layer 1", pixels: pixels, isVisible: true, isLocked: false)
        XCTAssertNotEqual(a, Layer(id: UUID(), name: "Layer 1", pixels: pixels, isVisible: true, isLocked: false))
        XCTAssertNotEqual(a, Layer(id: id, name: "Other",   pixels: pixels, isVisible: true, isLocked: false))
        XCTAssertNotEqual(a, Layer(id: id, name: "Layer 1", pixels: Data(repeating: 1, count: pixels.count), isVisible: true, isLocked: false))
        XCTAssertNotEqual(a, Layer(id: id, name: "Layer 1", pixels: pixels, isVisible: false, isLocked: false))
        XCTAssertNotEqual(a, Layer(id: id, name: "Layer 1", pixels: pixels, isVisible: true, isLocked: true))
    }
}
