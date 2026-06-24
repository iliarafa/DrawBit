import Foundation

enum Fill {
    /// 4-connected flood fill. Uses exact RGBA equality as the "same color" test, so transparent
    /// and opaque regions are distinct.
    static func fill(on grid: inout PixelGrid, at start: (Int, Int), with replacement: RGBA) {
        guard grid.contains(x: start.0, y: start.1) else { return }
        let target = grid.pixel(x: start.0, y: start.1)
        if target == replacement { return }
        var stack: [(Int, Int)] = [start]
        while let (x, y) = stack.popLast() {
            guard grid.contains(x: x, y: y) else { continue }
            if grid.pixel(x: x, y: y) != target { continue }
            grid.setPixel(x: x, y: y, color: replacement)
            stack.append((x + 1, y))
            stack.append((x - 1, y))
            stack.append((x, y + 1))
            stack.append((x, y - 1))
        }
    }
}
