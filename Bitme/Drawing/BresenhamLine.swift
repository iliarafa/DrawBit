import Foundation

/// Classic Bresenham's line algorithm. Returns every integer point from `from` to `to` inclusive.
func bresenhamLine(from: (Int, Int), to: (Int, Int)) -> [(Int, Int)] {
    var (x0, y0) = from
    let (x1, y1) = to
    let dx = abs(x1 - x0)
    let dy = -abs(y1 - y0)
    let sx = x0 < x1 ? 1 : -1
    let sy = y0 < y1 ? 1 : -1
    var err = dx + dy
    var points: [(Int, Int)] = []
    while true {
        points.append((x0, y0))
        if x0 == x1 && y0 == y1 { break }
        let e2 = 2 * err
        if e2 >= dy { err += dy; x0 += sx }
        if e2 <= dx { err += dx; y0 += sy }
    }
    return points
}
