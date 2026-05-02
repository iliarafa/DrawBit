import Foundation

struct Layer: Equatable {
    let id: UUID
    var name: String
    var pixels: Data
    var isVisible: Bool
    var isLocked: Bool

    init(id: UUID = UUID(), name: String, pixels: Data, isVisible: Bool = true, isLocked: Bool = false) {
        self.id = id
        self.name = name
        self.pixels = pixels
        self.isVisible = isVisible
        self.isLocked = isLocked
    }
}
