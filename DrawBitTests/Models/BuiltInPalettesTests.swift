import XCTest
@testable import DrawBit

final class BuiltInPalettesTests: XCTestCase {

    /// The exact DB32 hex set the picker shipped before this feature (lowercase, no '#').
    /// The DB32 built-in must reproduce these colors, in order.
    private static let legacyDB32: [String] = [
        "000000", "222034", "45283c", "663931", "8f563b", "df7126", "d9a066", "eec39a",
        "fbf236", "99e550", "6abe30", "37946e", "4b692f", "524b24", "323c39", "3f3f74",
        "306082", "5b6ee1", "639bff", "5fcde4", "cbdbfc", "ffffff", "9badb7", "847e87",
        "696a6a", "595652", "76428a", "ac3232", "d95763", "d77bba", "8f974a", "8a6f30",
    ]

    func testFourBuiltInsPresentInOrder() {
        let names = BuiltInPalettes.all.map(\.name)
        XCTAssertEqual(names, ["DB32", "PICO-8", "SWEETIE 16", "GAME BOY"])
    }

    func testExpectedColorCounts() {
        func count(_ name: String) -> Int? {
            BuiltInPalettes.all.first { $0.name == name }?.colors.count
        }
        XCTAssertEqual(count("DB32"), 32)
        XCTAssertEqual(count("PICO-8"), 16)
        XCTAssertEqual(count("SWEETIE 16"), 16)
        XCTAssertEqual(count("GAME BOY"), 4)
    }

    func testEveryColorIsValidSixDigitHex() {
        for palette in BuiltInPalettes.all {
            for hex in palette.colors {
                XCTAssertFalse(hex.hasPrefix("#"), "\(palette.name): '\(hex)' must not include '#'")
                XCTAssertEqual(hex.count, 6, "\(palette.name): '\(hex)' must be 6 digits")
                XCTAssertNotNil(RGBA(hex: hex), "\(palette.name): '\(hex)' must parse")
            }
        }
    }

    func testColorsAreUppercase() {
        for palette in BuiltInPalettes.all {
            for hex in palette.colors {
                XCTAssertEqual(hex, hex.uppercased(), "\(palette.name): '\(hex)' must be uppercase")
            }
        }
    }

    func testDB32MatchesLegacyColors() {
        let db32 = BuiltInPalettes.all.first { $0.name == "DB32" }
        let actual = (db32?.colors ?? []).map { RGBA(hex: $0) }
        let expected = Self.legacyDB32.map { RGBA(hex: $0) }
        XCTAssertEqual(actual, expected, "DB32 built-in must reproduce the legacy hardcoded colors")
    }

    func testIDsAreStableAndUnique() {
        let first = BuiltInPalettes.all.map(\.id)
        let second = BuiltInPalettes.all.map(\.id)
        XCTAssertEqual(first, second, "built-in ids must be stable across reads")
        XCTAssertEqual(Set(first).count, first.count, "built-in ids must be unique")
    }
}
