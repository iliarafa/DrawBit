import SwiftUI
import SwiftData

struct GalleryView: View {
    var onHome: () -> Void
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
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(pieces) { piece in
                            thumbnailCell(for: piece)
                        }
                        NewPieceTile(dimension: pieces.last?.size.dimension ?? 32)
                            .onTapGesture { showingNewSheet = true }
                            .accessibilityLabel("New")
                            .accessibilityIdentifier("NewButton")
                    }
                    .padding()
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
            }
        }
    }

    private var topBar: some View {
        ZStack {
            Text("BITME")
                .font(.pixel(20))
            HStack {
                Button {
                    onHome()
                } label: {
                    PixelArtIcon(pattern: GalleryView.housePattern, size: 22)
                }
                .accessibilityLabel("Home")
                .accessibilityIdentifier("HomeButton")
                Spacer()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private static let housePattern: [String] = [
        "...##...",
        "..####..",
        ".######.",
        "########",
        "########",
        ".#.##.#.",
        ".#.##.#.",
        ".#.##.#.",
    ]

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
