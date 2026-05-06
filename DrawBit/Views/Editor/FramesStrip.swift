import SwiftUI

struct FramesStrip: View {
    @Bindable var state: EditorState
    let onAddFrame: () -> Void
    let onDuplicateFrame: () -> Void
    let onDeleteFrame: () -> Void
    /// Reserved for Stage 4+ drag-to-reorder. Currently unused — the parameter is here
    /// so the EditorView wiring doesn't need to change when reorder lands.
    let onReorderFrame: (Int, Int) -> Void
    let onRenameFrame: (UUID, String) -> Void
    let onActivateFrame: (Int) -> Void

    @State private var isEditMode: Bool = false
    @State private var renamingFrameID: UUID?
    @State private var renameText: String = ""

    var body: some View {
        HStack(spacing: 8) {
            // Stage 4 will add play/pause and FPS picker controls here on the left side.

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.frames, id: \.id) { frame in
                        if let renamingID = renamingFrameID, renamingID == frame.id {
                            TextField("Frame name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .onSubmit { commitRename() }
                                .submitLabel(.done)
                        } else {
                            FrameRow(
                                frame: frame,
                                size: state.size,
                                isActive: frame.id == state.frames[state.activeFrameIndex].id,
                                isEditing: isEditMode,
                                onTap: {
                                    if renamingFrameID != nil && renamingFrameID != frame.id {
                                        commitRename()
                                    }
                                    if let idx = state.frames.firstIndex(where: { $0.id == frame.id }) {
                                        onActivateFrame(idx)
                                    }
                                },
                                onLongPressRename: {
                                    renamingFrameID = frame.id
                                    renameText = frame.name
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 6) {
                Button(action: onAddFrame) {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .accessibilityIdentifier("FramesStrip.add")
                .disabled(state.frames.count >= FrameSequence.frameCap)

                if isEditMode {
                    Button(action: onDuplicateFrame) {
                        Image(systemName: "plus.square.on.square")
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityIdentifier("FramesStrip.duplicate")
                    .disabled(state.frames.count >= FrameSequence.frameCap)

                    Button(action: onDeleteFrame) {
                        Image(systemName: "trash")
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityIdentifier("FramesStrip.delete")
                    .disabled(state.frames.count <= 1)
                }

                Button(isEditMode ? "DONE" : "EDIT") {
                    if renamingFrameID != nil {
                        commitRename()
                    }
                    isEditMode.toggle()
                }
                .font(.caption2.bold())
                .accessibilityIdentifier("FramesStrip.editToggle")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .background(Color.black.opacity(0.4))
    }

    private func commitRename() {
        guard let id = renamingFrameID else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           let current = state.frames.first(where: { $0.id == id }),
           trimmed != current.name {
            onRenameFrame(id, trimmed)
        }
        renamingFrameID = nil
        renameText = ""
    }
}
