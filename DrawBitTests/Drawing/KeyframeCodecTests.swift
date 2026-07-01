import XCTest
@testable import DrawBit

final class KeyframeCodecTests: XCTestCase {
    func testRoundTripIsLossless() throws {
        // A canvas-shaped buffer with runs (compresses well) plus some variation.
        var rgba = Data(count: 32 * 32 * 4)
        for i in stride(from: 0, to: rgba.count, by: 4) where (i / 4) % 7 == 0 {
            rgba[i] = 200; rgba[i + 1] = 40; rgba[i + 2] = 90; rgba[i + 3] = 255
        }
        let blob = try XCTUnwrap(KeyframeCodec.compress(rgba))
        XCTAssertLessThan(blob.count, rgba.count, "pixel-art buffer should shrink")
        let back = try XCTUnwrap(KeyframeCodec.decompress(blob))
        XCTAssertEqual(back, rgba, "decompress must reproduce bytes exactly")
    }

    func testDecompressGarbageReturnsNil() {
        XCTAssertNil(KeyframeCodec.decompress(Data([0x01, 0x02, 0x03, 0x04])))
    }
}
