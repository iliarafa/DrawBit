import Foundation

struct Frame: Equatable {
    private(set) var layers: [Layer]
    private(set) var activeLayerID: UUID

    init(layers: [Layer], activeLayerID: UUID) {
        precondition(!layers.isEmpty, "Frame must have at least one layer")
        precondition(layers.contains(where: { $0.id == activeLayerID }),
                     "activeLayerID must reference one of the layers")
        precondition(layers.dropFirst().allSatisfy { $0.pixels.count == layers[0].pixels.count },
                     "All layers must have equal pixel byte count")
        self.layers = layers
        self.activeLayerID = activeLayerID
    }

    var activeIndex: Int {
        // Safe: invariant guarantees activeLayerID is in layers.
        layers.firstIndex(where: { $0.id == activeLayerID })!
    }

    var activeLayer: Layer {
        layers[activeIndex]
    }

    /// Adds a new empty layer above the active layer and makes it active. Returns the new layer.
    /// Caller is responsible for enforcing any cap; this method always inserts.
    @discardableResult
    mutating func addLayer(name: String) -> Layer {
        let pixelByteCount = layers[0].pixels.count
        let new = Layer(name: name, pixels: Data(count: pixelByteCount))
        let insertAt = activeIndex + 1
        layers.insert(new, at: insertAt)
        activeLayerID = new.id
        return new
    }

    /// Duplicates the active layer, places the duplicate above the original, and makes it active.
    @discardableResult
    mutating func duplicateActiveLayer(nameSuffix: String = " copy") -> Layer {
        let original = layers[activeIndex]
        let copy = Layer(
            name: original.name + nameSuffix,
            pixels: original.pixels,
            isVisible: original.isVisible,
            isLocked: original.isLocked
        )
        layers.insert(copy, at: activeIndex + 1)
        activeLayerID = copy.id
        return copy
    }

    /// Removes the layer with the given id. No-ops if removing the last layer.
    mutating func removeLayer(id: UUID) {
        guard layers.count > 1 else { return }
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = id == activeLayerID
        layers.remove(at: idx)
        if wasActive {
            // Prefer the layer below (idx - 1); otherwise the new layer at the same index.
            let newActiveIdx = max(0, idx - 1)
            activeLayerID = layers[newActiveIdx].id
        }
    }

    /// Moves the layer with the given id to `toIndex` (clamped to bounds). Active stays on the moved layer.
    mutating func move(id: UUID, toIndex: Int) {
        guard let from = layers.firstIndex(where: { $0.id == id }) else { return }
        let to = max(0, min(layers.count - 1, toIndex))
        if from == to { return }
        let layer = layers.remove(at: from)
        layers.insert(layer, at: to)
    }

    mutating func setActive(id: UUID) {
        guard layers.contains(where: { $0.id == id }) else { return }
        activeLayerID = id
    }

    mutating func setName(id: UUID, to name: String) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].name = name
    }

    mutating func setVisible(id: UUID, to visible: Bool) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].isVisible = visible
    }

    mutating func setLocked(id: UUID, to locked: Bool) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].isLocked = locked
    }

    /// Mutates the active layer's pixel data in place.
    mutating func withActiveLayerPixels(_ body: (inout Data) -> Void) {
        body(&layers[activeIndex].pixels)
    }
}
