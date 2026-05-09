import Foundation

/// Stream-style filter for "pixel-perfect" pencil strokes (after Piskel's SimplePen.js).
/// As points are appended, three consecutive points forming a perpendicular L-corner
/// (one-step axis change) cause the middle point to be reported as an elbow that
/// should be unpainted. The elbow is also removed from internal history so cascading
/// drops are evaluated against the surviving predecessor.
struct PixelPerfectStroke {
    private var points: [(Int, Int)] = []

    /// Append a new stroke point. If the trailing two points plus the new one form an
    /// L-corner, the middle of the three is returned as the "elbow" — the caller should
    /// restore that pixel to its pre-stroke color before painting the new point.
    mutating func append(_ p: (Int, Int)) -> (Int, Int)? {
        if points.count >= 2 {
            let a = points[points.count - 2]
            let b = points[points.count - 1]
            if Self.isLCorner(a, b, p) {
                points[points.count - 1] = p
                return b
            }
        }
        points.append(p)
        return nil
    }

    mutating func reset() {
        points.removeAll(keepingCapacity: true)
    }

    static func isLCorner(_ a: (Int, Int), _ b: (Int, Int), _ c: (Int, Int)) -> Bool {
        let dx1 = b.0 - a.0, dy1 = b.1 - a.1
        let dx2 = c.0 - b.0, dy2 = c.1 - b.1
        if abs(dx1) + abs(dy1) != 1 { return false }
        if abs(dx2) + abs(dy2) != 1 { return false }
        return (dx1 != 0) != (dx2 != 0)
    }
}
