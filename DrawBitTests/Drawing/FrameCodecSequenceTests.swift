import XCTest
@testable import DrawBit

final class FrameCodecSequenceTests: XCTestCase {

    private func makeFrame(name: String, byteCount: Int = CanvasSize.s32.byteCount) -> Frame {
        let layer = Layer(name: "Layer 1", pixels: Data(count: byteCount))
        return Frame(name: name, layers: [layer], activeLayerID: layer.id)
    }

    func testSequenceRoundTripSingleFrame() throws {
        let f = makeFrame(name: "Frame 1")
        let blob = FrameCodec.encodeSequence(frames: [f], activeFrameIndex: 0, fps: 12)
        let decoded = try FrameCodec.decodeSequence(blob)
        XCTAssertEqual(decoded.frames.count, 1)
        XCTAssertEqual(decoded.frames[0].id, f.id)
        XCTAssertEqual(decoded.frames[0].name, "Frame 1")
        XCTAssertEqual(decoded.frames[0].layers, f.layers)
        XCTAssertEqual(decoded.frames[0].activeLayerID, f.activeLayerID)
        XCTAssertEqual(decoded.activeFrameIndex, 0)
        XCTAssertEqual(decoded.fps, 12)
    }

    func testSequenceRoundTripMultiFrame() throws {
        let frames = (1...4).map { makeFrame(name: "Frame \($0)") }
        let blob = FrameCodec.encodeSequence(frames: frames, activeFrameIndex: 2, fps: 24)
        let decoded = try FrameCodec.decodeSequence(blob)
        XCTAssertEqual(decoded.frames.count, 4)
        XCTAssertEqual(decoded.activeFrameIndex, 2)
        XCTAssertEqual(decoded.fps, 24)
        for (a, b) in zip(frames, decoded.frames) {
            XCTAssertEqual(a.id, b.id)
            XCTAssertEqual(a.name, b.name)
            XCTAssertEqual(a.layers, b.layers)
        }
    }

    func testV1FallbackFromDBFRMagic() throws {
        let f = makeFrame(name: "ignored")
        let v1Blob = FrameCodec.encode(f)
        let decoded = try FrameCodec.decodeSequence(v1Blob)
        XCTAssertEqual(decoded.frames.count, 1)
        XCTAssertEqual(decoded.frames[0].name, "Frame 1") // default
        XCTAssertEqual(decoded.frames[0].layers, f.layers)
        XCTAssertEqual(decoded.activeFrameIndex, 0)
        XCTAssertEqual(decoded.fps, 12) // default
    }

    func testRawV1RGBABytesAreNotASequence() {
        let raw = Data(count: CanvasSize.s32.byteCount)
        XCTAssertThrowsError(try FrameCodec.decodeSequence(raw))
    }

    func testTruncatedSequenceThrows() {
        let f = makeFrame(name: "F")
        var blob = FrameCodec.encodeSequence(frames: [f], activeFrameIndex: 0, fps: 12)
        blob.removeLast(20)
        XCTAssertThrowsError(try FrameCodec.decodeSequence(blob))
    }

    func testHasV2SequenceMagicPrefixHelper() {
        let f = makeFrame(name: "F")
        let blob = FrameCodec.encodeSequence(frames: [f], activeFrameIndex: 0, fps: 12)
        XCTAssertTrue(FrameCodec.hasV2SequenceMagicPrefix(blob))
        XCTAssertFalse(FrameCodec.hasV2SequenceMagicPrefix(FrameCodec.encode(f)))
    }

    func testDecodeSequenceClampsOutOfRangeFPS() throws {
        // Construct a V2 blob with an absurd fps by encoding then patching the fps bytes.
        let pixels = Data(count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: pixels)
        let frame = Frame(name: "F", layers: [layer], activeLayerID: layer.id)
        var blob = FrameCodec.encodeSequence(frames: [frame], activeFrameIndex: 0, fps: 12)
        // FPS lives at offset 9: 4 magic + 1 version + 2 frame count + 2 active index = 9.
        let bigFPS: UInt16 = 30000
        blob[9] = UInt8(bigFPS >> 8)
        blob[10] = UInt8(bigFPS & 0xFF)
        let decoded = try FrameCodec.decodeSequence(blob)
        XCTAssertEqual(decoded.fps, 120, "Out-of-range fps must clamp to 120 on decode")
    }
}
