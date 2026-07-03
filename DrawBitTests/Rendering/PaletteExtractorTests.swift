import XCTest
@testable import DrawBit

final class PaletteExtractorTests: XCTestCase {

    private let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    private let green = RGBA(r: 0, g: 255, b: 0, a: 255)
    private let blue = RGBA(r: 0, g: 0, b: 255, a: 255)

    private func frame(size: CanvasSize, paint: (inout PixelGrid) -> Void) -> Frame {
        var grid = PixelGrid(size: size)
        paint(&grid)
        let layer = Layer(name: "Layer 1", pixels: grid.data)
        return Frame(layers: [layer], activeLayerID: layer.id)
    }

    func testEmptyFrameReturnsEmpty() {
        let f = frame(size: .s16) { _ in }
        XCTAssertEqual(PaletteExtractor.colors(in: f, size: .s16), [])
    }

    func testDistinctOpaqueColorsInFirstSeenOrder() {
        let f = frame(size: .s16) { g in
            g.setPixel(x: 0, y: 0, color: red)
            g.setPixel(x: 1, y: 0, color: green)
            g.setPixel(x: 2, y: 0, color: red)   // duplicate, ignored
            g.setPixel(x: 0, y: 1, color: blue)
        }
        XCTAssertEqual(PaletteExtractor.colors(in: f, size: .s16), ["FF0000", "00FF00", "0000FF"])
    }

    func testTransparentPixelsExcluded() {
        let f = frame(size: .s16) { g in
            g.setPixel(x: 5, y: 5, color: green)
            // everything else stays transparent (a == 0)
        }
        XCTAssertEqual(PaletteExtractor.colors(in: f, size: .s16), ["00FF00"])
    }

    func testPortraitCanvasScansBelowTheSquareRegion() {
        // 9:16 portrait (18×32): a color painted below y == width must still be found.
        let size = CanvasSize(ratio: .r9x16, longestEdge: 32)
        XCTAssertEqual(size.width, 18)
        XCTAssertEqual(size.height, 32)
        let f = frame(size: size) { g in
            g.setPixel(x: 0, y: 0, color: red)
            g.setPixel(x: 5, y: 28, color: blue)  // below the top width×width square
        }
        XCTAssertEqual(PaletteExtractor.colors(in: f, size: size), ["FF0000", "0000FF"])
    }

    func testLandscapeCanvasScansFullWidth() {
        // 16:9 landscape (32×18): the far-right column must be found.
        let size = CanvasSize(ratio: .r16x9, longestEdge: 32)
        XCTAssertEqual(size.width, 32)
        XCTAssertEqual(size.height, 18)
        let f = frame(size: size) { g in
            g.setPixel(x: 31, y: 17, color: green)
        }
        XCTAssertEqual(PaletteExtractor.colors(in: f, size: size), ["00FF00"])
    }

    func testLimitRespected() {
        let f = frame(size: .s16) { g in
            g.setPixel(x: 0, y: 0, color: red)
            g.setPixel(x: 1, y: 0, color: green)
            g.setPixel(x: 2, y: 0, color: blue)
        }
        XCTAssertEqual(PaletteExtractor.colors(in: f, size: .s16, limit: 2), ["FF0000", "00FF00"])
    }
}
