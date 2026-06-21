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
