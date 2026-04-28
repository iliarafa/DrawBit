import Foundation

enum Eyedropper {
    /// Returns the color at `point`, or nil if the sample is fully transparent or out of bounds.
    /// Per spec: picking transparent is a no-op at the caller, not a new color selection.
    static func pick(from grid: PixelGrid, at point: (Int, Int)) -> RGBA? {
        guard grid.contains(x: point.0, y: point.1) else { return nil }
        let color = grid.pixel(x: point.0, y: point.1)
        return color.a == 0 ? nil : color
    }
}
