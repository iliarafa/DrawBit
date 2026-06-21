import XCTest
@testable import DrawBit

final class AppSettingsPaletteTests: XCTestCase {

    func testAddCustomPaletteAutoNamesSequentially() {
        let s = AppSettings()
        let first = s.addCustomPalette()
        let second = s.addCustomPalette()
        XCTAssertEqual(first.name, "PALETTE 1")
        XCTAssertEqual(second.name, "PALETTE 2")
        XCTAssertEqual(s.customPalettes.map(\.name), ["PALETTE 1", "PALETTE 2"])
    }

    func testAddCustomPaletteUsesGivenName() {
        let s = AppSettings()
        let p = s.addCustomPalette(name: "Skin")
        XCTAssertEqual(p.name, "Skin")
        XCTAssertEqual(s.customPalettes.first?.name, "Skin")
        XCTAssertTrue(p.colors.isEmpty)
    }

    func testRenameCustomPalette() {
        let s = AppSettings()
        let p = s.addCustomPalette(name: "Old")
        s.renameCustomPalette(id: p.id, to: "New")
        XCTAssertEqual(s.customPalettes.first?.name, "New")
    }

    func testDeleteCustomPalette() {
        let s = AppSettings()
        let a = s.addCustomPalette(name: "A")
        let b = s.addCustomPalette(name: "B")
        s.deleteCustomPalette(id: a.id)
        XCTAssertEqual(s.customPalettes.map(\.id), [b.id])
    }

    func testAddColorNormalizesAndAppends() {
        let s = AppSettings()
        let p = s.addCustomPalette(name: "P")
        s.addColor("#ff0000", toPaletteID: p.id)
        XCTAssertEqual(s.customPalettes.first?.colors, ["FF0000"])
    }

    func testAddColorDedupesCaseInsensitively() {
        let s = AppSettings()
        let p = s.addCustomPalette(name: "P")
        s.addColor("ff0000", toPaletteID: p.id)
        s.addColor("#FF0000", toPaletteID: p.id)
        XCTAssertEqual(s.customPalettes.first?.colors, ["FF0000"])
    }

    func testRemoveColor() {
        let s = AppSettings()
        let p = s.addCustomPalette(name: "P")
        s.addColor("FF0000", toPaletteID: p.id)
        s.addColor("00FF00", toPaletteID: p.id)
        s.removeColor("#ff0000", fromPaletteID: p.id)
        XCTAssertEqual(s.customPalettes.first?.colors, ["00FF00"])
    }

    func testMutatorsIgnoreUnknownPaletteID() {
        let s = AppSettings()
        let p = s.addCustomPalette(name: "P")
        s.addColor("FF0000", toPaletteID: UUID())
        s.removeColor("FF0000", fromPaletteID: UUID())
        s.renameCustomPalette(id: UUID(), to: "X")
        XCTAssertEqual(s.customPalettes, [p])
    }
}
