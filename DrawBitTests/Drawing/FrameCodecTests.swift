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

    func testDecodeRejectsMismatchedPixelCounts() throws {
        // Two layers with different pixel byte counts. Without the pre-validation guard,
        // this would trigger Frame.init's "equal pixel byte count" precondition trap.
        let l1 = Layer(name: "A", pixels: Data(count: CanvasSize.s32.byteCount))
        let l2 = Layer(name: "B", pixels: Data(count: CanvasSize.s32.byteCount))
        let frame = Frame(layers: [l1, l2], activeLayerID: l1.id)
        var encoded = FrameCodec.encode(frame)

        // Locate L2's 4-byte pixel-length field. Header layout:
        //   4 magic + 1 version + 2 count + 16 active = 23 bytes
        // Then L1: 16 uuid + 1 flags + 1 name-len + name + 4 pixel-len + N pixels.
        // L1's name "A" is 1 byte, so the per-layer prefix length before pixel-len is
        //   16 + 1 + 1 + 1 = 19, putting L1's pixel-len at offset 23 + 19 = 42.
        // L1's pixels span 42 + 4 = 46 .. 46 + s32.byteCount.
        // L2 starts at 46 + s32.byteCount and has the same 19-byte prefix shape.
        let s32 = CanvasSize.s32.byteCount
        let l2PixelLenOffset = 23 + 19 + 4 + s32 + 19
        // Overwrite L2's declared pixel-len with a smaller value (BE).
        let smaller = UInt32(s32 / 2)
        encoded[l2PixelLenOffset    ] = UInt8((smaller >> 24) & 0xFF)
        encoded[l2PixelLenOffset + 1] = UInt8((smaller >> 16) & 0xFF)
        encoded[l2PixelLenOffset + 2] = UInt8((smaller >>  8) & 0xFF)
        encoded[l2PixelLenOffset + 3] = UInt8( smaller        & 0xFF)
        // Truncate the trailing pixel bytes that are no longer needed by the new declared length,
        // so the stream stays internally consistent on byte counts.
        let truncated = encoded.prefix(l2PixelLenOffset + 4 + Int(smaller))

        XCTAssertThrowsError(try FrameCodec.decode(Data(truncated))) { error in
            guard case FrameCodec.DecodeError.malformed = error else {
                return XCTFail("expected DecodeError.malformed, got \(error)")
            }
        }
    }
}
