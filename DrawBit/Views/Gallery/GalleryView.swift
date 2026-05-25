import SwiftUI
import SwiftData

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Piece.updatedAt, order: .reverse) private var pieces: [Piece]
    @State private var showingNewSheet = false
    @State private var selectedPiece: Piece?

    @State private var renameTarget: Piece?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: Piece?

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                RadioStrip()
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(pieces) { piece in
                            thumbnailCell(for: piece)
                        }
                        NewPieceTile()
                            .onTapGesture { showingNewSheet = true }
                            .accessibilityLabel("New")
                            .accessibilityIdentifier("NewButton")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color(white: 0.10).ignoresSafeArea())
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

    private var topBar: some View {
        Text("GALLERY")
            .font(.pixel(20))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
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
