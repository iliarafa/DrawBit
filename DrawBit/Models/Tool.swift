import Foundation

enum Tool: String, CaseIterable, Codable {
    case pencil
    case eraser
    case fill
    case colorSwap
    case eyedropper
    case marquee

    var sfSymbol: String {
        switch self {
        case .pencil: "pencil"
        case .eraser: "eraser"
        case .fill: "drop.fill"
        case .colorSwap: "arrow.left.arrow.right"
        case .eyedropper: "eyedropper"
        case .marquee: "rectangle.dashed"
        }
    }

    var displayName: String {
        switch self {
        case .pencil: "Pencil"
        case .eraser: "Eraser"
        case .fill: "Fill"
        case .colorSwap: "Swap"
        case .eyedropper: "Pick"
        case .marquee: "Select"
        }
    }
}
