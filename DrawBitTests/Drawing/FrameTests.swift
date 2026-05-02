import XCTest
@testable import DrawBit

final class FrameTests: XCTestCase {
    private func emptyLayer(name: String = "Layer 1") -> Layer {
        Layer(name: name, pixels: Data(count: CanvasSize.s32.byteCount))
    }

    func testInitWithSingleLayerSetsActiveCorrectly() {
        let layer = emptyLayer()
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.activeLayerID, layer.id)
    }

    func testActiveIndexLocatesActiveLayer() {
        let bottom = emptyLayer(name: "Bottom")
        let top    = emptyLayer(name: "Top")
        let frame  = Frame(layers: [bottom, top], activeLayerID: top.id)
        XCTAssertEqual(frame.activeIndex, 1)
    }

    func testAddLayerAboveInsertsAndSetsActive() {
        let bottom = emptyLayer(name: "Bottom")
        var frame  = Frame(layers: [bottom], activeLayerID: bottom.id)
        let added  = frame.addLayer(name: "Layer 2")
        XCTAssertEqual(frame.layers.count, 2)
        XCTAssertEqual(frame.layers[1].id, added.id)
        XCTAssertEqual(frame.activeLayerID, added.id)
    }

    func testRemoveLayerSelectsLayerBelow() {
        let l1 = emptyLayer(name: "L1")
        let l2 = emptyLayer(name: "L2")
        var frame = Frame(layers: [l1, l2], activeLayerID: l2.id)
        frame.removeLayer(id: l2.id)
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.activeLayerID, l1.id)
    }

    func testRemoveBottomLayerSelectsLayerAbove() {
        let l1 = emptyLayer(name: "L1")
        let l2 = emptyLayer(name: "L2")
        var frame = Frame(layers: [l1, l2], activeLayerID: l1.id)
        frame.removeLayer(id: l1.id)
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.activeLayerID, l2.id)
    }

    func testRemoveLastLayerIsNoOp() {
        let l1 = emptyLayer()
        var frame = Frame(layers: [l1], activeLayerID: l1.id)
        frame.removeLayer(id: l1.id)
        XCTAssertEqual(frame.layers.count, 1, "minimum 1 layer must be preserved")
        XCTAssertEqual(frame.activeLayerID, l1.id)
    }

    func testMoveLayerReorders() {
        let l1 = emptyLayer(name: "L1")
        let l2 = emptyLayer(name: "L2")
        let l3 = emptyLayer(name: "L3")
        var frame = Frame(layers: [l1, l2, l3], activeLayerID: l1.id)
        frame.move(id: l1.id, toIndex: 2)
        XCTAssertEqual(frame.layers.map(\.name), ["L2", "L3", "L1"])
        XCTAssertEqual(frame.activeLayerID, l1.id, "active stays on the moved layer")
    }

    func testSetActiveValidatesMembership() {
        let l1 = emptyLayer()
        var frame = Frame(layers: [l1], activeLayerID: l1.id)
        frame.setActive(id: UUID()) // unknown id
        XCTAssertEqual(frame.activeLayerID, l1.id, "unknown ids are ignored, not stored")
    }

    func testWithActiveLayerPixelsMutatesOnlyActiveLayer() {
        let l1 = emptyLayer(name: "L1")
        let l2 = emptyLayer(name: "L2")
        var frame = Frame(layers: [l1, l2], activeLayerID: l2.id)

        frame.withActiveLayerPixels { pixels in
            pixels[0] = 0xFF
        }

        XCTAssertEqual(frame.layers[0].pixels[0], 0x00, "L1 untouched")
        XCTAssertEqual(frame.layers[1].pixels[0], 0xFF, "L2 mutated")
    }
}
