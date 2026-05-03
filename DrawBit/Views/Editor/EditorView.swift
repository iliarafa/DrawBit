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

    init(piece: Piece) {
        self.piece = piece
        // Synchronous load: frameData is already in-memory on the SwiftData object.
        // If the eager migration in DrawBitApp ran (Task 1.13), this is a v2 blob.
        // Per-read defense-in-depth: if it's still v1 raw bytes, wrap it; the next
        // saveFrame will write back the v2 blob.
        let frame: Frame
        if FrameCodec.hasV1MagicPrefix(piece.frameData) {
            frame = (try? FrameCodec.decode(piece.frameData))
                ?? FrameCodec.wrapV1Data(Data(count: piece.size.byteCount), defaultName: "Layer 1")
        } else {
            frame = FrameCodec.wrapV1Data(piece.frameData, defaultName: "Layer 1")
        }
        self._state = State(initialValue: EditorState(piece: piece, frame: frame))
    }

    var body: some View {
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
            bottomBar
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
                saveCurrentFrame()
            }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
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
                ToolBar(state: state, onClear: clearCanvas)
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

    // MARK: - Drawing actions

    private func applyDrawPoint(x: Int, y: Int) {
        let isMutatingTool = state.tool == .pencil || state.tool == .eraser
                           || state.tool == .fill   || state.tool == .marquee
        if isMutatingTool && state.activeLayerIsLocked { return }

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
        state.beginStrokeSnapshot()
        applyDrawPoint(x: x, y: y)
        commitStrokeAndSave()
    }

    private func saveCurrentFrame() {
        let repo = PieceRepository(context: modelContext)
        try? repo.saveFrame(piece: piece, state.frame)
    }

    private func clearCanvas() {
        if state.selection != nil { state.cancelMarquee() }
        state.beginStrokeSnapshot()
        state.setActiveLayerPixels(Data(count: state.size.byteCount))
        state.commitStroke()
        saveCurrentFrame()
    }

    private func commitStrokeAndSave() {
        state.commitStroke()
        let repo = PieceRepository(context: modelContext)
        try? repo.saveFrame(piece: piece, state.frame)
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
}

