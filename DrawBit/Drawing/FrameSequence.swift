import Foundation

enum FrameSequence {

    static let frameCap: Int = 60

    /// Inserts a new frame after the frame with the given id. The new frame's pixels are
    /// a duplicate of the source frame's pixels (every layer copied). The new frame's id
    /// is fresh; layer UUIDs are preserved across frames so the layer-cascade rule (Task 2.2)
    /// stays consistent. Returns the new frame id, or nil if at the cap.
    @discardableResult
    static func addFrameAfter(frameID: UUID, in frames: inout [Frame]) -> UUID? {
        guard frames.count < frameCap else { return nil }
        guard let idx = frames.firstIndex(where: { $0.id == frameID }) else { return nil }
        let source = frames[idx]
        let copy = Frame(name: nextFrameName(in: frames),
                         layers: source.layers,           // SAME UUIDs — cascade-aligned
                         activeLayerID: source.activeLayerID)
        frames.insert(copy, at: idx + 1)
        return copy.id
    }

    @discardableResult
    static func duplicateFrame(_ frameID: UUID, in frames: inout [Frame]) -> UUID? {
        return addFrameAfter(frameID: frameID, in: &frames)
    }

    static func removeFrame(_ frameID: UUID, in frames: inout [Frame]) {
        guard frames.count > 1 else { return }
        guard let idx = frames.firstIndex(where: { $0.id == frameID }) else { return }
        frames.remove(at: idx)
    }

    static func move(frameID: UUID, toIndex: Int, in frames: inout [Frame]) {
        guard let from = frames.firstIndex(where: { $0.id == frameID }) else { return }
        let to = max(0, min(frames.count - 1, toIndex))
        if from == to { return }
        let frame = frames.remove(at: from)
        frames.insert(frame, at: to)
    }

    static func setName(frameID: UUID, to name: String, in frames: inout [Frame]) {
        guard let idx = frames.firstIndex(where: { $0.id == frameID }) else { return }
        frames[idx].name = name
    }

    /// Reorder math, analog of `Frame.modelTargetIndex`. SwiftUI `.onMove`'s `newOffset` is
    /// a pre-removal insertion point; the timeline strip is displayed left→right matching
    /// the model order, so no reversal is needed here (unlike the layers panel which reverses).
    static func modelTargetIndex(displayedFrom: Int, newOffset: Int, count: Int) -> Int? {
        let displayedTo = newOffset > count ? count : newOffset
        let modelFrom = displayedFrom
        let correctedTo = max(0, min(count - 1, displayedTo - (displayedTo > displayedFrom ? 1 : 0)))
        return modelFrom == correctedTo ? nil : correctedTo
    }

    // MARK: - Naming

    /// Returns "Frame N" where N is the lowest unused integer. Existing frames named
    /// outside the "Frame N" pattern (e.g., "Pose A") don't count toward the integer set.
    private static func nextFrameName(in frames: [Frame]) -> String {
        let prefix = "Frame "
        let used = Set(frames.compactMap { frame -> Int? in
            guard frame.name.hasPrefix(prefix) else { return nil }
            return Int(frame.name.dropFirst(prefix.count))
        })
        var n = 1
        while used.contains(n) { n += 1 }
        return "Frame \(n)"
    }
}
