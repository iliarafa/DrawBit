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

    func testSetReferenceComputesGrid() {
        let s = makeState()
        XCTAssertNil(s.referenceGrid)
        s.setReference(imageData: Self.tinyPNG())
        // The 4×4 red PNG fills the square canvas. Assert the grid is present, opaque, and reddish.
        // Exact sRGB color preservation is covered by ReferenceSamplerTests; this fixture's PNG isn't
        // sRGB-tagged, so its decoded red drifts a few points (a fixture quirk, not the sampler).
        let c = s.referenceGrid?.pixel(x: 8, y: 8)
        XCTAssertEqual(c?.a, 255)               // reference present + opaque
        XCTAssertGreaterThan(c?.r ?? 0, 200)    // sampled the red reference, not blank/blue
        XCTAssertLessThan(c?.b ?? 255, 80)
    }

    func testNilReferenceClearsGrid() {
        let s = makeState()
        s.setReference(imageData: Self.tinyPNG())
        XCTAssertNotNil(s.referenceGrid)
        s.setReference(imageData: nil)
        XCTAssertNil(s.referenceGrid)
    }

    // MARK: - pickColor (eyedropper reads the reference where layers are blank)

    func testPickColorFromReferenceWhenLayerBlank() {
        let s = makeState()
        s.setReference(imageData: Self.tinyPNG())     // red fills the canvas
        s.color = RGBA(r: 0, g: 0, b: 0, a: 255)      // start non-red
        s.pickColor(at: (8, 8))
        XCTAssertGreaterThan(s.color.r, 200)          // picked the reference red
        XCTAssertLessThan(s.color.b, 80)
    }

    func testPickColorLayerWinsOverReference() {
        let s = makeState()
        s.setReference(imageData: Self.tinyPNG())     // red reference
        let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
        var g = s.activeLayerPixelGrid
        g.setPixel(x: 8, y: 8, color: blue)
        s.setActiveLayerPixels(g.data)
        s.color = RGBA(r: 0, g: 0, b: 0, a: 255)
        s.pickColor(at: (8, 8))
        XCTAssertEqual(s.color, blue)                 // an actual layer pixel wins
    }

    func testPickColorReferenceHiddenIsNoOp() {
        let s = makeState()
        s.setReference(imageData: Self.tinyPNG())
        s.isReferenceVisible = false
        let before = RGBA(r: 9, g: 9, b: 9, a: 255)
        s.color = before
        s.pickColor(at: (8, 8))                        // blank layer + hidden reference
        XCTAssertEqual(s.color, before)               // unchanged
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
