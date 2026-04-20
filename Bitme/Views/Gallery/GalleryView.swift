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
            ScrollView {
                if pieces.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text("NO PIECES YET")
                            .font(.pixel(16))
                            .foregroundStyle(.primary)
                        Text("Tap + New to create your first canvas.")
                            .font(.pixel(11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("BITME")
                        .font(.pixel(20))
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onHome()
                    } label: {
                        Image(systemName: "house.fill")
                    }
                    .accessibilityIdentifier("HomeButton")
                }
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
