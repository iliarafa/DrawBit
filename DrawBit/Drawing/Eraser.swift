import Foundation

enum Eraser {
    static func erase(on grid: inout PixelGrid, at point: (Int, Int)) {
        grid.setPixel(x: point.0, y: point.1, color: .transparent)
    }

    static func eraseLine(on grid: inout PixelGrid, from: (Int, Int), to: (Int, Int)) {
        for p in bresenhamLine(from: from, to: to) {
            grid.setPixel(x: p.0, y: p.1, color: .transparent)
        }
    }
}
