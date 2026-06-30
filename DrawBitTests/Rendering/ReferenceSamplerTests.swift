import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DrawBit

/// `ReferenceSampler` renders the tracing reference image down onto the canvas grid (aspect-fit,
/// centered, sRGB, alpha 0/255) so the eyedropper can sample it. Orientation must stay top-left to
/// match `PixelGrid` / the on-screen backdrop — these tests pin that and the letterbox math.
final class ReferenceSamplerTests: XCTestCase {
    private let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    private let blue = RGBA(r: 0, g: 0, b: 255, a: 255)

    /// Build a CGImage from top-left row-major RGBA (row 0 = top), mirroring `bufferToCGImage`.
    private func cgImage(_ w: Int, _ h: Int, _ fill: (Int, Int) -> RGBA) -> CGImage {
        var data = Data(count: w * h * 4)
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for y in 0..<h {
                for x in 0..<w {
                    let c = fill(x, y)
                    let i = (y * w + x) * 4
                    p[i] = c.r; p[i + 1] = c.g; p[i + 2] = c.b; p[i + 3] = c.a
                }
            }
        }
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func grid(_ data: Data, _ size: CanvasSize) -> PixelGrid { PixelGrid(data: data, size: size) }

    private func pngBytes(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    // MARK: - aspectFitRect

    func testAspectFitSquareFillsExactly() {
        XCTAssertEqual(ReferenceSampler.aspectFitRect(imageW: 10, imageH: 10, canvasW: 16, canvasH: 16),
                       CGRect(x: 0, y: 0, width: 16, height: 16))
    }

    func testAspectFitWideLetterboxesVertically() {
        // 20×10 into 16×16 → fits width 16, height 8, centered at y = 4.
        XCTAssertEqual(ReferenceSampler.aspectFitRect(imageW: 20, imageH: 10, canvasW: 16, canvasH: 16),
                       CGRect(x: 0, y: 4, width: 16, height: 8))
    }

    func testAspectFitTallPillarboxesHorizontally() {
        XCTAssertEqual(ReferenceSampler.aspectFitRect(imageW: 10, imageH: 20, canvasW: 16, canvasH: 16),
                       CGRect(x: 4, y: 0, width: 8, height: 16))
    }

    // MARK: - renderToCanvasGrid

    func testRenderOrientationTopStaysTop() {
        // Top half red, bottom half blue → grid top rows red, bottom rows blue (NOT vertically mirrored).
        let img = cgImage(16, 16) { _, y in y < 8 ? red : blue }
        let g = grid(ReferenceSampler.renderToCanvasGrid(img, size: .s16), .s16)
        XCTAssertEqual(g.pixel(x: 8, y: 2), red)
        XCTAssertEqual(g.pixel(x: 8, y: 13), blue)
    }

    func testRenderSolidFillsOpaque() {
        let img = cgImage(16, 16) { _, _ in red }
        let g = grid(ReferenceSampler.renderToCanvasGrid(img, size: .s16), .s16)
        for (x, y) in [(0, 0), (15, 15), (8, 8)] { XCTAssertEqual(g.pixel(x: x, y: y), red) }
    }

    func testRenderWideLetterboxIsTransparent() {
        // 32×8 into 16×16 → scale 0.5 → band height 4 centered (rows 6...9); rows 0 & 15 are bars.
        let img = cgImage(32, 8) { _, _ in red }
        let g = grid(ReferenceSampler.renderToCanvasGrid(img, size: .s16), .s16)
        XCTAssertEqual(g.pixel(x: 8, y: 0), .transparent)
        XCTAssertEqual(g.pixel(x: 8, y: 15), .transparent)
        XCTAssertEqual(g.pixel(x: 8, y: 7), red)
    }

    func testRenderNonSquareCanvas() {
        let size = CanvasSize(width: 16, height: 8)
        let img = cgImage(16, 8) { _, _ in blue }   // same aspect → fills
        let g = grid(ReferenceSampler.renderToCanvasGrid(img, size: size), size)
        XCTAssertEqual(g.pixel(x: 8, y: 4), blue)
    }

    func testRenderFromDataDecodes() throws {
        let img = cgImage(16, 16) { x, _ in x < 8 ? red : blue }
        let data = try XCTUnwrap(pngBytes(img))
        let g = grid(try XCTUnwrap(ReferenceSampler.renderToCanvasGrid(data, size: .s16)), .s16)
        XCTAssertEqual(g.pixel(x: 4, y: 8), red)    // left half
        XCTAssertEqual(g.pixel(x: 12, y: 8), blue)  // right half
    }
}
