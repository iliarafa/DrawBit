import XCTest
import ImageIO
@testable import DrawBit

final class SpriteSheetExporterTests: XCTestCase {
    private func makeFrame(byteCount: Int, fill: UInt8 = 255) -> Frame {
        let layer = Layer(name: "L", pixels: Data(repeating: fill, count: byteCount))
        return Frame(name: "F", layers: [layer], activeLayerID: layer.id)
    }

    private func decodedSize(_ data: Data) throws -> (w: Int, h: Int) {
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        return (img.width, img.height)
    }

    // MARK: - Layout

    func testSingleFrameProducesOneCellSheet() throws {
        let frames = [makeFrame(byteCount: CanvasSize.s32.byteCount)]
        let data = try XCTUnwrap(SpriteSheetExporter.export(frames: frames, size: .s32, scale: 1))
        let (w, h) = try decodedSize(data)
        XCTAssertEqual(w, 32)
        XCTAssertEqual(h, 32)
    }

    func testFourFramesProduceTwoByTwoGrid() throws {
        let frames = (1...4).map { _ in makeFrame(byteCount: CanvasSize.s32.byteCount) }
        let data = try XCTUnwrap(SpriteSheetExporter.export(frames: frames, size: .s32, scale: 1))
        let (w, h) = try decodedSize(data)
        XCTAssertEqual(w, 64)
        XCTAssertEqual(h, 64)
    }

    func testNineFramesProduceThreeByThreeGrid() throws {
        let frames = (1...9).map { _ in makeFrame(byteCount: CanvasSize.s32.byteCount) }
        let data = try XCTUnwrap(SpriteSheetExporter.export(frames: frames, size: .s32, scale: 1))
        let (w, h) = try decodedSize(data)
        XCTAssertEqual(w, 96)
        XCTAssertEqual(h, 96)
    }

    /// 10 frames: round(sqrt(10)) = 3 columns, ceil(10/3) = 4 rows. 3×4 grid (2 empty cells).
    func testTenFramesProduceThreeByFourGrid() throws {
        let frames = (1...10).map { _ in makeFrame(byteCount: CanvasSize.s32.byteCount) }
        let data = try XCTUnwrap(SpriteSheetExporter.export(frames: frames, size: .s32, scale: 1))
        let (w, h) = try decodedSize(data)
        XCTAssertEqual(w, 32 * 3)
        XCTAssertEqual(h, 32 * 4)
    }

    /// 60 frames: round(sqrt(60)) = 8 columns, ceil(60/8) = 8 rows. 8×8 grid (4 empty cells).
    func testSixtyFramesProduceEightByEightGrid() throws {
        let frames = (1...60).map { _ in makeFrame(byteCount: CanvasSize.s16.byteCount) }
        let data = try XCTUnwrap(SpriteSheetExporter.export(frames: frames, size: .s16, scale: 1))
        let (w, h) = try decodedSize(data)
        XCTAssertEqual(w, 16 * 8)
        XCTAssertEqual(h, 16 * 8)
    }

    // MARK: - Scaling

    func testScaleAppliesToEntireSheet() throws {
        let frames = (1...4).map { _ in makeFrame(byteCount: CanvasSize.s32.byteCount) }
        let data = try XCTUnwrap(SpriteSheetExporter.export(frames: frames, size: .s32, scale: 4))
        let (w, h) = try decodedSize(data)
        XCTAssertEqual(w, 32 * 4 * 2)  // 4× × 2 cols
        XCTAssertEqual(h, 32 * 4 * 2)
    }

    // MARK: - Pixel-level layout

    /// Place two distinguishable frames in a 1×2 sheet (round(sqrt(2)) = 1 column,
    /// ceil(2/1) = 2 rows). Decode and verify cell 0 has the red fill, cell 1 has the
    /// blue fill — proves the layout writes frames in the right order at the right offset.
    func testFramesAreLaidOutInOrder() throws {
        let bytes = CanvasSize.s16.byteCount
        var redPixels = Data(count: bytes)
        var bluePixels = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 4) {
            redPixels[i] = 255; redPixels[i+1] = 0; redPixels[i+2] = 0; redPixels[i+3] = 255
            bluePixels[i] = 0;   bluePixels[i+1] = 0; bluePixels[i+2] = 255; bluePixels[i+3] = 255
        }
        let redLayer = Layer(name: "L", pixels: redPixels)
        let blueLayer = Layer(name: "L", pixels: bluePixels)
        let f0 = Frame(name: "R", layers: [redLayer],  activeLayerID: redLayer.id)
        let f1 = Frame(name: "B", layers: [blueLayer], activeLayerID: blueLayer.id)
        let data = try XCTUnwrap(SpriteSheetExporter.export(frames: [f0, f1], size: .s16, scale: 1))

        // Decode and rasterize into a known buffer.
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 16)
        XCTAssertEqual(img.height, 32)  // 1 col × 2 rows

        let bytesPerRow = 16 * 4
        var out = [UInt8](repeating: 0, count: bytesPerRow * 32)
        out.withUnsafeMutableBytes { buf in
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctx = CGContext(
                data: buf.baseAddress, width: 16, height: 32,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: 16, height: 32))
        }

        // Top-left of cell (0,0) — first frame, red.
        XCTAssertEqual(out[0], 255, "cell 0,0: R")
        XCTAssertEqual(out[2], 0,   "cell 0,0: B")
        // Top-left of cell (0,1) — second frame, blue. Row 16 of the sheet.
        let row16Offset = 16 * bytesPerRow
        XCTAssertEqual(out[row16Offset + 0], 0,   "cell 0,1: R")
        XCTAssertEqual(out[row16Offset + 2], 255, "cell 0,1: B")
    }

    // MARK: - Alpha preservation

    func testAlphaIsPreservedInEmptyCells() throws {
        // 3 frames in a 2×2 grid → cell (1,1) is empty. Frames are opaque.
        let bytes = CanvasSize.s16.byteCount
        var opaque = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 4) {
            opaque[i] = 200; opaque[i+1] = 200; opaque[i+2] = 200; opaque[i+3] = 255
        }
        let frames = (1...3).map { _ -> Frame in
            let l = Layer(name: "L", pixels: opaque)
            return Frame(name: "F", layers: [l], activeLayerID: l.id)
        }
        let data = try XCTUnwrap(SpriteSheetExporter.export(frames: frames, size: .s16, scale: 1))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 32)
        XCTAssertEqual(img.height, 32)

        let bytesPerRow = 32 * 4
        var out = [UInt8](repeating: 0, count: bytesPerRow * 32)
        out.withUnsafeMutableBytes { buf in
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctx = CGContext(
                data: buf.baseAddress, width: 32, height: 32,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }

        // Cell (1,1) — the empty one — top-left pixel is at (16, 16).
        let emptyOffset = (16 * bytesPerRow) + (16 * 4)
        XCTAssertEqual(out[emptyOffset + 3], 0, "empty cell must be fully transparent")
        // Cell (0,0) — filled — top-left pixel is opaque grey.
        XCTAssertEqual(out[3], 255, "filled cell must be opaque")
    }

    // MARK: - Edge cases

    func testEmptyFramesReturnsNil() {
        XCTAssertNil(SpriteSheetExporter.export(frames: [], size: .s32, scale: 1))
    }

    func testInvalidScaleReturnsNil() {
        let frames = [makeFrame(byteCount: CanvasSize.s32.byteCount)]
        XCTAssertNil(SpriteSheetExporter.export(frames: frames, size: .s32, scale: 0))
    }
}
