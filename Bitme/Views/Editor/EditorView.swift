import SwiftUI
import SwiftData

struct EditorView: View {
    let piece: Piece
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var state: EditorState

    init(piece: Piece) {
        self.piece = piece
        self._state = State(initialValue: EditorState(piece: piece))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ZStack {
                Color(white: 0.10)
                    .ignoresSafeArea(edges: [.leading, .trailing])
                Text("Canvas coming in Phase 7")
                    .foregroundStyle(.white.opacity(0.4))
            }
            Divider()
            Rectangle()
                .fill(Color(white: 0.09))
                .frame(height: 88)
                .overlay(Text("Tools + colors (Phase 8)").foregroundStyle(.white.opacity(0.5)))
        }
        .background(Color(white: 0.10).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label("Gallery", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            Spacer()
            Text(piece.size.displayName)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            HStack(spacing: 18) {
                Button {
                    state.undo()
                } label: { Image(systemName: "arrow.left") }
                    .disabled(!state.canUndo)
                Button {
                    state.redo()
                } label: { Image(systemName: "arrow.right") }
                    .disabled(!state.canRedo)
                Button("Share") {
                    // wired in Phase 9
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
