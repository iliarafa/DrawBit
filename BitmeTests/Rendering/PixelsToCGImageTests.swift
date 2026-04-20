import XCTest
import CoreGraphics
@testable import Bitme

final class PixelsToCGImageTests: XCTestCase {
    func testImageDimensionsMatchCanvas() throws {
        var grid = PixelGrid(size: .s32)
        grid.setPixel(x: 0, y: 0, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        let image = try XCTUnwrap(pixelsToCGImage(grid))
        XCTAssertEqual(image.width, 32)
        XCTAssertEqual(image.height, 32)
    }

    func testImageIsSRGB() throws {
        let grid = PixelGrid(size: .s16)
        let image = try XCTUnwrap(pixelsToCGImage(grid))
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.sRGB)
    }

    func testRoundTripSinglePixel() throws {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 3, y: 4, color: RGBA(r: 200, g: 100, b: 50, a: 255))
        let image = try XCTUnwrap(pixelsToCGImage(grid))

        var out = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(
            data: &out, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        // sample pixel (3,4) from a 16x16 image: flip y to (16 - 1 - 4) = 11
        ctx.draw(image, in: CGRect(x: -3, y: -11, width: 16, height: 16))
        XCTAssertEqual(out[0], 200)
        XCTAssertEqual(out[1], 100)
        XCTAssertEqual(out[2], 50)
        XCTAssertEqual(out[3], 255)
    }
}
