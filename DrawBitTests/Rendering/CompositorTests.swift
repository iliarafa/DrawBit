import XCTest
@testable import DrawBit

final class CompositorTests: XCTestCase {
    private let size = CanvasSize.s32

    private func solidLayer(name: String, rgba: (UInt8, UInt8, UInt8, UInt8)) -> Layer {
        var data = Data(count: size.byteCount)
        for i in stride(from: 0, to: size.byteCount, by: 4) {
            data[i] = rgba.0; data[i+1] = rgba.1; data[i+2] = rgba.2; data[i+3] = rgba.3
        }
        return Layer(name: name, pixels: data)
    }

    func testSingleLayerCompositesToItsOwnBytes() {
        let l = solidLayer(name: "L", rgba: (255, 0, 0, 255))
        let frame = Frame(layers: [l], activeLayerID: l.id)
        let buf = Compositor.composite(frame, size: size)
        XCTAssertEqual(buf.data, l.pixels)
        XCTAssertEqual(buf.size, size)
    }

    func testTwoOpaqueLayersTopWins() {
        let bottom = solidLayer(name: "B", rgba: (255, 0, 0, 255))
        let top    = solidLayer(name: "T", rgba: (  0, 255, 0, 255))
        let frame = Frame(layers: [bottom, top], activeLayerID: bottom.id)
        let buf = Compositor.composite(frame, size: size)
        XCTAssertEqual(buf.data, top.pixels)
    }

    func testTopTransparentRevealsBottom() {
        let bottom = solidLayer(name: "B", rgba: (255, 0, 0, 255))
        let top    = solidLayer(name: "T", rgba: (  0,   0, 0,   0))
        let frame = Frame(layers: [bottom, top], activeLayerID: bottom.id)
        let buf = Compositor.composite(frame, size: size)
        XCTAssertEqual(buf.data, bottom.pixels)
    }

    func testHiddenLayerSkipped() {
        var bottom = solidLayer(name: "B", rgba: (255, 0, 0, 255))
        var top    = solidLayer(name: "T", rgba: (  0, 255, 0, 255))
        top.isVisible = false
        _ = bottom // appease compiler about var

        let frame = Frame(layers: [bottom, top], activeLayerID: bottom.id)
        let buf = Compositor.composite(frame, size: size)
        XCTAssertEqual(buf.data, bottom.pixels, "hidden top must not affect output")
    }

    func testAllHiddenProducesAllTransparent() {
        var l1 = solidLayer(name: "1", rgba: (255, 0, 0, 255)); l1.isVisible = false
        var l2 = solidLayer(name: "2", rgba: (  0, 255, 0, 255)); l2.isVisible = false
        let frame = Frame(layers: [l1, l2], activeLayerID: l1.id)
        let buf = Compositor.composite(frame, size: size)
        XCTAssertEqual(buf.data, Data(count: size.byteCount))
    }

    func testCompositedAlphaIsAlwaysZeroOr255() {
        // Per the rendering invariant, compositor output must never produce partial alpha.
        let bottom = solidLayer(name: "B", rgba: (255, 0, 0, 255))
        let top    = solidLayer(name: "T", rgba: (  0, 255, 0,   0))
        let frame = Frame(layers: [bottom, top], activeLayerID: bottom.id)
        let buf = Compositor.composite(frame, size: size)
        for i in stride(from: 3, to: buf.data.count, by: 4) {
            let a = buf.data[i]
            XCTAssertTrue(a == 0 || a == 255, "alpha must be 0 or 255, got \(a) at byte \(i)")
        }
    }
}
