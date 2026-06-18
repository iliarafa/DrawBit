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
            }
            .toolbar(.hidden, for: .navigationBar)
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
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    @ViewBuilder
    private func thumbnailCell(for piece: Piece) -> some View {
        PieceThumbnailView(piece: piece)
            .onTapGesture { selectedPiece = piece }
            .contextMenu {
                Button("Rename") {
                    renameTarget = piece
                    renameDraft = piece.name ?? ""
                }
                Button("Duplicate") { duplicate(piece) }
                Divider()
                Button("Delete", role: .destructive) { deleteTarget = piece }
            }
    }

    private func duplicate(_ piece: Piece) {
        let repo = PieceRepository(context: modelContext)
        _ = try? repo.duplicate(piece: piece)
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
