import XCTest
@testable import DrawBit

final class ColorPaletteTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let palette = ColorPalette(name: "Skin Tones", colors: ["FFCCAA", "D9A066", "8F563B"])
        let data = try JSONEncoder().encode(palette)
        let decoded = try JSONDecoder().decode(ColorPalette.self, from: data)
        XCTAssertEqual(decoded, palette)
    }

    func testArrayCodableRoundTrip() throws {
        let palettes = [
            ColorPalette(name: "A", colors: ["000000"]),
            ColorPalette(name: "B", colors: []),
        ]
        let data = try JSONEncoder().encode(palettes)
        let decoded = try JSONDecoder().decode([ColorPalette].self, from: data)
        XCTAssertEqual(decoded, palettes)
    }
}
