import Foundation

/// A named set of colors. Used both for the read-only built-ins (`BuiltInPalettes`) and for the
/// user's stored custom palettes (`AppSettings.customPalettes`).
///
/// `colors` are uppercase 6-digit hex strings WITHOUT a leading '#'. Pure Foundation value type —
/// no SwiftUI/SwiftData so it stays trivially testable and Codable for SwiftData storage.
struct ColorPalette: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var colors: [String]

    init(id: UUID = UUID(), name: String, colors: [String] = []) {
        self.id = id
        self.name = name
        self.colors = colors
    }
}

extension ColorPalette {
    /// Hex normalized for storage/compare: no leading '#', uppercase.
    static func normalizeHex(_ hex: String) -> String {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        return s.uppercased()
    }
}

/// Single source of truth for palette-list mutations, shared by `AppSettings` (persistence) and
/// `DrawBitColorPicker` (which mutates its `@Binding<[ColorPalette]>` live). Pure value logic.
extension Array where Element == ColorPalette {
    /// Appends a new empty palette. A blank name auto-numbers as `PALETTE N` (N = count + 1).
    @discardableResult
    mutating func addPalette(name: String = "") -> ColorPalette {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "PALETTE \(count + 1)" : trimmed
        let palette = ColorPalette(name: finalName)
        append(palette)
        return palette
    }

    mutating func deletePalette(id: UUID) {
        removeAll { $0.id == id }
    }

    mutating func renamePalette(id: UUID, to name: String) {
        guard let i = firstIndex(where: { $0.id == id }) else { return }
        self[i].name = name
    }

    mutating func addColor(_ hex: String, toPaletteID id: UUID) {
        guard let i = firstIndex(where: { $0.id == id }) else { return }
        let norm = ColorPalette.normalizeHex(hex)
        guard !self[i].colors.contains(where: { $0.caseInsensitiveCompare(norm) == .orderedSame }) else { return }
        self[i].colors.append(norm)
    }

    mutating func removeColor(_ hex: String, fromPaletteID id: UUID) {
        guard let i = firstIndex(where: { $0.id == id }) else { return }
        let norm = ColorPalette.normalizeHex(hex)
        self[i].colors.removeAll { $0.caseInsensitiveCompare(norm) == .orderedSame }
    }
}
