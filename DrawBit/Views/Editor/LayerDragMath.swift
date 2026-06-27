import CoreGraphics

/// Pure math for the custom layer drag-reorder gesture, in *display* coordinates (top-of-stack
/// first). The LayersPanel translates the resulting slot to a model index via the already-tested
/// `performMove` → `Frame.move` path. Kept here, free of SwiftUI, so it's trivially unit-testable.

/// The display slot a dragged row should land in, given its starting slot and the vertical drag
/// distance in points. Rounds to the nearest whole row and clamps to `0..<count`.
func draggedDisplayIndex(start: Int, translation: CGFloat, rowHeight: CGFloat, count: Int) -> Int {
    guard rowHeight > 0 else { return start }
    let delta = Int((translation / rowHeight).rounded())
    return max(0, min(count - 1, start + delta))
}

/// The vertical offset (points) a non-dragged row takes to open the gap as the dragged row passes
/// over it. The dragged row (`i == start`) gets 0 here — it follows the finger directly.
/// Moving down: rows between the vacated slot and the target slide up by one row; moving up: rows
/// between target and origin slide down by one row.
func rowGapShift(displayIndex i: Int, start: Int, target: Int, rowHeight: CGFloat) -> CGFloat {
    if i == start { return 0 }
    if start < target, (start + 1 ... target).contains(i) { return -rowHeight }
    if target < start, (target ..< start).contains(i) { return rowHeight }
    return 0
}
