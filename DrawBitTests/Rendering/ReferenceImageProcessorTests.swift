import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import DrawBit

final class ReferenceImageProcessorTests: XCTestCase {

    func testLargeImageDownscaledToMaxEdgePreservingAspect() throws {
        let input = Self.makePNG(width: 4000, height: 2000)
        let out = try XCTUnwrap(ReferenceImageProcessor.process(input))
        let dims = try XCTUnwrap(Self.pixelSize(of: out))
        XCTAssertEqual(dims.width, 1024)   // 4000x2000 -> 1024x512
        XCTAssertEqual(dims.height, 512)
    }

    func testSmallImageNotUpscaled() throws {
        let input = Self.makePNG(width: 300, height: 200)
        let out = try XCTUnwrap(ReferenceImageProcessor.process(input))
        let dims = try XCTUnwrap(Self.pixelSize(of: out))
        XCTAssertEqual(dims.width, 300)
        XCTAssertEqual(dims.height, 200)
    }

    func testInvalidDataReturnsNil() {
        XCTAssertNil(ReferenceImageProcessor.process(Data([0, 1, 2, 3])))
    }

    // MARK: - Helpers

    private static func makePNG(width: Int, height: Int) -> Data {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.2, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let img = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out as CFMutableData,
                                                    UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    private static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return (img.width, img.height)
    }
}
