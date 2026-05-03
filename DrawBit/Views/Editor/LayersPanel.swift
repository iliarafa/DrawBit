import SwiftUI

struct LayersPanel: View {
    @Bindable var state: EditorState
    let isPresented: Bool
    let onRenameLayer: (UUID, String) -> Void
    let onDismiss: () -> Void

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
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark").foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider().overlay(Color.white.opacity(0.08))

                    // Top of list = top of stack (layers stored bottom-up; reverse for display).
                    List {
                        ForEach(state.frame.layers.reversed(), id: \.id) { layer in
                            LayerRow(
                                layer: layer,
                                size: state.size,
                                isActive: layer.id == state.frame.activeLayerID,
                                onTap: { state.frame.setActive(id: layer.id) },
                                onRename: { newName in
                                    onRenameLayer(layer.id, newName)
                                }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)

                    // Action bar — disabled placeholders for stage 2.
                    HStack(spacing: 12) {
                        Image(systemName: "plus").opacity(0.3)
                        Image(systemName: "doc.on.doc").opacity(0.3)
                        Image(systemName: "trash").opacity(0.3)
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: .infinity)
                .frame(width: 360)
                .background(Color(white: 0.10))
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isPresented)
    }
}
