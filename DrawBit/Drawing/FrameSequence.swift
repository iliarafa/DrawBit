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

    /// Inserts a new EMPTY frame after the frame with the given id: same layer UUIDs,
    /// names, visibility and lock state (so the cascade invariant holds) but all-zero
    /// pixels. Contrast with `addFrameAfter`/`duplicateFrame`, which copy pixels.
    /// Returns the new frame id, or nil if at the cap.
    @discardableResult
    static func addBlankFrameAfter(frameID: UUID, in frames: inout [Frame]) -> UUID? {
        guard frames.count < frameCap else { return nil }
        guard let idx = frames.firstIndex(where: { $0.id == frameID }) else { return nil }
        let source = frames[idx]
        let blankLayers = source.layers.map { layer in
            Layer(id: layer.id,
                  name: layer.name,
                  pixels: Data(count: layer.pixels.count),
                  isVisible: layer.isVisible,
                  isLocked: layer.isLocked)
        }
        let copy = Frame(name: nextFrameName(in: frames),
                         layers: blankLayers,
                         activeLayerID: source.activeLayerID)
        frames.insert(copy, at: idx + 1)
        return copy.id
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

    // MARK: - Naming (frame)

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

// MARK: - Layer cascade (Task 2.2)

extension FrameSequence {

    /// Mirrors `Frame.maxLayers` — the per-frame cap is a single number, owned
    /// by the model. Re-declared as `layerCap` here only so existing call sites
    /// in this file stay readable.
    static let layerCap: Int = Frame.maxLayers

    /// Inserts a new empty layer above the currently-active layer in EVERY frame, with the
    /// SAME UUID across the sequence. Returns the new layer id, or nil if at the cap.
    /// Active layer is set to the new layer in every frame.
    @discardableResult
    static func addLayer(name: String, in frames: inout [Frame]) -> UUID? {
        guard frames[0].layers.count < layerCap else { return nil }
        let newID = UUID()
        let byteCount = frames[0].layers[0].pixels.count
        let activeIndex = frames[0].layers.firstIndex(where: { $0.id == frames[0].activeLayerID })!
        let insertAt = activeIndex + 1

        for i in frames.indices {
            var layers = frames[i].layers
            layers.insert(Layer(id: newID, name: name, pixels: Data(count: byteCount)),
                          at: insertAt)
            frames[i] = Frame(id: frames[i].id,
                              name: frames[i].name,
                              layers: layers,
                              activeLayerID: newID)
        }
        return newID
    }

    /// Duplicates the layer with `sourceID` in EVERY frame; per-frame pixel data is duplicated
    /// from THAT frame's source layer pixels (so frame 1's duplicate mirrors frame 1's source,
    /// frame 2's duplicate mirrors frame 2's source). The duplicate's UUID is the same across
    /// frames. Active layer is set to the duplicate in every frame.
    @discardableResult
    static func duplicateLayer(_ sourceID: UUID, in frames: inout [Frame]) -> UUID? {
        guard frames[0].layers.count < layerCap else { return nil }
        let newID = UUID()
        guard let sourceIdx = frames[0].layers.firstIndex(where: { $0.id == sourceID }) else { return nil }

        for i in frames.indices {
            var layers = frames[i].layers
            let source = layers[sourceIdx]
            let copy = Layer(id: newID,
                             name: source.name + " copy",
                             pixels: source.pixels,
                             isVisible: source.isVisible,
                             isLocked: source.isLocked)
            layers.insert(copy, at: sourceIdx + 1)
            frames[i] = Frame(id: frames[i].id,
                              name: frames[i].name,
                              layers: layers,
                              activeLayerID: newID)
        }
        return newID
    }

    /// Removes the layer with the given id from EVERY frame. No-ops if it would leave a frame
    /// with zero layers. If the removed layer was active, the layer below (or above if it was
    /// the bottom) becomes active in every frame, with the same new active layer ID across frames.
    static func removeLayer(_ layerID: UUID, in frames: inout [Frame]) {
        guard frames[0].layers.count > 1 else { return }
        guard let idx = frames[0].layers.firstIndex(where: { $0.id == layerID }) else { return }
        let wasActive = frames[0].activeLayerID == layerID

        for i in frames.indices {
            var layers = frames[i].layers
            layers.remove(at: idx)
            let nextActive: UUID
            if wasActive {
                let newActiveIdx = max(0, idx - 1)
                nextActive = layers[newActiveIdx].id
            } else {
                nextActive = frames[i].activeLayerID
            }
            frames[i] = Frame(id: frames[i].id,
                              name: frames[i].name,
                              layers: layers,
                              activeLayerID: nextActive)
        }
    }

    /// Moves the layer with `layerID` to `toIndex` in EVERY frame.
    static func moveLayer(_ layerID: UUID, toIndex: Int, in frames: inout [Frame]) {
        guard let from = frames[0].layers.firstIndex(where: { $0.id == layerID }) else { return }
        let to = max(0, min(frames[0].layers.count - 1, toIndex))
        if from == to { return }
        for i in frames.indices {
            var layers = frames[i].layers
            let layer = layers.remove(at: from)
            layers.insert(layer, at: to)
            frames[i] = Frame(id: frames[i].id,
                              name: frames[i].name,
                              layers: layers,
                              activeLayerID: frames[i].activeLayerID)
        }
    }

    static func setLayerName(_ layerID: UUID, to name: String, in frames: inout [Frame]) {
        for i in frames.indices {
            guard let idx = frames[i].layers.firstIndex(where: { $0.id == layerID }) else { continue }
            var layers = frames[i].layers
            layers[idx].name = name
            frames[i] = Frame(id: frames[i].id, name: frames[i].name,
                              layers: layers, activeLayerID: frames[i].activeLayerID)
        }
    }

    static func setLayerVisible(_ layerID: UUID, _ visible: Bool, in frames: inout [Frame]) {
        for i in frames.indices {
            guard let idx = frames[i].layers.firstIndex(where: { $0.id == layerID }) else { continue }
            var layers = frames[i].layers
            layers[idx].isVisible = visible
            frames[i] = Frame(id: frames[i].id, name: frames[i].name,
                              layers: layers, activeLayerID: frames[i].activeLayerID)
        }
    }

    static func setLayerLocked(_ layerID: UUID, _ locked: Bool, in frames: inout [Frame]) {
        for i in frames.indices {
            guard let idx = frames[i].layers.firstIndex(where: { $0.id == layerID }) else { continue }
            var layers = frames[i].layers
            layers[idx].isLocked = locked
            frames[i] = Frame(id: frames[i].id, name: frames[i].name,
                              layers: layers, activeLayerID: frames[i].activeLayerID)
        }
    }
}
