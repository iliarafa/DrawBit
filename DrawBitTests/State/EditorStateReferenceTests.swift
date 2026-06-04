import XCTest
import CoreGraphics
import ImageIO
@testable import DrawBit

@MainActor
final class EditorStateReferenceTests: XCTestCase {
    private func makeState() -> EditorState {
        let layer = Layer(name: "Layer 1", pixels: Data(count: CanvasSize.s16.byteCount))
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        return EditorState(pieceID: UUID(), size: .s16,
                           frames: [frame], activeFrameIndex: 0, fps: 12)
    }

    func testDefaultsHaveNoReference() {
        let s = makeState()
        XCTAssertNil(s.referenceImage)
        XCTAssertNil(s.referenceImageData)
        XCTAssertTrue(s.isReferenceVisible)
        XCTAssertEqual(s.referenceOpacity, 0.35, accuracy: 0.0001)
    }

    func testSetReferenceWithValidDataDecodesImage() {
        let s = makeState()
        let png = Self.tinyPNG()
        s.setReference(imageData: png)
        XCTAssertEqual(s.referenceImageData, png)
        XCTAssertNotNil(s.referenceImage)
    }

    func testSetReferenceNilClears() {
        let s = makeState()
        s.setReference(imageData: Self.tinyPNG())
        s.setReference(imageData: nil)
        XCTAssertNil(s.referenceImageData)
        XCTAssertNil(s.referenceImage)
    }

    private static func tinyPNG() -> Data {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let img = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out as CFMutableData,
                                                    "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
}
