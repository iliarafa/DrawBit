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

    func testSlicedPixelsDataIsNormalized() {
        let raw = Data(repeating: 0xFF, count: CanvasSize.s32.byteCount + 4)
        let sliced = raw[4...] // startIndex is 4, not 0
        let layer = Layer(name: "L", pixels: sliced)
        XCTAssertEqual(layer.pixels.startIndex, 0)
        XCTAssertEqual(layer.pixels.count, CanvasSize.s32.byteCount)
        XCTAssertEqual(layer.pixels.first, 0xFF)
    }
}
