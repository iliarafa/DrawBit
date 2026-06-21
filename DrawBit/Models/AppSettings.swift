import Foundation
import SwiftData

@Model
final class AppSettings {
    var recentColors: [String]
    var lastUsedToolRaw: String
    /// User-curated global palettes. Additive defaulted field → inferred lightweight migration
    /// (no new VersionedSchema). Built-in palettes are NOT stored here; see `BuiltInPalettes`.
    var customPalettes: [ColorPalette] = []

    var lastUsedTool: Tool {
        get { Tool(rawValue: lastUsedToolRaw) ?? .pencil }
        set { lastUsedToolRaw = newValue.rawValue }
    }

    init() {
        self.recentColors = []
        self.lastUsedToolRaw = Tool.pencil.rawValue
        self.customPalettes = []
    }

    func addRecentColor(_ hex: String, limit: Int = 23) {
        var next = recentColors.filter { $0.caseInsensitiveCompare(hex) != .orderedSame }
        next.insert(hex, at: 0)
        if next.count > limit { next.removeLast(next.count - limit) }
        recentColors = next
    }

    // MARK: - Custom palette management

    /// Hex normalized for storage/compare: no leading '#', uppercase.
    private static func normalizeHex(_ hex: String) -> String {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        return s.uppercased()
    }

    /// Creates a new empty palette. A blank name auto-numbers as `PALETTE N` (N = count + 1).
    @discardableResult
    func addCustomPalette(name: String = "") -> ColorPalette {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "PALETTE \(customPalettes.count + 1)" : trimmed
        let palette = ColorPalette(name: finalName)
        customPalettes.append(palette)
        return palette
    }

    func deleteCustomPalette(id: UUID) {
        customPalettes.removeAll { $0.id == id }
    }

    func renameCustomPalette(id: UUID, to name: String) {
        guard let i = customPalettes.firstIndex(where: { $0.id == id }) else { return }
        customPalettes[i].name = name
    }

    func addColor(_ hex: String, toPaletteID id: UUID) {
        guard let i = customPalettes.firstIndex(where: { $0.id == id }) else { return }
        let norm = Self.normalizeHex(hex)
        guard !customPalettes[i].colors.contains(where: { $0.caseInsensitiveCompare(norm) == .orderedSame }) else { return }
        customPalettes[i].colors.append(norm)
    }

    func removeColor(_ hex: String, fromPaletteID id: UUID) {
        guard let i = customPalettes.firstIndex(where: { $0.id == id }) else { return }
        let norm = Self.normalizeHex(hex)
        customPalettes[i].colors.removeAll { $0.caseInsensitiveCompare(norm) == .orderedSame }
    }
}
