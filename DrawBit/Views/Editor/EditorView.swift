import SwiftUI
import SwiftData

struct EditorView: View {
    let piece: Piece
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var state: EditorState
    @State private var pencilAvailability = PencilAvailability()
    @State private var recentHex: [String] = []
    @State private var showingSystemColorPicker = false
    @State private var showingShareSheet = false
    @State private var showingLayersPanel = false
    @State private var showingDeleteFrameConfirm = false

    init(piece: Piece) {
        self.piece = piece
        // Synchronous load: frameData is already in-memory on the SwiftData object.
        // decodeAnyFrameData handles V2 sequence, V1 single-frame, and raw legacy bytes.
        let result = FrameCodec.decodeAnyFrameData(piece.frameData,
                                                    fallbackByteCount: piece.size.byteCount)
        self._state = State(initialValue: EditorState(piece: piece,
                                                      frames: result.frames,
                                                      activeFrameIndex: result.activeFrameIndex,
                                                      fps: result.fps))
    }

    var body: some View {
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
                    onTap: { x, y in handleTap(x: x, y: y) }
                )
                Divider().overlay(Color.white.opacity(0.08))
                FramesStrip(
                    state: state,
                    onAddFrame: addFrameAfterActive,
                    onDuplicateFrame: addFrameAfterActive,
                    onDeleteFrame: deleteActiveFrameWithConfirmIfNeeded,
                    onReorderFrame: reorderFrame,
                    onRenameFrame: renameFrame,
                    onActivateFrame: setActiveFrameAndPersistIfDirty
                )
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
                recentHex: recentHex
            )
            .presentationDetents([.large])
            .presentationCornerRadius(0)
        }
        .onChange(of: showingSystemColorPicker) { _, isShowing in
            if !isShowing {
                addRecent(state.color.hex)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(piece: piece)
                .presentationDetents([.height(460)])
                .presentationCornerRadius(0)
        }
        .onAppear {
            let repo = PieceRepository(context: modelContext)
            if let settings = try? repo.appSettings() {
                recentHex = settings.recentColors
            }
        }
        .onDisappear {
            if state.selection != nil {
                state.commitMarquee()
            }
            saveCurrentFrame()
        }
        .confirmationDialog(
            "Delete Frame?",
            isPresented: $showingDeleteFrameConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteActiveFrame()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frame has content. Delete it from the sequence?")
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
            }
            .accessibilityIdentifier("Gallery")
            Spacer()
            Text(piece.size.displayName)
                .font(.pixel(12))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button {
                showingLayersPanel.toggle()
            } label: {
                Text("LAYERS").font(.pixel(11))
            }
            .foregroundStyle(showingLayersPanel ? .blue : .white)
            Button {
                showingShareSheet = true
            } label: {
                Text("SHARE")
                    .font(.pixel(11))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 20) {
                ToolBar(
                    state: state,
                    onUndo: {
                        state.undo()
                        saveCurrentFrame()
                    },
                    onRedo: {
                        state.redo()
                        saveCurrentFrame()
                    },
                    onClear: clearCanvas
                )
                Divider().frame(height: 36).overlay(Color.white.opacity(0.15))
                RecentColorsStrip(
                    selectedColor: Binding(
                        get: { state.color },
                        set: { state.color = $0 }
                    ),
                    recentHex: $recentHex,
                    onRequestColorPicker: { showingSystemColorPicker = true }
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(height: 72)
        .background(Color(white: 0.09))
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

        switch state.tool {
        case .pencil:
            state.mutateActiveLayerPixels { data in
                var grid = PixelGrid(data: data, size: state.size)
                Pencil.paint(on: &grid, at: (x, y), color: state.color)
                data = grid.data
            }
        case .eraser:
            state.mutateActiveLayerPixels { data in
                var grid = PixelGrid(data: data, size: state.size)
                Eraser.erase(on: &grid, at: (x, y))
                data = grid.data
            }
        case .fill:
            state.mutateActiveLayerPixels { data in
                var grid = PixelGrid(data: data, size: state.size)
                Fill.fill(on: &grid, at: (x, y), with: state.color)
                data = grid.data
            }
        case .colorSwap:
            // Sample from the active layer, not the composite — swap should only affect this layer.
            // Transparent pixels are skipped to avoid "tap empty area = paint everything".
            let picked = state.activeLayerPixelGrid.pixel(x: x, y: y)
            guard picked.a > 0, picked != state.color else { return }
            state.mutateActiveLayerPixels { data in
                var grid = PixelGrid(data: data, size: state.size)
                ColorSwap.swap(on: &grid, from: picked, to: state.color)
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
        let repo = PieceRepository(context: modelContext)
        try? repo.saveFrames(piece: piece,
                             frames: state.frames,
                             activeFrameIndex: state.activeFrameIndex,
                             fps: state.fps)
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

    func deleteActiveFrame() {
        let activeID = state.frames[state.activeFrameIndex].id
        mutateFrameSequence { frames in
            FrameSequence.removeFrame(activeID, in: &frames)
        }
    }

    func renameFrame(id: UUID, to name: String) {
        mutateFrameSequence { frames in
            FrameSequence.setName(frameID: id, to: name, in: &frames)
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

    func reorderFrame(from: Int, toOffset: Int) {
        let activeID = state.frames[state.activeFrameIndex].id
        let movingID = state.frames[from].id
        guard let modelTo = FrameSequence.modelTargetIndex(displayedFrom: from,
                                                           newOffset: toOffset,
                                                           count: state.frames.count) else { return }
        mutateFrameSequence { frames in
            FrameSequence.move(frameID: movingID, toIndex: modelTo, in: &frames)
            if let newActiveIdx = frames.firstIndex(where: { $0.id == activeID }) {
                state.activeFrameIndex = newActiveIdx
            }
        }
    }
}

