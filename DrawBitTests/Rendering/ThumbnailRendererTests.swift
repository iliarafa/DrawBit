import XCTest
import ImageIO
@testable import DrawBit

final class ThumbnailRendererTests: XCTestCase {
    func testThumbnailIsPNGAtTargetSize() throws {
        var grid = PixelGrid(size: .s32)
        grid.setPixel(x: 0, y: 0, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        let data = try XCTUnwrap(ThumbnailRenderer.render(grid: grid, targetEdge: 128))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let type = CGImageSourceGetType(src) as String?
        XCTAssertEqual(type, "public.png")

        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(image.width, 128)
        XCTAssertEqual(image.height, 128)
    }

    func testThumbnailNonIntegerScaleStillProducesOutput() throws {
        let grid = PixelGrid(size: .s128)
        let data = try XCTUnwrap(ThumbnailRenderer.render(grid: grid, targetEdge: 120))
        XCTAssertGreaterThan(data.count, 0)
    }
}
