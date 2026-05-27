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
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color(white: 0.10).ignoresSafeArea())
            // FM is pinned to the bottom-left of the gallery viewport as a
            // fixed overlay rather than a grid cell. The 120pt square matches
            // a grid tile so it visually echoes the row above; the leading
            // and bottom paddings match the grid's own paddings so the FM
            // tile aligns with the leftmost column and rests at the same
            // bottom offset. Inline play/pause and the body-tap-to-push-
            // `FMScreen` behaviour are unchanged.
            .overlay(alignment: .bottomLeading) {
                FMTile()
                    .frame(width: 120, height: 120)
                    .onTapGesture { showingFM = true }
                    .padding(.leading, 20)
                    .padding(.bottom, 24)
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
                .presentationDetents([.medium])
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
                Image(systemName: "info.circle")
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: Self.helpButtonHitSize, height: Self.helpButtonHitSize)
                    .foregroundStyle(.white.opacity(0.85))
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
