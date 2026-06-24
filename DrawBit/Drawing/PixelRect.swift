import Foundation

struct PixelRect: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    static func from(_ a: (Int, Int), _ b: (Int, Int)) -> PixelRect {
        let x0 = Swift.min(a.0, b.0)
        let y0 = Swift.min(a.1, b.1)
        let x1 = Swift.max(a.0, b.0)
        let y1 = Swift.max(a.1, b.1)
        return PixelRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }

    func contains(x: Int, y: Int) -> Bool {
        x >= self.x && y >= self.y && x < self.x + width && y < self.y + height
    }

    /// Clip to a non-square canvas, each axis bounded independently.
    func clipped(toCanvasWidth canvasWidth: Int, height canvasHeight: Int) -> PixelRect? {
        let x0 = Swift.max(0, x)
        let y0 = Swift.max(0, y)
        let x1 = Swift.min(canvasWidth, x + width)
        let y1 = Swift.min(canvasHeight, y + height)
        let w = x1 - x0
        let h = y1 - y0
        guard w > 0, h > 0 else { return nil }
        return PixelRect(x: x0, y: y0, width: w, height: h)
    }

    /// Square-canvas convenience.
    func clipped(toCanvasDimension dim: Int) -> PixelRect? {
        clipped(toCanvasWidth: dim, height: dim)
    }

    func translated(dx: Int, dy: Int) -> PixelRect {
        PixelRect(x: x + dx, y: y + dy, width: width, height: height)
    }
}
