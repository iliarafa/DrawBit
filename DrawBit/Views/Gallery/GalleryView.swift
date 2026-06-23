import SwiftUI
import SwiftData

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Piece.updatedAt, order: .reverse) private var pieces: [Piece]
    @State private var showingNewSheet = false
    @State private var selectedPiece: Piece?
    /// True while the FM destination is pushed onto the navigation stack.
    /// Mirrors the `selectedPiece` pattern but on a Bool because the FM screen
    /// is a singleton destination (only one station).
    @State private var showingFM = false
    /// True while the help destination is pushed. Same shape as `showingFM`.
    @State private var showingHelp = false

    @State private var renameTarget: Piece?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: Piece?

    /// When true (only when arriving from the launch sequence), the gallery plays a
    /// one-time staggered intro: each of its four elements pops in as a whole, in
    /// order — GALLERY title, the "i", the works grid, then DRAWBIT FM.
    let playIntro: Bool

    @State private var showTitle: Bool
    @State private var showInfo: Bool
    @State private var showWorks: Bool
    @State private var showFM: Bool
    @State private var didRunIntro = false

    init(playIntro: Bool = false) {
        self.playIntro = playIntro
        // Start hidden only when the intro will play; otherwise fully shown so normal
        // entries (and UI tests) render complete on the first frame and stay queryable.
        let shown = !playIntro
        _showTitle = State(initialValue: shown)
        _showInfo = State(initialValue: shown)
        _showWorks = State(initialValue: shown)
        _showFM = State(initialValue: shown)
    }

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    /// Uniform inset for the gallery's edge-anchored tiles (the "+" cell at
    /// top-left and the FM tile at bottom-left) so they sit as a balanced pair.
    private let edgeInset: CGFloat = 30

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        // NEW tile lives at position 0 — the gallery's primary
                        // action, top-left of the grid. Pieces follow, sorted
                        // by `updatedAt` descending, so the newest piece sits
                        // immediately to its right.
                        NewPieceTile()
                            .onTapGesture { showingNewSheet = true }
                            .accessibilityLabel("New")
                            .accessibilityIdentifier("NewButton")
                        ForEach(pieces) { piece in
                            thumbnailCell(for: piece)
                        }
                    }
                    .padding(edgeInset)
                }
                .scrollContentBackground(.hidden)
                .opacity(showWorks ? 1 : 0)
            }
            .background(Color(white: 0.10).ignoresSafeArea())
            // FM is pinned to the bottom-RIGHT of the gallery viewport as a
            // fixed overlay rather than a grid cell, placing it diagonally
            // opposite the "+" tile (top-left of the grid) so the two
            // edge-anchored tiles balance the empty space across the screen.
            // The 120pt square matches a grid tile; the trailing and bottom
            // paddings reuse `edgeInset` so it mirrors the grid's own margins.
            // The tile sits in a full-screen, safe-area-ignoring frame so its
            // `edgeInset` padding is measured from the PHYSICAL screen edges on
            // both the trailing and bottom sides — otherwise the bottom gap
            // would stack on top of the home-indicator safe area and read as
            // ~double the side gap. Inline play/pause and the body-tap-to-push-
            // `FMScreen` behaviour are unchanged.
            .overlay {
                FMTile()
                    .frame(width: 120, height: 120)
                    .onTapGesture { showingFM = true }
                    .padding(edgeInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .ignoresSafeArea()
                    .opacity(showFM ? 1 : 0)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { runIntro() }
            .sheet(isPresented: $showingNewSheet) {
                NewPieceSheet { size in
                    do {
                        let repo = PieceRepository(context: modelContext)
                        let piece = try repo.createPiece(size: size)
                        selectedPiece = piece
                    } catch {
                        // v1: swallow; surface via alert later if needed
                    }
                }
                // Height sized for the 7 size rows + nav bar (~48pt × 7 + chrome).
                .presentationDetents([.height(420)])
                .presentationCornerRadius(0)
                .presentationBackground(Color(white: 0.10))
            }
            .navigationDestination(item: $selectedPiece) { piece in
                EditorView(piece: piece)
            }
            .navigationDestination(isPresented: $showingFM) {
                FMScreen()
            }
            .navigationDestination(isPresented: $showingHelp) {
                HelpScreen()
            }
            .sheet(isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                RenamePieceSheet(
                    draft: $renameDraft,
                    onCancel: { renameTarget = nil },
                    onSave: {
                        if let target = renameTarget {
                            let repo = PieceRepository(context: modelContext)
                            try? repo.rename(piece: target, to: renameDraft)
                        }
                        renameTarget = nil
                    }
                )
                .presentationDetents([.height(220)])
                .presentationCornerRadius(0)
                .presentationBackground(Color(white: 0.10))
            }
            .sheet(isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                DeletePieceSheet(
                    onCancel: { deleteTarget = nil },
                    onDelete: {
                        if let target = deleteTarget {
                            let repo = PieceRepository(context: modelContext)
                            try? repo.delete(piece: target)
                        }
                        deleteTarget = nil
                    }
                )
                .presentationDetents([.height(200)])
                .presentationCornerRadius(0)
                .presentationBackground(Color(white: 0.10))
            }
        }
    }

    /// Width of the trailing "?" help button's hit area. A clear leading
    /// spacer of the same width keeps the `GALLERY` title visually centered
    /// despite the trailing button taking real estate on only one side.
    private static let helpButtonHitSize: CGFloat = 44

    private var topBar: some View {
        HStack(spacing: 0) {
            // Invisible leading spacer balancing the trailing button so the
            // centered title remains centered on the screen, not pushed left.
            Color.clear
                .frame(width: Self.helpButtonHitSize, height: Self.helpButtonHitSize)

            Text("GALLERY")
                .font(.pixel(20))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .opacity(showTitle ? 1 : 0)

            Button {
                showingHelp = true
            } label: {
                // Pixel-font "i" instead of SF Symbol so the glyph shares the
                // GALLERY title's baseline, rasterization, and weight — the
                // two read as part of the same row instead of two different
                // typefaces side by side. pixel(20) matches the title size.
                Text("i")
                    .font(.pixel(20))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: Self.helpButtonHitSize, height: Self.helpButtonHitSize)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Help.button")
            .accessibilityLabel("Help")
            .opacity(showInfo ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    @ViewBuilder
    private func thumbnailCell(for piece: Piece) -> some View {
        PieceCell(
            piece: piece,
            onOpen: { selectedPiece = piece },
            onRename: {
                renameTarget = piece
                renameDraft = piece.name ?? ""
            },
            onDuplicate: { duplicate(piece) },
            onDelete: { deleteTarget = piece }
        )
    }

    private func duplicate(_ piece: Piece) {
        let repo = PieceRepository(context: modelContext)
        _ = try? repo.duplicate(piece: piece)
    }

    /// One-time staggered intro: pop the four elements in, in order, once the
    /// launch sequence has handed off to the gallery. Each appears as a whole (one
    /// "pixel" placed); the gap between moves is the only timing. Runs once and only
    /// for the launch path — `playIntro` is false on normal entries and under UI test.
    private func runIntro() {
        guard playIntro, !UITestSupport.isRunning, !didRunIntro else { return }
        didRunIntro = true
        // Build completes at gap*4. Slowed from 0.22 (~0.88s) to breathe with the
        // intro music — now ~2.38s end to end.
        let gap = 0.595
        DispatchQueue.main.asyncAfter(deadline: .now() + gap * 1) { showTitle = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + gap * 2) { showInfo = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + gap * 3) { showWorks = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + gap * 4) { showFM = true }
    }
}

struct PixelArtIcon: View {
    let pattern: [String]
    let size: CGFloat

    /// The editor's ANIMATE play triangle (11×11). Shared so the HELP page's
    /// ANIMATION tile shows the exact same sprite the user taps above the canvas.
    static let playTriangle: [String] = [
        "...........",
        ".#.........",
        ".###.......",
        ".#####.....",
        ".#######...",
        ".#########.",
        ".#######...",
        ".#####.....",
        ".###.......",
        ".#.........",
        "...........",
    ]

    var body: some View {
        Canvas { ctx, sz in
            let cols = pattern.first?.count ?? 0
            let rows = pattern.count
            guard cols > 0, rows > 0 else { return }
            let cell = min(sz.width / CGFloat(cols), sz.height / CGFloat(rows))
            for (y, row) in pattern.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    let rect = CGRect(
                        x: CGFloat(x) * cell,
                        y: CGFloat(y) * cell,
                        width: cell,
                        height: cell
                    )
                    ctx.fill(Path(rect), with: .foreground)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// A gallery piece tile with its own themed long-press menu (Rename / Duplicate /
/// Delete). Gallery tiles have no drag gesture, so — unlike the animation frames,
/// where `.draggable` swallows the long press — a custom themed popover works here,
/// replacing the unthemeable native `.contextMenu`. Styled to match `FramesStrip.fpsMenu`.
private struct PieceCell: View {
    let piece: Piece
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var showingMenu = false

    var body: some View {
        PieceThumbnailView(piece: piece)
            .onTapGesture { onOpen() }
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.4, maximumDistance: 10)
                    .onEnded { _ in showingMenu = true }
            )
            .popover(isPresented: $showingMenu) { menu }
            // VoiceOver can't long-press, so keep the actions reachable via the rotor.
            .accessibilityAction(named: "Rename") { onRename() }
            .accessibilityAction(named: "Duplicate") { onDuplicate() }
            .accessibilityAction(named: "Delete") { onDelete() }
    }

    private var menu: some View {
        VStack(spacing: 0) {
            row("RENAME", systemImage: "pencil", id: "PieceMenu.rename", action: onRename)
            divider
            row("DUPLICATE", systemImage: "plus.square.on.square", id: "PieceMenu.duplicate", action: onDuplicate)
            divider
            row("DELETE", systemImage: "trash", id: "PieceMenu.delete", destructive: true, action: onDelete)
        }
        .frame(width: 184)
        .background(Color(white: 0.12))
        .presentationCompactAdaptation(.popover)
        .presentationBackground(Color(white: 0.12))
    }

    private var divider: some View {
        Divider().overlay(Color.white.opacity(0.12))
    }

    private func row(_ title: String,
                     systemImage: String,
                     id: String,
                     destructive: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button {
            // Dismiss the popover first; the Rename/Delete actions then present their
            // own sheets from the gallery (Duplicate is instant).
            showingMenu = false
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.pixel(10))
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? Color.destructive : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
