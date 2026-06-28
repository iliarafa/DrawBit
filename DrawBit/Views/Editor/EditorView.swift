import SwiftUI
import SwiftData
import UIKit

struct EditorView: View {
    let piece: Piece
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var state: EditorState
    @State private var pencilAvailability = PencilAvailability()
    @State private var recentHex: [String] = []
    @State private var customPalettes: [ColorPalette] = []
    @State private var showingSystemColorPicker = false
    @State private var showingShareSheet = false
    @State private var showingLayersPanel = false
    @State private var showTimeline = false
    @State private var showingDeleteFrameConfirm = false
    @State private var playback: PlaybackController?
    /// Light haptic fired the instant a freehand stroke snaps to a straight line ("hold to straighten").
    private let lineSnapHaptic = UIImpactFeedbackGenerator(style: .light)
    /// Light haptic confirming an undo/redo (button or gesture).
    private let editHaptic = UIImpactFeedbackGenerator(style: .light)

    /// True when this draw's stored blob was recognized (V1/V2 magic) but failed to decode —
    /// i.e. corrupt. We then show an error and BLOCK all saves so the (recoverable) original is
    /// never overwritten by a blank, instead of silently substituting a blank canvas.
    private let loadFailed: Bool

    init(piece: Piece) {
        self.piece = piece
        // Synchronous load: frameData is already in-memory on the SwiftData object.
        // `decodeForEditing` THROWS on a corrupt recognized blob (vs. decodeAnyFrameData, which
        // would silently return a blank frame that the next save would make permanent).
        let editorState: EditorState
        var failed = false
        do {
            let result = try FrameCodec.decodeForEditing(piece.frameData,
                                                         fallbackByteCount: piece.size.byteCount)
            editorState = EditorState(piece: piece,
                                      frames: result.frames,
                                      activeFrameIndex: result.activeFrameIndex,
                                      fps: result.fps)
        } catch {
            failed = true
            // Throwaway placeholder so @State is initialized; never shown (error view replaces the
            // editor) and never saved (loadFailed gates persistence). Mirrors Piece(size:)'s blank.
            let layer = Layer(name: "Layer 1", pixels: Data(count: piece.size.byteCount))
            let frame = Frame(name: "Frame 1", layers: [layer], activeLayerID: layer.id)
            editorState = EditorState(piece: piece, frames: [frame], activeFrameIndex: 0,
                                      fps: FrameCodec.defaultFPS)
        }
        editorState.setReference(imageData: piece.referenceImageData)
        editorState.referenceOpacity = piece.referenceOpacity
        self._state = State(initialValue: editorState)
        self.loadFailed = failed
    }

    var body: some View {
        if loadFailed {
            loadErrorView
        } else {
            editorBody
        }
    }

    /// Shown instead of the editor when the draw can't be decoded. The original bytes are left
    /// untouched (saves are blocked), so the file is preserved rather than overwritten by a blank.
    private var loadErrorView: some View {
        ZStack {
            Color(white: 0.10).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Color.toolSelected)
                Text("THIS DRAW COULDN'T BE OPENED")
                    .font(.pixel(14))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Your file is preserved — nothing was changed.")
                    .font(.pixelBody(16))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                Button { dismiss() } label: {
                    Text("GALLERY")
                        .font(.pixel(11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .overlay(Rectangle().stroke(Color.toolSelected, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(40)
        }
        .accessibilityIdentifier("EditorLoadError")
    }

    private var editorBody: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                topBar
                Divider().overlay(Color.white.opacity(0.08))
                CanvasView(
                    state: state,
                    pencilAvailability: pencilAvailability,
                    onStrokePoint: { x, y in applyDrawPoint(x: x, y: y) },
                    onStrokeBegin: { handleStrokeBegin() },
                    onStrokeEnd: { handleStrokeEnd() },
                    onStrokeCancel: { handleStrokeCancel() },
                    onTap: { x, y in handleTap(x: x, y: y) },
                    onLineStraighten: { from, to, justSnapped in
                        handleLineStraighten(from: from, to: to, justSnapped: justSnapped)
                    },
                    onUndo: { handleUndo() },
                    onRedo: { handleRedo() }
                )
                .allowsHitTesting(!state.isPlaying)
                // No dividers around the animation strip and it shares the Color(white: 0.10)
                // background, so canvas → strip → tool strip read as one continuous surface.
                // The slot stays a fixed 88pt so toggling ANIMATE never resizes the canvas.
                Group {
                    if showTimeline {
                        FramesStrip(
                            state: state,
                            onAddFrame: addBlankFrameAfter,
                            onDuplicateFrame: duplicateActiveFrame,
                            onReorderFrame: { moveFrame(fromIndex: $0, toIndex: $1) },
                            onActivateFrame: setActiveFrameAndPersistIfDirty,
                            onTogglePlay: togglePlay,
                            onDeleteFrame: deleteActiveFrameWithConfirmIfNeeded
                        )
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 88)
                bottomBar
            }
            LayersPanel(
                state: state,
                isPresented: showingLayersPanel,
                onRenameLayer: { layerID, newName in
                    state.commitFloatingSelectionIfAny()
                    state.beginStructuralSnapshot()
                    state.frame.setName(id: layerID, to: newName)
                    state.commitStructuralChange()
                    saveCurrentFrame()
                },
                onStructuralChange: { saveCurrentFrame() },
                onReferenceImport: { rawData in
                    if let processed = ReferenceImageProcessor.process(rawData) {
                        state.setReference(imageData: processed)
                        saveReference()
                    }
                },
                onReferenceRemove: {
                    state.setReference(imageData: nil)
                    saveReference()
                },
                onReferenceOpacityCommit: { saveReference() },
                onDismiss: { showingLayersPanel = false }
            )
        }
        .background(Color(white: 0.10).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingSystemColorPicker) {
            DrawBitColorPicker(
                color: Binding(
                    get: { state.color },
                    set: { state.color = $0 }
                ),
                onDismiss: { showingSystemColorPicker = false },
                recentHex: recentHex,
                customPalettes: $customPalettes,
                pieceColors: { PaletteExtractor.colors(in: state.frame, size: state.size) }
            )
            .presentationDetents([.large])
            .presentationCornerRadius(0)
            .presentationBackground(Color(white: 0.10))
        }
        .onChange(of: showingSystemColorPicker) { _, isShowing in
            if !isShowing {
                addRecent(state.color.hex)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(piece: piece, frameCount: state.frames.count)
                .presentationDetents([.height(640)])
                .presentationCornerRadius(0)
                .presentationBackground(Color(white: 0.10))
        }
        .onAppear {
            // Diving into a piece ends the launch intro so its music doesn't bleed
            // into the canvas. No-op once the ~17s clip has already finished.
            IntroAudio.shared.stop()
            let repo = PieceRepository(context: modelContext)
            if let settings = try? repo.appSettings() {
                recentHex = settings.recentColors
                customPalettes = settings.customPalettes
            }
            showTimeline = state.frames.count > 1
        }
        .onChange(of: customPalettes) { _, _ in persistCustomPalettes() }
        .onDisappear {
            // Stop playback first so the timer doesn't keep mutating state during teardown.
            playback?.stop()
            if state.selection != nil {
                // Defensive: if the active layer somehow became locked while the
                // marquee was floating, drop the selection instead of committing
                // through the lock. Not currently reachable through any UI gesture
                // (the lock toggle in LayersPanel auto-commits before flipping
                // isLocked), but cheap forward-compat if a future code path
                // bypasses that shim. See EditorState.commitMarquee's doc comment.
                if state.activeLayerIsLocked {
                    state.cancelMarquee()
                } else {
                    state.commitMarquee()
                }
            }
            saveCurrentFrame()
        }
        .sheet(isPresented: $showingDeleteFrameConfirm) {
            ConfirmDialogSheet(
                title: "DELETE FRAME?",
                message: "This frame has content. Delete it from the sequence?",
                confirmLabel: "DELETE",
                onCancel: { showingDeleteFrameConfirm = false },
                onConfirm: {
                    showingDeleteFrameConfirm = false
                    deleteActiveFrame()
                }
            )
            .presentationDetents([.height(220)])
            .presentationCornerRadius(0)
            .presentationBackground(Color(white: 0.10))
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("GALLERY")
                        .font(.pixel(11))
                }
                .hoverPop()
            }
            .accessibilityIdentifier("Gallery")

            Button(action: handleUndo) {
                PixelArtIcon(pattern: PixelArtIcon.undoArrow, size: 22)
                    .frame(width: 44, height: 44)
                    .hoverPop()
            }
            // Unavailable → almost invisible, camouflaged into the dark chrome.
            .foregroundStyle(state.canUndo ? .white : .white.opacity(0.07))
            .disabled(!state.canUndo || state.isPlaying)
            .accessibilityIdentifier("Undo")
            .accessibilityLabel("Undo")
            Button(action: handleRedo) {
                PixelArtIcon(pattern: PixelArtIcon.redoArrow, size: 22)
                    .frame(width: 44, height: 44)
                    .hoverPop()
            }
            .foregroundStyle(state.canRedo ? .white : .white.opacity(0.07))
            .disabled(!state.canRedo || state.isPlaying)
            .accessibilityIdentifier("Redo")
            .accessibilityLabel("Redo")

            Spacer()
            Text(piece.size.displayName)
                .font(.pixel(12))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button {
                showingLayersPanel.toggle()
            } label: {
                Image("LayersIcon")
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .frame(width: 26, height: 26)
                    .frame(width: 44, height: 44)
                    .hoverPop()
            }
            .foregroundStyle(showingLayersPanel ? Self.layersActiveGreen : .white)
            .disabled(state.isPlaying)
            .accessibilityLabel("LAYERS")
            Button {
                if showTimeline {
                    showTimeline = false
                } else {
                    // First-time transition from still to animation: seed a 2nd frame
                    // so the strip has something to scrub. Frames are never auto-removed
                    // on hide — user work is preserved.
                    if state.frames.count == 1 {
                        addFrameAfterActive()
                    }
                    showTimeline = true
                }
            } label: {
                PixelArtIcon(pattern: PixelArtIcon.playTriangle, size: 22)
                    .frame(width: 44, height: 44)
                    .hoverPop()
            }
            .foregroundStyle(showTimeline ? Self.animateActiveGreen : .white)
            .disabled(state.isPlaying)
            .accessibilityIdentifier("Animate")
            .accessibilityLabel("ANIMATE")
            Button {
                // Auto-commit any floating marquee + persist before the sheet's
                // export reads from SwiftData. Otherwise the user's in-flight
                // cut+drag wouldn't appear in the exported GIF/APNG/PNG.
                commitFloatingMarqueeAndPersist()
                showingShareSheet = true
            } label: {
                // Vector glyph drawn to match the LAYERS icon's stroke weight, at the
                // same 26pt size. Inherits the white tint via the Canvas .foreground.
                ShareGlyph()
                    .frame(width: 26, height: 26)
                    .frame(width: 44, height: 44)
                    .hoverPop()
            }
            .disabled(state.isPlaying)
            .accessibilityLabel("SHARE")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var bottomBar: some View {
        ToolBar(
            state: state,
            selectedColor: Binding(
                get: { state.color },
                set: { state.color = $0 }
            ),
            onClear: clearCanvas,
            onRequestColorPicker: { showingSystemColorPicker = true }
        )
        .disabled(state.isPlaying)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(height: 72)
        .background(Color(white: 0.10))
    }

    // MARK: - Lock-pulse feedback

    private func triggerLockPulse(layerID: UUID) {
        state.lockPulseLayerID = layerID
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            // Only clear if it's still the same layer — if another pulse fired in the
            // meantime (different layer), don't stomp on its timer.
            if state.lockPulseLayerID == layerID {
                state.lockPulseLayerID = nil
            }
        }
    }

    // MARK: - Drawing actions

    private func applyDrawPoint(x: Int, y: Int) {
        let isMutatingTool = state.tool == .pencil    || state.tool == .eraser
                           || state.tool == .fill     || state.tool == .colorSwap
                           || state.tool == .marquee
        if isMutatingTool && state.activeLayerIsLocked {
            triggerLockPulse(layerID: state.frame.activeLayerID)
            return
        }

        // Vertical-centerline mirror. mx == x on the center column of an odd
        // grid, in which case the mirror call is a no-op duplicate that we
        // skip so undo doesn't get phantom writes. Both writes live inside
        // the same `mutateActiveLayerPixels` closure → one stroke snapshot.
        let mx = state.size.dimension - 1 - x
        let mirror = state.isMirrorEnabled && mx != x

        switch state.tool {
        case .pencil:
            state.mutateActiveLayerPixels { data in
                var grid = PixelGrid(data: data, size: state.size)
                state.revertPixelPerfectElbow(grid: &grid, beforeApplyingAt: (x, y))
                Pencil.paint(on: &grid, at: (x, y), color: state.color)
                if mirror { Pencil.paint(on: &grid, at: (mx, y), color: state.color) }
                data = grid.data
            }
        case .eraser:
            state.mutateActiveLayerPixels { data in
                var grid = PixelGrid(data: data, size: state.size)
                state.revertPixelPerfectElbow(grid: &grid, beforeApplyingAt: (x, y))
                Eraser.erase(on: &grid, at: (x, y))
                if mirror { Eraser.erase(on: &grid, at: (mx, y)) }
                data = grid.data
            }
        case .fill:
            state.mutateActiveLayerPixels { data in
                var grid = PixelGrid(data: data, size: state.size)
                Fill.fill(on: &grid, at: (x, y), with: state.color)
                if mirror { Fill.fill(on: &grid, at: (mx, y), with: state.color) }
                data = grid.data
            }
        case .colorSwap:
            // Sample from the active layer, not the composite — swap should only affect this layer.
            // Transparent pixels are skipped to avoid "tap empty area = paint everything".
            let picked = state.activeLayerPixelGrid.pixel(x: x, y: y)
            guard picked.a > 0, picked != state.color else { return }
            // Mirror-sample BEFORE the first swap mutates the grid — otherwise
            // the second sample would see post-swap pixels.
            let mirrorPicked: RGBA? = {
                guard mirror else { return nil }
                let p = state.activeLayerPixelGrid.pixel(x: mx, y: y)
                return (p.a > 0 && p != state.color) ? p : nil
            }()
            state.mutateActiveLayerPixels { data in
                var grid = PixelGrid(data: data, size: state.size)
                ColorSwap.swap(on: &grid, from: picked, to: state.color)
                if let mp = mirrorPicked { ColorSwap.swap(on: &grid, from: mp, to: state.color) }
                data = grid.data
            }
        case .eyedropper:
            let buffer = Compositor.composite(state.frame, size: state.size)
            let grid = PixelGrid(data: buffer.data, size: state.size)
            if let picked = Eyedropper.pick(from: grid, at: (x, y)) {
                state.color = picked
            }
        case .marquee:
            applyMarqueePoint(x: x, y: y)
        }
    }

    private func applyMarqueePoint(x: Int, y: Int) {
        if state.isMarqueeDefining {
            state.updateMarqueeDefine(to: (x, y))
            return
        }
        if state.isMarqueeDragging {
            state.updateMarqueeDrag(to: (x, y))
            return
        }
        // First point of a marquee stroke: tap inside floating selection drags it; tap
        // anywhere else commits any existing selection and starts defining a new one.
        if let sel = state.selection, sel.displayBounds.contains(x: x, y: y) {
            state.beginMarqueeDrag(at: (x, y))
        } else {
            // Block starting a new define on a locked layer. (Dragging an already-floating
            // selection is allowed above — those pixels are already detached from the layer.)
            if state.activeLayerIsLocked {
                triggerLockPulse(layerID: state.frame.activeLayerID)
                return
            }
            if state.selection != nil {
                state.commitMarquee()
                saveCurrentFrame()
            }
            state.beginMarqueeDefine(at: (x, y))
        }
    }

    private func handleStrokeBegin() {
        // For marquee, the snapshot is taken inside beginMarqueeDefine on the first point.
        if state.tool != .marquee {
            state.beginStrokeSnapshot()
        }
    }

    private func handleStrokeEnd() {
        if state.tool == .marquee {
            if state.isMarqueeDefining {
                state.endMarqueeDefine()
            } else if state.isMarqueeDragging {
                state.endMarqueeDrag()
            }
            // No save while floating — commit happens on tap-outside / tool-switch / dismiss.
        } else if state.activeLayerIsLocked {
            // Lock guard fired during this stroke: discard the orphaned snapshot
            // (taken in handleStrokeBegin before applyDrawPoint had a chance to
            // run the lock guard) without pushing a no-op undo entry.
            state.cancelStroke()
        } else {
            commitStrokeAndSave()
        }
    }

    private func handleStrokeCancel() {
        if state.tool == .marquee {
            // Cancel the in-progress define; keep any pre-existing floating selection alone.
            if state.isMarqueeDefining {
                state.cancelMarquee()
            } else {
                state.endMarqueeDrag()
            }
        } else {
            state.cancelStroke()
        }
    }

    /// Undo/redo, shared by the top-bar buttons and the two/three-finger-tap gestures. A light
    /// haptic confirms the action — especially useful for the invisible gesture. Guarded so the
    /// gesture path (which doesn't go through a disabled button) can't fire while playing or empty.
    private func handleUndo() {
        guard !state.isPlaying, state.canUndo else { return }
        state.undo()
        saveCurrentFrame()
        editHaptic.impactOccurred()
    }

    private func handleRedo() {
        guard !state.isPlaying, state.canRedo else { return }
        state.redo()
        saveCurrentFrame()
        editHaptic.impactOccurred()
    }

    /// Pencil "hold to straighten": redraw the active layer as a straight line from the stroke's
    /// start (`from`) to the current finger (`to`), off the pre-stroke snapshot, so re-aiming is a
    /// clean restore. A light haptic marks the lock. The stroke commits normally in `handleStrokeEnd`.
    private func handleLineStraighten(from: (Int, Int), to: (Int, Int), justSnapped: Bool) {
        guard state.tool == .pencil else { return }
        if state.activeLayerIsLocked {
            triggerLockPulse(layerID: state.frame.activeLayerID)
            return
        }
        state.applyStraightLine(from: from, to: to, mirror: state.isMirrorEnabled)
        let perfect = LineTool.isPerfectAngle(from: from, to: to)
        if justSnapped {
            // The snap haptic owns this instant; just seed the perfect-angle tracker.
            lineSnapHaptic.impactOccurred()
        } else if perfect, !state.lineWasPerfect {
            // Detent: the line just locked into a perfect angle (H / V / 45°) — click + haptic.
            SelectionFeedback.shared.fire()
        }
        state.lineWasPerfect = perfect
    }

    private func handleTap(x: Int, y: Int) {
        if state.tool == .marquee {
            if let sel = state.selection, !sel.displayBounds.contains(x: x, y: y) {
                state.commitMarquee()
                saveCurrentFrame()
            }
            // Tap inside floating selection or with no selection: no-op.
            return
        }
        // Lock guard: triggers a pulse on the row and returns without snapshotting.
        if state.activeLayerIsLocked {
            triggerLockPulse(layerID: state.frame.activeLayerID)
            return
        }
        state.beginStrokeSnapshot()
        applyDrawPoint(x: x, y: y)
        commitStrokeAndSave()
    }

    private func saveCurrentFrame() {
        // Never persist when the draw failed to load — the in-memory `state` is a blank
        // placeholder, and saving it would overwrite the corrupt-but-recoverable original.
        guard !loadFailed else { return }
        let repo = PieceRepository(context: modelContext)
        try? repo.saveFrames(piece: piece,
                             frames: state.frames,
                             activeFrameIndex: state.activeFrameIndex,
                             fps: state.fps)
    }

    private func saveReference() {
        guard !loadFailed else { return }
        let repo = PieceRepository(context: modelContext)
        try? repo.saveReference(piece: piece,
                                imageData: state.referenceImageData,
                                opacity: state.referenceOpacity)
    }

    private func clearCanvas() {
        // Clear is a pixel mutation on the active layer — same lock semantics as
        // pencil/eraser/fill/marquee. Without this guard, Stage 4's lock would
        // have a hole.
        if state.activeLayerIsLocked {
            triggerLockPulse(layerID: state.frame.activeLayerID)
            return
        }
        if state.selection != nil { state.cancelMarquee() }
        state.beginStrokeSnapshot()
        state.setActiveLayerPixels(Data(count: state.size.byteCount))
        state.commitStroke()
        saveCurrentFrame()
    }

    private func commitStrokeAndSave() {
        state.commitStroke()
        saveCurrentFrame()
        // Pencil-only: record color into recents on stroke commit. Skip for eraser/eyedropper.
        if state.tool == .pencil || state.tool == .fill {
            addRecent(state.color.hex)
        }
    }

    private func addRecent(_ hex: String) {
        let repo = PieceRepository(context: modelContext)
        if let settings = try? repo.appSettings() {
            settings.addRecentColor(hex)
            recentHex = settings.recentColors
            try? modelContext.save()
        }
    }

    /// Writes the live custom-palette list back to AppSettings. Mirrors `addRecent`'s seam:
    /// all SwiftData stays here, never in the picker.
    private func persistCustomPalettes() {
        let repo = PieceRepository(context: modelContext)
        if let settings = try? repo.appSettings() {
            settings.customPalettes = customPalettes
            try? modelContext.save()
        }
    }

    // MARK: - Frame-sequence mutations

    /// Wraps any frame-sequence mutation in the standard pattern:
    /// 1. Commit any floating marquee.
    /// 2. Take a sequence-level snapshot.
    /// 3. Run the mutation.
    /// 4. Clamp `activeFrameIndex` if the sequence shrank.
    /// 5. Commit the snapshot to the undo stack.
    /// 6. Save via the repository.
    private func mutateFrameSequence(_ body: (inout [Frame]) -> Void) {
        state.commitFloatingSelectionIfAny()
        state.beginSequenceSnapshot()
        body(&state.frames)
        if state.activeFrameIndex >= state.frames.count {
            state.activeFrameIndex = max(0, state.frames.count - 1)
        }
        state.commitSequenceChange()
        saveCurrentFrame()
    }

    private var activeFrameHasContent: Bool {
        let frame = state.frames[state.activeFrameIndex]
        return frame.layers.contains { layer in
            layer.pixels.contains(where: { $0 != 0 })
        }
    }

    func deleteActiveFrameWithConfirmIfNeeded() {
        state.commitFloatingSelectionIfAny()
        if activeFrameHasContent {
            showingDeleteFrameConfirm = true
        } else {
            deleteActiveFrame()
        }
    }

    func addFrameAfterActive() {
        let activeID = state.frames[state.activeFrameIndex].id
        mutateFrameSequence { frames in
            if let newID = FrameSequence.addFrameAfter(frameID: activeID, in: &frames),
               let idx = frames.firstIndex(where: { $0.id == newID }) {
                state.activeFrameIndex = idx
            }
        }
    }

    func addBlankFrameAfter() {
        let activeID = state.frames[state.activeFrameIndex].id
        mutateFrameSequence { frames in
            if let newID = FrameSequence.addBlankFrameAfter(frameID: activeID, in: &frames),
               let idx = frames.firstIndex(where: { $0.id == newID }) {
                state.activeFrameIndex = idx
            }
        }
    }

    func duplicateActiveFrame() {
        let activeID = state.frames[state.activeFrameIndex].id
        mutateFrameSequence { frames in
            if let newID = FrameSequence.duplicateFrame(activeID, in: &frames),
               let idx = frames.firstIndex(where: { $0.id == newID }) {
                state.activeFrameIndex = idx
            }
        }
    }

    /// Index-based reorder for drag-and-drop (plain from/to, not `.onMove` offsets).
    func moveFrame(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              state.frames.indices.contains(fromIndex) else { return }
        let activeID = state.frames[state.activeFrameIndex].id
        let movingID = state.frames[fromIndex].id
        mutateFrameSequence { frames in
            FrameSequence.move(frameID: movingID, toIndex: toIndex, in: &frames)
            if let newActiveIdx = frames.firstIndex(where: { $0.id == activeID }) {
                state.activeFrameIndex = newActiveIdx
            }
        }
    }

    func deleteActiveFrame() {
        let activeID = state.frames[state.activeFrameIndex].id
        mutateFrameSequence { frames in
            FrameSequence.removeFrame(activeID, in: &frames)
        }
    }

    func setActiveFrameAndPersistIfDirty(index: Int) {
        let hadSelection = state.selection != nil
        state.setActiveFrame(index: index)
        if hadSelection {
            // setActiveFrame committed the marquee, mutating layer pixels — persist.
            saveCurrentFrame()
        }
    }

    func togglePlay() {
        if playback == nil { playback = PlaybackController(state: state) }
        if state.isPlaying {
            playback?.stop()
            // Persist the frame the user paused on so a force-quit doesn't lose it.
            saveCurrentFrame()
        } else {
            // Auto-commit any floating selection BEFORE starting playback (the
            // controller also commits as defense-in-depth). Persist immediately so
            // the now-merged pixels survive a force-quit during playback.
            commitFloatingMarqueeAndPersist()
            playback?.start()
        }
    }

    /// Canonical "auto-commit floating selection before <X>" call site. Use this
    /// before any operation that either (a) reads the persisted piece state
    /// (export, share) or (b) mutates the active-frame index in a way that
    /// changes the destination of an eventual marquee commit (playback). The
    /// `saveCurrentFrame()` after commit ensures the now-merged pixels survive a
    /// force-quit between the commit and the next user-driven save.
    private func commitFloatingMarqueeAndPersist() {
        let hadSelection = state.selection != nil
        state.commitFloatingSelectionIfAny()
        if hadSelection { saveCurrentFrame() }
    }

    // MARK: - Pixel icons (topBar)

    /// Tint for ANIMATE when the timeline is open — a desaturated bright
    /// green, deliberately distinct from the deeper green used for LAYERS-active.
    private static let animateActiveGreen = Color(red: 0.50, green: 0.85, blue: 0.55)

    /// Tint for LAYERS when the panel is open — a deeper, more saturated
    /// emerald that reads as a clearly different state from ANIMATE's lime.
    private static let layersActiveGreen = Color(red: 0.20, green: 0.60, blue: 0.35)

}

/// Top-bar SHARE glyph — a thin open-top box with a solid up-arrow, drawn to match the
/// LAYERS icon's stroke weight (≈1.2pt at 26pt). A vector (scalable, crisp) that inherits
/// the surrounding `foregroundStyle` via the Canvas `.foreground`, replacing the heavier
/// ShareIcon PNG.
/// The top-bar SHARE/export glyph. Internal (not file-private) so the HELP page's
/// EXPORT tile can reuse the exact same sprite the editor's share button shows.
struct ShareGlyph: View {
    var body: some View {
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height)
            let cx = s / 2
            let style = StrokeStyle(lineWidth: s * 0.05, lineCap: .square, lineJoin: .miter)

            // Open-top box: left wall → bottom → right wall, plus two short top stubs
            // leaving a gap for the arrow shaft.
            let bx0 = s * 0.18, bx1 = s * 0.82
            let bt = s * 0.42, bb = s * 0.94
            let stub = s * 0.16
            var box = Path()
            box.move(to: CGPoint(x: bx0, y: bt))
            box.addLine(to: CGPoint(x: bx0, y: bb))
            box.addLine(to: CGPoint(x: bx1, y: bb))
            box.addLine(to: CGPoint(x: bx1, y: bt))
            box.move(to: CGPoint(x: bx1, y: bt))
            box.addLine(to: CGPoint(x: bx1 - stub, y: bt))
            box.move(to: CGPoint(x: bx0, y: bt))
            box.addLine(to: CGPoint(x: bx0 + stub, y: bt))
            ctx.stroke(box, with: .foreground, style: style)

            // Arrow shaft (runs from just under the head down into the box).
            var shaft = Path()
            shaft.move(to: CGPoint(x: cx, y: s * 0.28))
            shaft.addLine(to: CGPoint(x: cx, y: s * 0.64))
            ctx.stroke(shaft, with: .foreground, style: style)

            // Solid up-arrowhead.
            var head = Path()
            head.move(to: CGPoint(x: cx, y: s * 0.06))
            head.addLine(to: CGPoint(x: cx - s * 0.20, y: s * 0.30))
            head.addLine(to: CGPoint(x: cx + s * 0.20, y: s * 0.30))
            head.closeSubpath()
            ctx.fill(head, with: .foreground)
        }
    }
}

