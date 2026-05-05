import XCTest
@testable import DrawBit

final class FrameSequenceTests: XCTestCase {

    private func makeFrames(_ names: [String], byteCount: Int = CanvasSize.s32.byteCount) -> [Frame] {
        return names.map { name in
            let layer = Layer(name: "Layer 1", pixels: Data(count: byteCount))
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

    func testReorderMath() {
        // Pre-removal newOffset semantics, mirrors Frame.modelTargetIndex but without the
        // display-array reversal (timeline strip is left-to-right == model order).
        XCTAssertEqual(FrameSequence.modelTargetIndex(displayedFrom: 0, newOffset: 2, count: 3), 1)
        XCTAssertEqual(FrameSequence.modelTargetIndex(displayedFrom: 2, newOffset: 0, count: 3), 0)
        XCTAssertNil(FrameSequence.modelTargetIndex(displayedFrom: 1, newOffset: 1, count: 3))
        XCTAssertNil(FrameSequence.modelTargetIndex(displayedFrom: 1, newOffset: 2, count: 3))
    }
}
