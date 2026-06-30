import Foundation

/// Square brush-nib geometry. Pure: the canvas cells an `n × n` nib covers when its center is
/// dropped on `point`, row-major. Odd sizes center on the cursor; even sizes put the cursor at the
/// upper-left of the central 2×2 (the nib extends one extra pixel down and right). Cells may fall
/// off-canvas — callers paint through `PixelGrid.setPixel`, which silently drops out-of-bounds
/// writes, so there is no clamping here.
enum Brush {
    static func squareCells(centeredAt point: (Int, Int), size: Int) -> [(Int, Int)] {
        let n = max(1, size)
        let originX = point.0 - (n - 1) / 2
        let originY = point.1 - (n - 1) / 2
        var cells: [(Int, Int)] = []
        cells.reserveCapacity(n * n)
        for j in 0..<n {
            for i in 0..<n {
                cells.append((originX + i, originY + j))
            }
        }
        return cells
    }
}
