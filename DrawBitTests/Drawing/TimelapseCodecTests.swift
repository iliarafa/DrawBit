import XCTest
@testable import DrawBit

final class TimelapseCodecTests: XCTestCase {
    func testRoundTrip() throws {
        let frames = [Data([1, 2, 3]), Data([]), Data([9, 9, 9, 9, 9])]
        let encoded = TimelapseCodec.encode(frames)
        let decoded = try XCTUnwrap(TimelapseCodec.decode(encoded))
        XCTAssertEqual(decoded, frames)
    }

    func testEmpty() throws {
        let decoded = try XCTUnwrap(TimelapseCodec.decode(TimelapseCodec.encode([])))
        XCTAssertEqual(decoded, [])
    }

    func testBadMagicReturnsNil() {
        XCTAssertNil(TimelapseCodec.decode(Data([0x00, 0x01, 0x02, 0x03, 0x04])))
    }

    func testTruncatedReturnsNil() {
        var d = TimelapseCodec.encode([Data([1, 2, 3, 4, 5])])
        d.removeLast(3)               // chop the payload
        XCTAssertNil(TimelapseCodec.decode(d))
    }
}
