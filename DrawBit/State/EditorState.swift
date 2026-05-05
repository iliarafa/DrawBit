import Foundation
import Observation

@Observable
final class EditorState {
    let pieceID: UUID
    let size: CanvasSize

    // MARK: - Frame sequence

    var frames: [Frame]
    var activeFrameIndex: Int
    var fps: Int

    /// Read/write accessor for the active frame. Most legacy call sites compile unchanged via this.
    var frame: Frame {
        get { frames[activeFrameIndex] }
        set { frames[activeFrameIndex] = newValue }
    }

    var tool: Tool = .pencil
    var color: RGBA = RGBA(r: 255, g: 255, b: 255, a: 255)

    var translation: CGSize = .zero
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0

    var selection: MarqueeSelection?
    var pendingMarqueeRect: PixelRect?

    private var selectionAnchor: (Int, Int)?
    private var dragAnchor: (Int, Int)?

    enum UndoEntry {
        case layerPixels(layerID: UUID, before: Data)
        case frameStructure(before: Frame)
    }

    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    private var preStrokeSnapshot: Data?
    private var preStrokeLayerID: UUID?
    private var preStructuralSnapshot: Frame?

    private let undoLimit = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var isMarqueeDefining: Bool { selectionAnchor != nil }
    var isMarqueeDragging: Bool { dragAnchor != nil }

    /// PixelGrid view of the active layer's pixels. Read-only — to mutate, use `mutateActiveLayerPixels`.
    var activeLayerPixelGrid: PixelGrid {
        PixelGrid(data: frame.activeLayer.pixels, size: size)
    }

    var activeLayerIsLocked: Bool { frame.activeLayer.isLocked }

    /// When the user attempts to draw on a locked layer, the editor sets this to that layer's ID
    /// for a brief moment so the panel can flash a red border on the row. Set back to nil after
    /// the animation duration. UI-feedback only — never persisted.
    var lockPulseLayerID: UUID? = nil

    init(pieceID: UUID, size: CanvasSize,
         frames: [Frame], activeFrameIndex: Int, fps: Int) {
        precondition(!frames.isEmpty, "Editor must have at least one frame")
        precondition((0..<frames.count).contains(activeFrameIndex), "activeFrameIndex out of range")
        self.pieceID = pieceID
        self.size = size
        self.frames = frames
        self.activeFrameIndex = activeFrameIndex
        self.fps = fps
    }

    /// Convenience used by EditorView when it has a Piece + decoded sequence in hand.
    convenience init(piece: Piece, frames: [Frame], activeFrameIndex: Int, fps: Int) {
        self.init(pieceID: piece.id, size: piece.size,
                  frames: frames, activeFrameIndex: activeFrameIndex, fps: fps)
    }

    // MARK: - Active-layer pixel mutation

    func mutateActiveLayerPixels(_ body: (inout Data) -> Void) {
        frame.withActiveLayerPixels(body)
    }

    func setActiveLayerPixels(_ data: Data) {
        frame.withActiveLayerPixels { $0 = data }
    }

    // MARK: - Drawing-stroke undo

    func beginStrokeSnapshot() {
        preStrokeSnapshot = frame.activeLayer.pixels
        preStrokeLayerID = frame.activeLayerID
    }

    func commitStroke() {
        guard let snap = preStrokeSnapshot, let layerID = preStrokeLayerID else { return }
        push(.layerPixels(layerID: layerID, before: snap))
        preStrokeSnapshot = nil
        preStrokeLayerID = nil
    }

    func cancelStroke() {
        if let snap = preStrokeSnapshot, let layerID = preStrokeLayerID,
           let idx = frame.layers.firstIndex(where: { $0.id == layerID }) {
            // Restore by rebuilding the frame with the snapshot at idx, preserving id + name.
            var layers = frame.layers
            layers[idx].pixels = snap
            frame = Frame(id: frame.id,
                          name: frame.name,
                          layers: layers,
                          activeLayerID: frame.activeLayerID)
        }
        preStrokeSnapshot = nil
        preStrokeLayerID = nil
    }

    // MARK: - Structural-change undo

    func beginStructuralSnapshot() {
        preStructuralSnapshot = frame
    }

    func commitStructuralChange() {
        guard let snap = preStructuralSnapshot else { return }
        push(.frameStructure(before: snap))
        preStructuralSnapshot = nil
    }

    func cancelStructuralChange() {
        if let snap = preStructuralSnapshot {
            frame = snap
        }
        preStructuralSnapshot = nil
    }

    private func push(_ entry: UndoEntry) {
        undoStack.append(entry)
        if undoStack.count > undoLimit {
            undoStack.removeFirst(undoStack.count - undoLimit)
        }
        redoStack.removeAll()
    }

    func undo() {
        if selection != nil { commitMarquee() }
        guard let entry = undoStack.popLast() else { return }
        switch entry {
        case .layerPixels(let layerID, let before):
            guard let frameIdx = frames.firstIndex(where: { $0.layers.contains { $0.id == layerID } }),
                  let layerIdx = frames[frameIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
            let after = frames[frameIdx].layers[layerIdx].pixels
            redoStack.append(.layerPixels(layerID: layerID, before: after))
            var layers = frames[frameIdx].layers
            layers[layerIdx].pixels = before
            frames[frameIdx] = Frame(id: frames[frameIdx].id,
                                     name: frames[frameIdx].name,
                                     layers: layers,
                                     activeLayerID: frames[frameIdx].activeLayerID)
        case .frameStructure(let before):
            redoStack.append(.frameStructure(before: frame))
            frame = before
        }
    }

    func redo() {
        if selection != nil { commitMarquee() }
        guard let entry = redoStack.popLast() else { return }
        switch entry {
        case .layerPixels(let layerID, let before):
            guard let frameIdx = frames.firstIndex(where: { $0.layers.contains { $0.id == layerID } }),
                  let layerIdx = frames[frameIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
            let after = frames[frameIdx].layers[layerIdx].pixels
            undoStack.append(.layerPixels(layerID: layerID, before: after))
            var layers = frames[frameIdx].layers
            layers[layerIdx].pixels = before
            frames[frameIdx] = Frame(id: frames[frameIdx].id,
                                     name: frames[frameIdx].name,
                                     layers: layers,
                                     activeLayerID: frames[frameIdx].activeLayerID)
        case .frameStructure(let before):
            undoStack.append(.frameStructure(before: frame))
            frame = before
        }
    }

    // MARK: - Tool selection

    func setTool(_ next: Tool) {
        if selection != nil { commitMarquee() }
        if pendingMarqueeRect != nil { cancelMarquee() }
        tool = next
    }

    // MARK: - Marquee lifecycle (operates on active layer only)

    func beginMarqueeDefine(at point: (Int, Int)) {
        if selection != nil { commitMarquee() }
        beginStrokeSnapshot()
        selectionAnchor = point
        pendingMarqueeRect = PixelRect.from(point, point)
    }

    func updateMarqueeDefine(to point: (Int, Int)) {
        guard let anchor = selectionAnchor else { return }
        pendingMarqueeRect = PixelRect.from(anchor, point)
    }

    func endMarqueeDefine() {
        guard let rect = pendingMarqueeRect else { return }
        selectionAnchor = nil
        pendingMarqueeRect = nil
        var grid = activeLayerPixelGrid
        if let extracted = Marquee.extractAndCut(grid: &grid, rect: rect) {
            setActiveLayerPixels(grid.data)
            selection = MarqueeSelection(extracted: extracted, dragOffset: (0, 0))
        } else {
            cancelStroke()
        }
    }

    func beginMarqueeDrag(at point: (Int, Int)) {
        guard let sel = selection else { return }
        dragAnchor = (point.0 - sel.dragOffset.dx, point.1 - sel.dragOffset.dy)
    }

    func updateMarqueeDrag(to point: (Int, Int)) {
        guard var sel = selection, let anchor = dragAnchor else { return }
        sel.dragOffset = (dx: point.0 - anchor.0, dy: point.1 - anchor.1)
        selection = sel
    }

    func endMarqueeDrag() {
        dragAnchor = nil
    }

    func commitMarquee() {
        guard let sel = selection else { return }
        var grid = activeLayerPixelGrid
        Marquee.commit(into: &grid, selection: sel.extracted, offset: sel.dragOffset)
        setActiveLayerPixels(grid.data)
        selection = nil
        dragAnchor = nil
        commitStroke()
    }

    /// If a floating marquee selection exists, commit it back into the active
    /// layer's pixels. Safe to call when there is no selection (no-op).
    func commitFloatingSelectionIfAny() {
        guard selection != nil else { return }
        commitMarquee()
    }

    func cancelMarquee() {
        selection = nil
        pendingMarqueeRect = nil
        selectionAnchor = nil
        dragAnchor = nil
        cancelStroke()
    }
}

struct MarqueeSelection: Equatable {
    var extracted: ExtractedSelection
    var dragOffset: (dx: Int, dy: Int)

    var displayBounds: PixelRect {
        extracted.originalBounds.translated(dx: dragOffset.dx, dy: dragOffset.dy)
    }

    static func == (lhs: MarqueeSelection, rhs: MarqueeSelection) -> Bool {
        lhs.extracted == rhs.extracted
            && lhs.dragOffset.dx == rhs.dragOffset.dx
            && lhs.dragOffset.dy == rhs.dragOffset.dy
    }
}
