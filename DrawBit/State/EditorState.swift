import Foundation
import Observation
import UIKit

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

    /// True while `PlaybackController` is advancing frames. Display-only state used to
    /// gate input (canvas hit-testing, frame/layer ops) and surface the play/pause icon.
    /// Cleared on `PlaybackController.stop()`. Not persisted.
    var isPlaying: Bool = false

    /// User-toggled onion-skin overlay state. When true and `activeFrameIndex > 0`,
    /// the canvas renders the previous frame as a faint ghost behind the active frame.
    /// Display-only — never written to pixel storage. Hidden during playback.
    var isOnionSkinEnabled: Bool = false

    /// Mirror strokes across the vertical centerline as the user draws.
    /// Session-only — resets when the editor closes. Affects pencil / eraser /
    /// fill / colorSwap; eyedropper and marquee are unaffected.
    var isMirrorEnabled: Bool = false

    var translation: CGSize = .zero
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0

    /// True when the view transform is away from its default (zoom/pan/rotation). Drives the
    /// contextual "reset view" chip — small tolerances absorb floating-point drift after a pinch.
    var isViewTransformed: Bool {
        abs(scale - 1) > 0.001
            || abs(rotation) > 0.001
            || abs(translation.width) > 0.5 || abs(translation.height) > 0.5
    }

    /// Snap the canvas back to default zoom/pan/rotation. View-only — never touches pixels.
    func resetView() {
        translation = .zero
        scale = 1.0
        rotation = 0.0
    }

    // MARK: - Reference photo (display-only tracing backdrop)

    /// Decoded reference image for rendering. Kept in sync with `referenceImageData`
    /// by `setReference(imageData:)` so the JPEG is decoded once, not every body pass.
    var referenceImage: UIImage?

    /// Raw stored bytes (size-capped JPEG). Source of truth for persistence.
    var referenceImageData: Data?

    /// Fade for the backdrop, 0...1. Mirrors `Piece.referenceOpacity`; edited live by the slider.
    var referenceOpacity: Double = 0.35

    /// Session-only show/hide of the backdrop. Not persisted (defaults visible when a reference exists).
    var isReferenceVisible: Bool = true

    var selection: MarqueeSelection?
    var pendingMarqueeRect: PixelRect?

    private var selectionAnchor: (Int, Int)?
    private var dragAnchor: (Int, Int)?

    enum UndoEntry {
        case layerPixels(frameID: UUID, layerID: UUID, before: Data)
        case frameStructure(before: Frame)            // legacy from layers v2 — used for in-frame structural changes; will be retired in a future stage if obsolete.
        /// Full-sequence snapshot. Memory cost at the cap is real:
        /// 60 frames × 16 layers × 256×256 RGBA = 240 MB per snapshot, × 50 = 12 GB undo stack.
        /// Stage 2 ships this whole-snapshot form because there is no UI yet to actually
        /// create a many-frame piece. Profiling is deferred to Stage 3 — once the timeline
        /// strip can produce a worst-case sequence, we revisit and migrate to a
        /// delta-encoded enum (`.frameInserted(at:)`, `.layerInsertedAcross(at:layerID:)`,
        /// etc.) if memory pressure is observed. See spec § "Undo storage".
        case sequenceStructure(beforeFrames: [Frame], beforeActive: Int)
    }

    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    private var preStrokeSnapshot: Data?
    private var preStrokeLayerID: UUID?
    /// The frame the stroke is being drawn on. Captured at snapshot time because
    /// layer UUIDs are shared across all frames (the cascade), so a layer id alone
    /// can't identify which frame the undo belongs to.
    private var preStrokeFrameID: UUID?
    private var preStructuralSnapshot: Frame?
    private var preSequenceSnapshot: (frames: [Frame], activeFrameIndex: Int)?

    private var pixelPerfectBuffer = PixelPerfectStroke()

    private let undoLimit = 50

    /// Tighter cap for `.sequenceStructure` entries specifically. Each one
    /// snapshots the full frame array — worst case (60 frames × 16 layers ×
    /// 128² × 4 bytes) is ~60 MiB per entry. At the generic `undoLimit=50`
    /// the stack could grow to 3 GiB worst-case and get the app killed on
    /// memory pressure. Capping sequence-structure entries at 10 keeps the
    /// worst-case footprint at ~600 MiB, well inside an iPad app's
    /// foreground budget. See `SequenceUndoMemoryTests`.
    ///
    /// Layer-pixel and frame-structure entries continue to use the generic
    /// `undoLimit` — they're small enough (<= ~1 MiB each) not to matter.
    ///
    /// If this constant is raised, also re-evaluate the worst-case math in
    /// `SequenceUndoMemoryTests.testWorstCaseSequenceUndoFitsBudget`.
    private let sequenceStructureUndoLimit = 10

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

    /// Transient: whether the hold-to-straighten line was at a "perfect" angle on the last re-aim.
    /// Lets `EditorView` fire a detent only on entry into a perfect angle. Reset per stroke.
    var lineWasPerfect = false

    /// Replaces the active layer with a straight line from `from` to `to`, recomputed off the
    /// pre-stroke snapshot. Calling it repeatedly as the finger re-aims keeps the freehand wobble
    /// erased and only the latest line shown; the existing begin/commitStroke flow makes the whole
    /// thing one undo entry. No-op until a stroke has begun (snapshot set) — see "hold to straighten".
    func applyStraightLine(from: (Int, Int), to: (Int, Int), mirror: Bool) {
        guard let base = preStrokeSnapshot else { return }
        setActiveLayerPixels(LineTool.apply(to: base, size: size, from: from, to: to,
                                            color: color, mirror: mirror))
    }

    /// Sets the reference photo from stored bytes, decoding for display. Pass nil to clear.
    func setReference(imageData: Data?) {
        referenceImageData = imageData
        referenceImage = imageData.flatMap { UIImage(data: $0) }
    }

    // MARK: - Drawing-stroke undo

    func beginStrokeSnapshot() {
        preStrokeSnapshot = frame.activeLayer.pixels
        preStrokeLayerID = frame.activeLayerID
        preStrokeFrameID = frame.id
        pixelPerfectBuffer.reset()
        lineWasPerfect = false
    }

    func commitStroke() {
        guard let snap = preStrokeSnapshot, let layerID = preStrokeLayerID,
              let frameID = preStrokeFrameID else { return }
        push(.layerPixels(frameID: frameID, layerID: layerID, before: snap))
        preStrokeSnapshot = nil
        preStrokeLayerID = nil
        preStrokeFrameID = nil
        pixelPerfectBuffer.reset()
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
        preStrokeFrameID = nil
        pixelPerfectBuffer.reset()
    }

    /// Pencil/eraser stroke filtering: append the new point and, if the trailing three points
    /// form an L-corner, mutate `grid` to restore the elbow pixel to its pre-stroke color.
    /// The new point at `p` should still be painted by the caller after this returns.
    func revertPixelPerfectElbow(grid: inout PixelGrid, beforeApplyingAt p: (Int, Int)) {
        guard let elbow = pixelPerfectBuffer.append(p),
              let snap = preStrokeSnapshot else { return }
        let snapGrid = PixelGrid(data: snap, size: size)
        grid.setPixel(x: elbow.0, y: elbow.1,
                      color: snapGrid.pixel(x: elbow.0, y: elbow.1))
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

    // MARK: - Sequence-structural-change undo

    func beginSequenceSnapshot() {
        preSequenceSnapshot = (frames, activeFrameIndex)
    }

    func commitSequenceChange() {
        guard let snap = preSequenceSnapshot else { return }
        push(.sequenceStructure(beforeFrames: snap.frames, beforeActive: snap.activeFrameIndex))
        preSequenceSnapshot = nil
    }

    func cancelSequenceChange() {
        if let snap = preSequenceSnapshot {
            frames = snap.frames
            activeFrameIndex = snap.activeFrameIndex
        }
        preSequenceSnapshot = nil
    }

    // MARK: - Active-frame switching

    func setActiveFrame(index: Int) {
        guard (0..<frames.count).contains(index) else { return }
        if index == activeFrameIndex { return }
        if selection != nil { commitMarquee() }
        if pendingMarqueeRect != nil { cancelMarquee() }
        if preStrokeSnapshot != nil { cancelStroke() }
        activeFrameIndex = index
    }

    private func push(_ entry: UndoEntry) {
        undoStack.append(entry)
        if undoStack.count > undoLimit {
            undoStack.removeFirst(undoStack.count - undoLimit)
        }
        // Sequence-structure entries are heavy (~60 MiB at worst-case sequence
        // size). Cap them separately so a flurry of frame-add operations doesn't
        // balloon the undo stack into memory-pressure territory. Drop oldest
        // .sequenceStructure entries until at or under sequenceStructureUndoLimit;
        // other entry types are untouched and follow the generic undoLimit.
        var sequenceCount = 0
        for e in undoStack { if case .sequenceStructure = e { sequenceCount += 1 } }
        while sequenceCount > sequenceStructureUndoLimit {
            if let idx = undoStack.firstIndex(where: { if case .sequenceStructure = $0 { return true } else { return false } }) {
                undoStack.remove(at: idx)
                sequenceCount -= 1
            } else {
                break
            }
        }
        redoStack.removeAll()
    }

    func undo() {
        if selection != nil { commitMarquee() }
        guard let entry = undoStack.popLast() else { return }
        switch entry {
        case .layerPixels(let frameID, let layerID, let before):
            // Resolve by frame id, not layer id: layer UUIDs are shared across every
            // frame (the cascade), so a layer-id search always lands on frame 0.
            guard let frameIdx = frames.firstIndex(where: { $0.id == frameID }),
                  let layerIdx = frames[frameIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
            let after = frames[frameIdx].layers[layerIdx].pixels
            redoStack.append(.layerPixels(frameID: frameID, layerID: layerID, before: after))
            var layers = frames[frameIdx].layers
            layers[layerIdx].pixels = before
            frames[frameIdx] = Frame(id: frames[frameIdx].id,
                                     name: frames[frameIdx].name,
                                     layers: layers,
                                     activeLayerID: frames[frameIdx].activeLayerID)
            activeFrameIndex = frameIdx   // show the frame that actually changed
        case .frameStructure(let before):
            redoStack.append(.frameStructure(before: frame))
            frame = before
        case .sequenceStructure(let beforeFrames, let beforeActive):
            redoStack.append(.sequenceStructure(beforeFrames: frames, beforeActive: activeFrameIndex))
            frames = beforeFrames
            activeFrameIndex = beforeActive
        }
    }

    func redo() {
        if selection != nil { commitMarquee() }
        guard let entry = redoStack.popLast() else { return }
        switch entry {
        case .layerPixels(let frameID, let layerID, let before):
            guard let frameIdx = frames.firstIndex(where: { $0.id == frameID }),
                  let layerIdx = frames[frameIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
            let after = frames[frameIdx].layers[layerIdx].pixels
            undoStack.append(.layerPixels(frameID: frameID, layerID: layerID, before: after))
            var layers = frames[frameIdx].layers
            layers[layerIdx].pixels = before
            frames[frameIdx] = Frame(id: frames[frameIdx].id,
                                     name: frames[frameIdx].name,
                                     layers: layers,
                                     activeLayerID: frames[frameIdx].activeLayerID)
            activeFrameIndex = frameIdx   // show the frame that actually changed
        case .frameStructure(let before):
            undoStack.append(.frameStructure(before: frame))
            frame = before
        case .sequenceStructure(let beforeFrames, let beforeActive):
            undoStack.append(.sequenceStructure(beforeFrames: frames, beforeActive: activeFrameIndex))
            frames = beforeFrames
            activeFrameIndex = beforeActive
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

    /// Commits the floating marquee selection back into the active layer's pixels
    /// at the current drag offset, then clears the selection.
    ///
    /// # Two known UX edges
    ///
    /// **1. Undo of a marquee commit doesn't restore the floating state.** The
    /// `.layerPixels` undo entry pushed here captures `preStrokeSnapshot` (the
    /// pre-extraction layer pixels), so undoing reverts all the way to before the
    /// lasso — the entire lasso+drag+commit collapses into one undo step. To
    /// support "undo just the commit, leaving the selection still floating", the
    /// undo entry would need a new case carrying the `MarqueeSelection` itself
    /// and the layer's post-extraction state; that's an architectural change to
    /// the undo stack rather than a one-line tweak. Accepted limitation — the
    /// single-step undo is intuitive enough that most users never notice.
    ///
    /// **2. This method doesn't check `isLocked` on the active layer.** The user
    /// can only reach `commitMarquee` via paths that either (a) the user
    /// explicitly triggered while the layer was unlocked, or (b) the layer-lock
    /// toggle auto-commits the marquee *before* setting the lock — so a locked
    /// layer with a floating marquee isn't reachable through any UI gesture
    /// today. If a future code path flips `Layer.isLocked` without going through
    /// the auto-commit shim, `commitMarquee` would silently write to a locked
    /// layer. The `onDisappear` save path in `EditorView` adds a defensive
    /// guard for that case (cancel instead of commit); add similar guards at any
    /// future direct callers.
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

    // MARK: - Selection transforms (operate on the floating selection)
    //
    // Flip/rotate mutate only the floating pixels — no layer write, no undo entry of their own;
    // the eventual `commitMarquee` captures the final result as one undo step (consistent with the
    // documented "lasso collapses to one undo"). Duplicate/delete DO write the layer, each as its
    // own undo step. Feedback (the detent click) fires from the view layer, not here.

    func flipSelectionHorizontal() {
        guard let sel = selection else { return }
        selection = MarqueeSelection(extracted: SelectionTransform.flipHorizontal(sel.extracted),
                                     dragOffset: sel.dragOffset)
    }

    func flipSelectionVertical() {
        guard let sel = selection else { return }
        selection = MarqueeSelection(extracted: SelectionTransform.flipVertical(sel.extracted),
                                     dragOffset: sel.dragOffset)
    }

    /// Rotate the floating selection 90° clockwise around where the user currently sees it.
    /// Returns `false` (and does nothing) when the rotated selection can't fit the canvas, so the
    /// caller can skip the success feedback. See `SelectionTransform.rotate90`'s fit-or-refuse rule.
    @discardableResult
    func rotateSelection() -> Bool {
        guard let sel = selection else { return false }
        let b = sel.displayBounds
        let center = (x: b.x + b.width / 2, y: b.y + b.height / 2)
        guard let rotated = SelectionTransform.rotate90(sel.extracted, around: center) else { return false }
        // Output bounds are absolute, so the drag offset folds away.
        selection = MarqueeSelection(extracted: rotated, dragOffset: (0, 0))
        return true
    }

    /// Stamp a copy of the floating selection into the active layer at its current position (one
    /// undo step), then keep the selection floating — nudged 1px down-right — so you immediately see
    /// two and can drag the copy away. Tap it again to scatter more. The stamped copy stays where
    /// you dropped it; you carry the duplicate.
    func duplicateSelection() {
        guard let sel = selection else { return }
        var grid = activeLayerPixelGrid
        Marquee.commit(into: &grid, selection: sel.extracted, offset: sel.dragOffset)
        setActiveLayerPixels(grid.data)
        commitStroke()          // bake the stamped copy as one undo step
        beginStrokeSnapshot()   // re-arm for the next stamp / the eventual commit
        // Keep floating, nudged off the stamp so the duplicate is visibly separate.
        selection = MarqueeSelection(extracted: sel.extracted,
                                     dragOffset: (dx: sel.dragOffset.dx + 1, dy: sel.dragOffset.dy + 1))
    }

    /// Discard the floating selection, leaving the hole it was cut from (one undo step restores it).
    /// Contrast `cancelMarquee`, which puts the pixels back.
    func deleteSelection() {
        guard selection != nil else { return }
        selection = nil
        dragAnchor = nil
        commitStroke()          // bake the already-cut hole
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
