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
    //
    // Logic lives on the `[ColorPalette]` extension (ColorPalette.swift) so the picker, which
    // mutates a live `@Binding<[ColorPalette]>`, shares one implementation. These delegate.

    @discardableResult
    func addCustomPalette(name: String = "") -> ColorPalette {
        customPalettes.addPalette(name: name)
    }

    func deleteCustomPalette(id: UUID) {
        customPalettes.deletePalette(id: id)
    }

    func renameCustomPalette(id: UUID, to name: String) {
        customPalettes.renamePalette(id: id, to: name)
    }

    func addColor(_ hex: String, toPaletteID id: UUID) {
        customPalettes.addColor(hex, toPaletteID: id)
    }

    func removeColor(_ hex: String, fromPaletteID id: UUID) {
        customPalettes.removeColor(hex, fromPaletteID: id)
    }
}
