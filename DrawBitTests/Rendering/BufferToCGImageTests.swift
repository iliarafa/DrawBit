import XCTest
@testable import DrawBit

final class BufferToCGImageTests: XCTestCase {
    func testProducesCGImageWithCorrectDimensions() {
        let bytes = Data(count: CanvasSize.s32.byteCount)
        let buf = CompositedBuffer(data: bytes, size: .s32)
        let img = bufferToCGImage(buf)
        XCTAssertNotNil(img)
        XCTAssertEqual(img?.width, 32)
        XCTAssertEqual(img?.height, 32)
    }
}
