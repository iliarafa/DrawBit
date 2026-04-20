import Foundation

enum Pencil {
    static func paint(on grid: inout PixelGrid, at point: (Int, Int), color: RGBA) {
        grid.setPixel(x: point.0, y: point.1, color: color)
    }

    static func paintLine(on grid: inout PixelGrid, from: (Int, Int), to: (Int, Int), color: RGBA) {
        for p in bresenhamLine(from: from, to: to) {
            grid.setPixel(x: p.0, y: p.1, color: color)
        }
    }
}
