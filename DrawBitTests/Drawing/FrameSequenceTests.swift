import XCTest
@testable import DrawBit

final class FrameSequenceTests: XCTestCase {

    /// Creates a frame sequence where all frames share the same layer UUID —
    /// the cascade invariant that any real sequence must satisfy.
    private func makeFrames(_ names: [String], byteCount: Int = CanvasSize.s32.byteCount) -> [Frame] {
        let sharedLayerID = UUID()
        return names.map { name in
            let layer = Layer(id: sharedLayerID, name: "Layer 1", pixels: Data(count: byteCount))
            return Frame(name: name, layers: [layer], activeLayerID: layer.id)
        }
    }

    func testAddFrameAfterDuplicatesContents() throws {
        var frames = makeFrames(["F1"])
        // Draw something into F1's layer:
        var layers = frames[0].layers
        layers[0].pixels[0] = 0xCC
        frames[0] = Frame(id: frames[0].id, name: frames[0].name,
                          layers: layers, activeLayerID: frames[0].activeLayerID)

        let newID = FrameSequence.addFrameAfter(frameID: frames[0].id, in: &frames)
        XCTAssertNotNil(newID)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[1].layers[0].pixels[0], 0xCC, "New frame should duplicate previous frame's pixels")
        XCTAssertNotEqual(frames[1].id, frames[0].id)
    }

    func testDuplicateFrame() {
        var frames = makeFrames(["F1", "F2"])
        let newID = FrameSequence.duplicateFrame(frames[0].id, in: &frames)
        XCTAssertNotNil(newID)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[1].id, newID)
        XCTAssertNotEqual(frames[1].id, frames[0].id)
    }

    func testAddBlankFrameAfterInsertsEmptyFrame() {
        var frames = makeFrames(["F1"])
        // Draw something into F1 so we can prove the new frame is NOT a copy.
        var layers = frames[0].layers
        layers[0].pixels[0] = 0xCC
        frames[0] = Frame(id: frames[0].id, name: frames[0].name,
                          layers: layers, activeLayerID: frames[0].activeLayerID)

        let newID = FrameSequence.addBlankFrameAfter(frameID: frames[0].id, in: &frames)
        XCTAssertNotNil(newID)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[1].id, newID)
        XCTAssertNotEqual(frames[1].id, frames[0].id)
        // New frame is blank in every layer:
        XCTAssertTrue(frames[1].layers.allSatisfy { $0.pixels.allSatisfy { $0 == 0 } },
                      "Blank-added frame must have all-zero pixels")
        // Source frame is untouched:
        XCTAssertEqual(frames[0].layers[0].pixels[0], 0xCC)
    }

    func testAddBlankFrameAfterPreservesLayerUUIDsAndOrder() {
        var frames = makeFrames(["F1"])
        _ = FrameSequence.addLayer(name: "Layer 2", in: &frames)
        let sourceLayerIDs = frames[0].layers.map(\.id)

        _ = FrameSequence.addBlankFrameAfter(frameID: frames[0].id, in: &frames)
        // The cascade invariant: the new frame has the SAME layer UUIDs in the same order.
        XCTAssertEqual(frames[1].layers.map(\.id), sourceLayerIDs)
    }

    func testAddBlankFrameAfterRespectsCap() {
        var frames = makeFrames((1...60).map { "F\($0)" })
        let newID = FrameSequence.addBlankFrameAfter(frameID: frames.last!.id, in: &frames)
        XCTAssertNil(newID, "Adding past the 60-frame cap must return nil")
        XCTAssertEqual(frames.count, 60)
    }

    func testRemoveFrame() {
        var frames = makeFrames(["F1", "F2", "F3"])
        FrameSequence.removeFrame(frames[1].id, in: &frames)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].name, "F1")
        XCTAssertEqual(frames[1].name, "F3")
    }

    func testRemoveFrameNoOpsAtSingleFrame() {
        var frames = makeFrames(["F1"])
        FrameSequence.removeFrame(frames[0].id, in: &frames)
        XCTAssertEqual(frames.count, 1)
    }

    func testMoveFrameForward() {
        var frames = makeFrames(["F1", "F2", "F3"])
        FrameSequence.move(frameID: frames[0].id, toIndex: 2, in: &frames)
        XCTAssertEqual(frames.map(\.name), ["F2", "F3", "F1"])
    }

    func testSetName() {
        var frames = makeFrames(["F1"])
        FrameSequence.setName(frameID: frames[0].id, to: "Idle", in: &frames)
        XCTAssertEqual(frames[0].name, "Idle")
    }

    func testCapEnforcedAtModelLevel() {
        var frames = makeFrames((1...60).map { "F\($0)" })
        let newID = FrameSequence.addFrameAfter(frameID: frames.last!.id, in: &frames)
        XCTAssertNil(newID, "Adding past the 60-frame cap must return nil")
        XCTAssertEqual(frames.count, 60)
    }

    // MARK: - Task 2.2: Layer cascade

    func testAddLayerCascadesAcrossAllFrames() {
        var frames = makeFrames(["F1", "F2", "F3"])
        let newLayerID = FrameSequence.addLayer(name: "Layer 2", in: &frames)
        XCTAssertNotNil(newLayerID)
        for f in frames {
            XCTAssertEqual(f.layers.count, 2)
            XCTAssertTrue(f.layers.contains(where: { $0.id == newLayerID }))
            // New layer is empty in every frame:
            XCTAssertTrue(f.layers.last!.pixels.allSatisfy { $0 == 0 })
        }
    }

    func testRemoveLayerCascadesAcrossAllFrames() {
        var frames = makeFrames(["F1", "F2"])
        _ = FrameSequence.addLayer(name: "Layer 2", in: &frames)
        let toRemove = frames[0].layers[1].id
        FrameSequence.removeLayer(toRemove, in: &frames)
        for f in frames {
            XCTAssertEqual(f.layers.count, 1)
            XCTAssertFalse(f.layers.contains(where: { $0.id == toRemove }))
        }
    }

    func testRemoveLayerNoOpsAtSingleLayer() {
        var frames = makeFrames(["F1"])
        let id = frames[0].layers[0].id
        FrameSequence.removeLayer(id, in: &frames)
        XCTAssertEqual(frames[0].layers.count, 1, "Cannot remove the last layer")
    }

    func testMoveLayerCascadesAcrossAllFrames() {
        var frames = makeFrames(["F1", "F2"])
        _ = FrameSequence.addLayer(name: "L2", in: &frames)
        _ = FrameSequence.addLayer(name: "L3", in: &frames)
        let l1 = frames[0].layers[0].id
        FrameSequence.moveLayer(l1, toIndex: 2, in: &frames)
        for f in frames {
            XCTAssertEqual(f.layers.last!.id, l1, "Layer 1 should now be on top in every frame")
        }
    }

    func testSetLayerNameCascadesAcrossAllFrames() {
        var frames = makeFrames(["F1", "F2"])
        let id = frames[0].layers[0].id
        FrameSequence.setLayerName(id, to: "Background", in: &frames)
        for f in frames {
            XCTAssertEqual(f.layers[0].name, "Background")
        }
    }

    func testSetLayerVisibleCascades() {
        var frames = makeFrames(["F1", "F2"])
        let id = frames[0].layers[0].id
        FrameSequence.setLayerVisible(id, false, in: &frames)
        for f in frames {
            XCTAssertFalse(f.layers[0].isVisible)
        }
    }

    func testSetLayerLockedCascades() {
        var frames = makeFrames(["F1", "F2"])
        let id = frames[0].layers[0].id
        FrameSequence.setLayerLocked(id, true, in: &frames)
        for f in frames {
            XCTAssertTrue(f.layers[0].isLocked)
        }
    }

    func testDuplicateLayerCascadesWithSameNewIDAcrossFrames() {
        var frames = makeFrames(["F1", "F2"])
        // Put different pixel data in F1 and F2 so we can verify per-frame copy semantics:
        var f1 = frames[0]
        var f2 = frames[1]
        var f1Layers = f1.layers
        var f2Layers = f2.layers
        f1Layers[0].pixels[0] = 0xAA
        f2Layers[0].pixels[0] = 0xBB
        frames[0] = Frame(id: f1.id, name: f1.name, layers: f1Layers, activeLayerID: f1.activeLayerID)
        frames[1] = Frame(id: f2.id, name: f2.name, layers: f2Layers, activeLayerID: f2.activeLayerID)

        let sourceID = frames[0].layers[0].id
        let newID = FrameSequence.duplicateLayer(sourceID, in: &frames)
        XCTAssertNotNil(newID)
        XCTAssertEqual(frames[0].layers.count, 2)
        XCTAssertEqual(frames[1].layers.count, 2)
        // Same UUID across frames:
        XCTAssertEqual(frames[0].layers[1].id, newID)
        XCTAssertEqual(frames[1].layers[1].id, newID)
        // Per-frame pixel copy:
        XCTAssertEqual(frames[0].layers[1].pixels[0], 0xAA)
        XCTAssertEqual(frames[1].layers[1].pixels[0], 0xBB)
    }
}
