import Foundation
import SwiftData

@Model
final class AppSettings {
    var recentColors: [String]
    var lastUsedToolRaw: String

    var lastUsedTool: Tool {
        get { Tool(rawValue: lastUsedToolRaw) ?? .pencil }
        set { lastUsedToolRaw = newValue.rawValue }
    }

    init() {
        self.recentColors = []
        self.lastUsedToolRaw = Tool.pencil.rawValue
    }

    func addRecentColor(_ hex: String, limit: Int = 16) {
        var next = recentColors.filter { $0.caseInsensitiveCompare(hex) != .orderedSame }
        next.insert(hex, at: 0)
        if next.count > limit { next.removeLast(next.count - limit) }
        recentColors = next
    }
}
