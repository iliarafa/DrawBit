import Foundation

enum Tool: String, CaseIterable, Codable {
    case pencil
    case eraser
    case fill
    case eyedropper
    case marquee

    var sfSymbol: String {
        switch self {
        case .pencil: "pencil"
        case .eraser: "eraser"
        case .fill: "drop.fill"
        case .eyedropper: "eyedropper"
        case .marquee: "rectangle.dashed"
        }
    }

    var displayName: String {
        switch self {
        case .pencil: "Pencil"
        case .eraser: "Eraser"
        case .fill: "Fill"
        case .eyedropper: "Pick"
        case .marquee: "Laso"
        }
    }
}
