import Foundation
import Observation

@Observable
final class EditorState {
    let pieceID: UUID
    var grid: PixelGrid
    var tool: Tool = .pencil
    var color: RGBA = RGBA(r: 255, g: 255, b: 255, a: 255)

    // View transform (rotation in radians). Rotation is view-only, not persisted.
    var translation: CGSize = .zero
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0

    // Marquee selection state. All transient — never persisted.
    var selection: MarqueeSelection?
    var pendingMarqueeRect: PixelRect?

    private var selectionAnchor: (Int, Int)?
    private var dragAnchor: (Int, Int)?

    private var undoStack: [Data] = []
    private var redoStack: [Data] = []
    private var preStrokeSnapshot: Data?

    private let undoLimit = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var isMarqueeDefining: Bool { selectionAnchor != nil }
    var isMarqueeDragging: Bool { dragAnchor != nil }

    init(piece: Piece) {
        self.pieceID = piece.id
        self.grid = PixelGrid(data: piece.pixels, size: piece.size)
    }

    // MARK: - Stroke primitives

    func beginStrokeSnapshot() {
        preStrokeSnapshot = grid.data
    }

    func commitStroke() {
        guard let snap = preStrokeSnapshot else { return }
        undoStack.append(snap)
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
        redoStack.removeAll()
        preStrokeSnapshot = nil
    }

    func cancelStroke() {
        if let snap = preStrokeSnapshot {
            grid = PixelGrid(data: snap, size: grid.size)
        }
        preStrokeSnapshot = nil
    }

    func undo() {
        if selection != nil { commitMarquee() }
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(grid.data)
        grid = PixelGrid(data: previous, size: grid.size)
    }

    func redo() {
        if selection != nil { commitMarquee() }
        guard let next = redoStack.popLast() else { return }
        undoStack.append(grid.data)
        grid = PixelGrid(data: next, size: grid.size)
    }

    // MARK: - Tool selection

    /// Sets the active tool. If a marquee selection is floating, it is committed first
    /// so that switching tools never silently drops the floating pixels.
    func setTool(_ next: Tool) {
        if selection != nil { commitMarquee() }
        if pendingMarqueeRect != nil { cancelMarquee() }
        tool = next
    }

    // MARK: - Marquee lifecycle

    /// Start defining a new selection rectangle from the given anchor pixel. Snapshots the
    /// pre-selection grid so that the entire define→drag→commit operation is one undo step.
    func beginMarqueeDefine(at point: (Int, Int)) {
        if selection != nil { commitMarquee() }
        beginStrokeSnapshot()
        selectionAnchor = point
        pendingMarqueeRect = PixelRect.from(point, point)
    }

    /// Update the second corner of the in-progress selection rectangle.
    func updateMarqueeDefine(to point: (Int, Int)) {
        guard let anchor = selectionAnchor else { return }
        pendingMarqueeRect = PixelRect.from(anchor, point)
    }

    /// Finish defining the rect: extract opaque pixels into a floating selection. If the
    /// region had no opaque pixels, roll back the snapshot — there's nothing to drag.
    func endMarqueeDefine() {
        guard let rect = pendingMarqueeRect else { return }
        selectionAnchor = nil
        pendingMarqueeRect = nil
        if let extracted = Marquee.extractAndCut(grid: &grid, rect: rect) {
            selection = MarqueeSelection(extracted: extracted, dragOffset: (0, 0))
        } else {
            cancelStroke()
        }
    }

    /// Start dragging the floating selection. The anchor is stored relative to the current
    /// drag offset, so subsequent updates set `dragOffset = currentPixel - relativeAnchor`.
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

    /// Commit the floating selection at its current offset and push the operation onto the
    /// undo stack as a single step (the snapshot was taken at `beginMarqueeDefine`).
    func commitMarquee() {
        guard let sel = selection else { return }
        Marquee.commit(into: &grid, selection: sel.extracted, offset: sel.dragOffset)
        selection = nil
        dragAnchor = nil
        commitStroke()
    }

    /// Discard the floating selection and restore the pre-selection grid.
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
