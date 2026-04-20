import SwiftUI
import SwiftData

struct GalleryView: View {
    var onHome: () -> Void = {}
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
            ScrollView {
                if pieces.isEmpty {
                    ContentUnavailableView(
                        "No pieces yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Tap + New to create your first canvas.")
                    )
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(pieces) { piece in
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
                    }
                    .padding()
                }
            }
            .navigationTitle("Pieces")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewSheet = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .accessibilityIdentifier("NewButton")
                }
            }
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
            .alert(
                "Rename piece",
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                )
            ) {
                TextField("Name", text: $renameDraft)
                Button("Save") {
                    if let target = renameTarget {
                        let repo = PieceRepository(context: modelContext)
                        try? repo.rename(piece: target, to: renameDraft)
                    }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .confirmationDialog(
                "Delete this piece?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget {
                        let repo = PieceRepository(context: modelContext)
                        try? repo.delete(piece: target)
                    }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private func duplicate(_ piece: Piece) {
        let repo = PieceRepository(context: modelContext)
        _ = try? repo.duplicate(piece: piece)
    }
}
