import XCTest
import ImageIO
@testable import Bitme

final class PNGExporterTests: XCTestCase {
    func testExportAt1x() throws {
        let grid = PixelGrid(size: .s16)
        let data = try XCTUnwrap(PNGExporter.export(grid: grid, scale: 1))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(image.height, 16)
    }

    func testExportAt16xProducesIntegerScaledOutput() throws {
        let grid = PixelGrid(size: .s16)
        let data = try XCTUnwrap(PNGExporter.export(grid: grid, scale: 16))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(image.width, 256)
        XCTAssertEqual(image.height, 256)
    }

    func testExportRejectsZeroOrNegativeScale() {
        let grid = PixelGrid(size: .s16)
        XCTAssertNil(PNGExporter.export(grid: grid, scale: 0))
        XCTAssertNil(PNGExporter.export(grid: grid, scale: -1))
    }

    func testExportPreservesExactPixelsAtIntegerScale() throws {
        var grid = PixelGrid(size: .s16)
        let red = RGBA(r: 200, g: 50, b: 10, a: 255)
        grid.setPixel(x: 0, y: 0, color: red)
        let data = try XCTUnwrap(PNGExporter.export(grid: grid, scale: 4))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 64)
        var out = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(
            data: &out, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        // top-left 4x4 block. In CG coord (bottom-left origin), pixel (0,0) of source is at y in [60,64).
        // Sample at (x=2, y=62) in image space.
        ctx.draw(image, in: CGRect(x: -2, y: -62, width: 64, height: 64))
        XCTAssertEqual(out[0], 200)
        XCTAssertEqual(out[1], 50)
        XCTAssertEqual(out[2], 10)
        XCTAssertEqual(out[3], 255)
    }
}
