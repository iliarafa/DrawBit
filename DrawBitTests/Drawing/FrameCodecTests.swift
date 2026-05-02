import XCTest
@testable import DrawBit

final class FrameCodecTests: XCTestCase {
    private func sampleFrame() -> Frame {
        let bytes = Data((0..<CanvasSize.s32.byteCount).map { UInt8($0 & 0xFF) })
        let l1 = Layer(name: "Background", pixels: bytes, isVisible: true,  isLocked: false)
        let l2 = Layer(name: "Sketch",     pixels: bytes, isVisible: false, isLocked: true)
        return Frame(layers: [l1, l2], activeLayerID: l2.id)
    }

    func testRoundTripPreservesAllFields() throws {
        let original = sampleFrame()
        let data = FrameCodec.encode(original)
        let decoded = try FrameCodec.decode(data)
        XCTAssertEqual(decoded, original)
    }

    func testEncodedDataStartsWithMagic() {
        let data = FrameCodec.encode(sampleFrame())
        let magic = Array(data.prefix(4))
        XCTAssertEqual(magic, Array("DBFR".utf8))
    }

    func testHasV1MagicPrefixReturnsFalseForRawV1Bytes() {
        let v1Raw = Data(count: CanvasSize.s32.byteCount)
        XCTAssertFalse(FrameCodec.hasV1MagicPrefix(v1Raw))
    }

    func testHasV1MagicPrefixReturnsTrueForEncodedFrame() {
        let encoded = FrameCodec.encode(sampleFrame())
        XCTAssertTrue(FrameCodec.hasV1MagicPrefix(encoded))
    }

    func testWrapV1DataProducesSingleLayerFrame() {
        let pixelCount = CanvasSize.s32.byteCount
        let v1Raw = Data((0..<pixelCount).map { UInt8($0 & 0xFF) })
        let frame = FrameCodec.wrapV1Data(v1Raw, defaultName: "Layer 1")
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.layers[0].name, "Layer 1")
        XCTAssertEqual(frame.layers[0].pixels, v1Raw)
        XCTAssertEqual(frame.activeLayerID, frame.layers[0].id)
    }

    func testDecodeRejectsBadMagic() {
        var bad = FrameCodec.encode(sampleFrame())
        bad[0] = 0x00
        XCTAssertThrowsError(try FrameCodec.decode(bad))
    }

    func testDecodeRejectsTruncatedData() {
        let encoded = FrameCodec.encode(sampleFrame())
        let truncated = encoded.prefix(encoded.count - 1)
        XCTAssertThrowsError(try FrameCodec.decode(Data(truncated)))
    }
}
