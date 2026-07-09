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

    /// Playback speeds the FPS control cycles through (tap the FPS icon to advance; wraps).
    static let fpsChoices = [4, 8, 12, 24, 30, 60]

    /// Read/write accessor for the active frame. Most legacy call sites compile unchanged via this.
    var frame: Frame {
        get { frames[activeFrameIndex] }
        set { frames[activeFrameIndex] = newValue }
    }

    var tool: Tool = .pencil
    var color: RGBA = RGBA(r: 255, g: 255, b: 255, a: 255)

    /// Square brush nib side for the pencil, within `brushSizeRange`. Session-only — resets to 1
    /// when the editor closes. Independent from `eraserSize` so a fat eraser and a fine pencil coexist.
    var pencilSize: Int = 1
    /// Square brush nib side for the eraser. Session-only. See `pencilSize`.
    var eraserSize: Int = 1
    /// Inclusive range the nib cycles through. Raise the upper bound here to offer larger brushes;
    /// `cycleBrushSize` and the toolbar glyph both read it.
    let brushSizeRange = 1...4

    /// True while `PlaybackController` is advancing frames. Display-only state used to
    /// gate input (canvas hit-testing, frame/layer ops) and surface the play/pause icon.
    /// Cleared on `PlaybackController.stop()`. Not persisted.
    var isPlaying: Bool = false

    /// True when the most recent persistence attempt threw. Drives a non-blocking "couldn't save"
    /// indicator so a failed autosave (e.g. disk full) isn't silently swallowed. Session-only,
    /// never persisted; cleared on the next successful save.
    var saveDidFail: Bool = false

    /// User-toggled onion-skin overlay state. When true and `activeFrameIndex > 0`,
    /// the canvas renders the previous frame as a faint ghost behind the active frame.
    /// Display-only — never written to pixel storage. Hidden during playback.
    var isOnionSkinEnabled: Bool = false

    /// Mirror strokes across the vertical centerline as the user draws.
    /// Session-only — resets when the editor closes. Affects pencil / eraser /
    /// fill / colorSwap; eyedropper and marquee are unaffected.
    var isMirrorEnabled: Bool = false

    /// Live grid-intensity the canvas renders (OFF/SOFT/STRONG). Seeded from the persisted
    /// `AppSettings.gridIntensity` when the editor opens and written back by `EditorView` when the
    /// top-bar GRID button cycles it. Defaults to the calmer `.soft` before seeding. Display-only —
    /// never touches pixel storage. See `GridIntensity` and `CanvasView.gridOverlay`.
    var gridIntensity: GridIntensity = .soft

    var translation: CGSize = .zero
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0

    /// The zoom the canvas opens at, and that RESET returns to. 1.0 for small canvases; larger for
    /// big ones so the pixel grid is visible on open (a fit-to-screen large canvas has sub-4pt cells,
    /// which the grid fades out). Set once by `CanvasView` from the live viewport; "home" not "1.0"
    /// is what `isViewTransformed` and `resetView()` compare against so the chrome stays consistent.
    var homeScale: CGFloat = 1.0

    /// True when the view transform is away from its home (zoom/pan/rotation). Drives the
    /// contextual "reset view" chip — small tolerances absorb floating-point drift after a pinch.
    var isViewTransformed: Bool {
        abs(scale - homeScale) > 0.001
            || abs(rotation) > 0.001
            || abs(translation.width) > 0.5 || abs(translation.height) > 0.5
    }

    /// Snap the canvas back to its home zoom/pan/rotation. View-only — never touches pixels.
    func resetView() {
        translation = .zero
        scale = homeScale
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

    /// The reference image rendered onto the canvas grid (aspect-fit, sRGB, alpha 0/255), recomputed
    /// in `setReference`. Lets the eyedropper sample the display-only reference where layers are
    /// blank. Transient — never a `Layer`, never composited into exports.
    private(set) var referenceGrid: PixelGrid?

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

    /// Session recorder for the time-lapse. Not observed — no view reads it in a
    /// body, so mutating it per stroke triggers no re-render. Persisted separately
    /// via `encodedTimelapse()` / restored via `loadTimelapse(_:)`.
    @ObservationIgnored private var timelapse = TimelapseRecording()

    /// Number of keyframes recorded so far (drives the FILM export tile's gating).
    var timelapseFrameCount: Int { timelapse.frames.count }

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

    // MARK: - Brush size

    /// The active nib side for `tool` (1 for any tool that doesn't take a size).
    func brushSize(for tool: Tool) -> Int {
        switch tool {
        case .pencil: pencilSize
        case .eraser: eraserSize
        default: 1
        }
    }

    /// Steps the tool's nib up one and wraps at `brushSizeRange.upperBound`. No-op for tools that
    /// don't take a size. Driven by tapping the already-selected pencil/eraser.
    func cycleBrushSize(for tool: Tool) {
        switch tool {
        case .pencil: pencilSize = nextBrushSize(pencilSize)
        case .eraser: eraserSize = nextBrushSize(eraserSize)
        default: break
        }
    }

    private func nextBrushSize(_ s: Int) -> Int {
        s >= brushSizeRange.upperBound ? brushSizeRange.lowerBound : s + 1
    }

    /// Steps the playback speed to the next `fpsChoices` value and wraps — driven by tapping the FPS
    /// icon, the same tap-to-cycle idiom as the brush nib. Snaps to the first choice if `fps` is
    /// somehow off-list.
    func cycleFPS() {
        let c = Self.fpsChoices
        fps = c[((c.firstIndex(of: fps) ?? -1) + 1) % c.count]
    }

    /// Steps the grid intensity `OFF → SOFT → STRONG` and wraps — the same tap-to-cycle idiom as the
    /// brush nib and FPS. Pure state mutation; the haptic and the persist-to-AppSettings both fire
    /// from `EditorView`'s button (the SwiftData seam lives in the view, as with `lastUsedTool`).
    func cycleGridIntensity() {
        gridIntensity = gridIntensity.next()
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
                                            color: color, mirror: mirror, brushSize: pencilSize))
    }

    /// Sets the reference photo from stored bytes, decoding for display. Pass nil to clear.
    func setReference(imageData: Data?) {
        referenceImageData = imageData
        referenceImage = imageData.flatMap { UIImage(data: $0) }
        referenceGrid = imageData
            .flatMap { ReferenceSampler.renderToCanvasGrid($0, size: size) }
            .map { PixelGrid(data: $0, size: size) }
    }

    /// Eyedropper: set `color` to the composited layer color at `point`; where the layers are blank
    /// and the reference is visible, fall back to the reference photo's true color there. No-op when
    /// both are empty. The reference grid is sampled, never composited into exports.
    func pickColor(at point: (Int, Int)) {
        let buffer = Compositor.composite(frame, size: size)
        let grid = PixelGrid(data: buffer.data, size: size)
        let fallback = isReferenceVisible ? referenceGrid : nil
        if let picked = Eyedropper.pick(from: grid, fallback: fallback, at: point) {
            color = picked
        }
    }

    // MARK: - Drawing-stroke undo

    func beginStrokeSnapshot() {
        preStrokeSnapshot = frame.activeLayer.pixels
        preStrokeLayerID = frame.activeLayerID
        preStrokeFrameID = frame.id
        pixelPerfectBuffer.reset()
        lineWasPerfect = false
    }

    /// Bake the in-progress stroke into a single undo step. Returns `true` if an entry was pushed,
    /// `false` when the stroke left the layer's pixels unchanged — the read-only eyedropper, a
    /// same-color tap, an empty fill. A no-op must not push a phantom undo entry (or record a
    /// keyframe), or Undo gains an invisible step that looks broken; callers that persist should
    /// skip the save when this returns `false`.
    @discardableResult
    func commitStroke() -> Bool {
        guard let snap = preStrokeSnapshot, let layerID = preStrokeLayerID,
              let frameID = preStrokeFrameID else { return false }
        defer {
            preStrokeSnapshot = nil
            preStrokeLayerID = nil
            preStrokeFrameID = nil
            pixelPerfectBuffer.reset()
        }
        // No-op guard: skip only when we can positively confirm the same frame+layer is still
        // active and its pixels equal the snapshot. Any real change — or an ambiguous edge where
        // the active frame/layer moved — commits normally.
        if frame.id == frameID, frame.activeLayerID == layerID, frame.activeLayer.pixels == snap {
            return false
        }
        push(.layerPixels(frameID: frameID, layerID: layerID, before: snap))
        recordKeyframe()
        return true
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

    // MARK: - Time-lapse recording

    /// Snapshot the composited canvas (layers only — never the reference photo) and
    /// append it to the recording. Deduped/thinned inside `TimelapseRecording`.
    /// Called at every commit point, and again on close/share to finalize (so the
    /// clip always ends on the real canvas even if the last action was an undo).
    func recordKeyframe() {
        let buffer = Compositor.composite(frame, size: size)
        if let blob = KeyframeCodec.compress(buffer.data) {
            timelapse.append(blob)
        }
    }

    /// Restore a persisted recording when a piece is reopened. nil / corrupt → empty.
    func loadTimelapse(_ blob: Data?) {
        let frames = blob.flatMap { TimelapseCodec.decode($0) } ?? []
        timelapse = TimelapseRecording(frames: frames)
    }

    /// Encoded recording for persistence, or nil when nothing has been recorded.
    func encodedTimelapse() -> Data? {
        timelapse.frames.isEmpty ? nil : TimelapseCodec.encode(timelapse.frames)
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

    /// Stamps the tool's square nib into the active layer at `point`, mirroring each painted cell
    /// across the vertical centerline when mirror is on. Pencil writes `color`; eraser writes
    /// transparent. The pixel-perfect elbow cleaner runs only at size 1 (a 1-px concept). All writes
    /// happen in one `mutateActiveLayerPixels` closure, so the whole stroke is one undo step.
    func stampBrush(_ tool: Tool, at point: (Int, Int)) {
        let n = brushSize(for: tool)
        let cells = Brush.squareCells(centeredAt: point, size: n)
        let w = size.width - 1
        let paintColor = color
        mutateActiveLayerPixels { data in
            var grid = PixelGrid(data: data, size: size)
            if n == 1 {
                revertPixelPerfectElbow(grid: &grid, beforeApplyingAt: point)
            }
            func write(_ x: Int, _ y: Int) {
                switch tool {
                case .pencil: Pencil.paint(on: &grid, at: (x, y), color: paintColor)
                case .eraser: Eraser.erase(on: &grid, at: (x, y))
                default: break
                }
            }
            for (cx, cy) in cells {
                write(cx, cy)
                if isMirrorEnabled {
                    let mx = w - cx
                    if mx != cx { write(mx, cy) }
                }
            }
            data = grid.data
        }
    }

    // MARK: - Structural-change undo

    func beginStructuralSnapshot() {
        preStructuralSnapshot = frame
    }

    func commitStructuralChange() {
        guard let snap = preStructuralSnapshot else { return }
        push(.frameStructure(before: snap))
        preStructuralSnapshot = nil
        recordKeyframe()
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
        recordKeyframe()
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
