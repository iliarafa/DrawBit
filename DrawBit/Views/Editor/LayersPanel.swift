import SwiftUI

struct LayersPanel: View {
    @Bindable var state: EditorState
    let isPresented: Bool
    let onRenameLayer: (UUID, String) -> Void
    let onStructuralChange: () -> Void
    let onDismiss: () -> Void

    @State private var confirmDeleteLayerID: UUID?
    @State private var editMode: EditMode = .inactive

    var body: some View {
        ZStack(alignment: .trailing) {
            if isPresented {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    HStack {
                        Text("LAYERS").font(.pixel(11)).foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                editMode = (editMode == .active) ? .inactive : .active
                            }
                        } label: {
                            Text(editMode == .active ? "DONE" : "EDIT")
                                .font(.pixel(11))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark").foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider().overlay(Color.white.opacity(0.08))

                    // Top of list = top of stack (layers stored bottom-up; reverse for display).
                    layerList

                    // Action bar — wired in stage 3.
                    HStack(spacing: 12) {
                        Button {
                            state.beginStructuralSnapshot()
                            state.frame.addLayer(name: "Layer \(state.frame.layers.count + 1)")
                            state.commitStructuralChange()
                            onStructuralChange()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(state.frame.layers.count >= 16)

                        Button {
                            state.beginStructuralSnapshot()
                            state.frame.duplicateActiveLayer()
                            state.commitStructuralChange()
                            onStructuralChange()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .disabled(state.frame.layers.count >= 16)

                        Button {
                            let active = state.frame.activeLayer
                            let isEmpty = active.pixels.allSatisfy { $0 == 0 }
                            if isEmpty {
                                state.beginStructuralSnapshot()
                                state.frame.removeLayer(id: active.id)
                                state.commitStructuralChange()
                                onStructuralChange()
                            } else {
                                confirmDeleteLayerID = active.id
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(state.frame.layers.count <= 1)

                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .confirmationDialog(
                        "Delete this layer?",
                        isPresented: Binding(
                            get: { confirmDeleteLayerID != nil },
                            set: { if !$0 { confirmDeleteLayerID = nil } }
                        )
                    ) {
                        Button("Delete", role: .destructive) {
                            if let id = confirmDeleteLayerID {
                                state.beginStructuralSnapshot()
                                state.frame.removeLayer(id: id)
                                state.commitStructuralChange()
                                onStructuralChange()
                            }
                            confirmDeleteLayerID = nil
                        }
                        Button("Cancel", role: .cancel) { confirmDeleteLayerID = nil }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(width: 360)
                .background(Color(white: 0.10))
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isPresented)
        .onChange(of: isPresented) { _, nowPresented in
            if !nowPresented {
                editMode = .inactive
            }
        }
    }

    // MARK: - Layer list

    private var layerList: some View {
        List {
            ForEach(state.frame.layers.reversed(), id: \.id) { layer in
                LayerRow(
                    layer: layer,
                    size: state.size,
                    isActive: layer.id == state.frame.activeLayerID,
                    onTap: {
                        state.frame.setActive(id: layer.id)
                        onStructuralChange()
                    },
                    onRename: { newName in
                        onRenameLayer(layer.id, newName)
                    }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .onMove(perform: editMode == .active ? performMove : nil)
        }
        .environment(\.editMode, editMode == .active ? .constant(.active) : .constant(.inactive))
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func performMove(indices: IndexSet, newOffset: Int) {
        guard let displayedFrom = indices.first else { return }
        let count = state.frame.layers.count
        let modelFrom = count - 1 - displayedFrom
        let modelTo = max(0, min(count - 1, (count - 1) - newOffset))
        guard modelFrom != modelTo else { return }
        let id = state.frame.layers[modelFrom].id

        state.beginStructuralSnapshot()
        state.frame.move(id: id, toIndex: modelTo)
        state.commitStructuralChange()
        onStructuralChange()
    }
}
