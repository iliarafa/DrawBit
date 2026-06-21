import SwiftUI

struct LayersPanel: View {
    let state: EditorState
    let isPresented: Bool
    let onRenameLayer: (UUID, String) -> Void
    let onStructuralChange: () -> Void
    let onReferenceImport: (Data) -> Void
    let onReferenceRemove: () -> Void
    let onReferenceOpacityCommit: () -> Void
    let onDismiss: () -> Void

    @State private var confirmDeleteLayerID: UUID?

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
                    layerList

                    // Action bar — wired in stage 3.
                    HStack(spacing: 12) {
                        let addDisabled = state.frame.layers.count >= Frame.maxLayers || state.isPlaying
                        Button {
                            state.commitFloatingSelectionIfAny()
                            state.beginStructuralSnapshot()
                            state.frame.addLayer(name: "Layer \(state.frame.layers.count + 1)")
                            state.commitStructuralChange()
                            onStructuralChange()
                        } label: {
                            actionButton(systemImage: "plus", title: "ADD")
                                .foregroundStyle(addDisabled ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                                .hoverPop()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("LayersPanel-plus")
                        .disabled(addDisabled)

                        let dupDisabled = state.frame.layers.count >= Frame.maxLayers || state.isPlaying
                        Button {
                            state.commitFloatingSelectionIfAny()
                            state.beginStructuralSnapshot()
                            state.frame.duplicateActiveLayer()
                            state.commitStructuralChange()
                            onStructuralChange()
                        } label: {
                            actionButton(systemImage: "doc.on.doc", title: "DUPE")
                                .foregroundStyle(dupDisabled ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                                .hoverPop()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("LayersPanel-duplicate")
                        .disabled(dupDisabled)

                        let delDisabled = state.frame.layers.count <= 1 || state.isPlaying
                        Button {
                            // Commit any floating marquee FIRST so the isEmpty check sees
                            // the post-commit layer pixels — without this reorder, a
                            // layer whose content has been entirely lifted into a marquee
                            // selection reads as empty (because extractAndCut zeroes the
                            // stored buffer) and would be silently deleted along with the
                            // selection it just received back.
                            state.commitFloatingSelectionIfAny()
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
                            actionButton(systemImage: "trash", title: "DELETE")
                                .foregroundStyle(delDisabled ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                                .hoverPop()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("LayersPanel-delete")
                        .disabled(delDisabled)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .sheet(isPresented: Binding(
                        get: { confirmDeleteLayerID != nil },
                        set: { if !$0 { confirmDeleteLayerID = nil } }
                    )) {
                        ConfirmDialogSheet(
                            title: "DELETE LAYER?",
                            confirmLabel: "DELETE",
                            onCancel: { confirmDeleteLayerID = nil },
                            onConfirm: {
                                if let id = confirmDeleteLayerID {
                                    state.commitFloatingSelectionIfAny()
                                    state.beginStructuralSnapshot()
                                    state.frame.removeLayer(id: id)
                                    state.commitStructuralChange()
                                    onStructuralChange()
                                }
                                confirmDeleteLayerID = nil
                            }
                        )
                        .presentationDetents([.height(200)])
                        .presentationCornerRadius(0)
                        .presentationBackground(Color(white: 0.10))
                    }
                    Divider().overlay(Color.white.opacity(0.08))
                    ReferenceRow(
                        state: state,
                        onImport: onReferenceImport,
                        onRemove: onReferenceRemove,
                        onOpacityCommit: onReferenceOpacityCommit
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(width: 360)
                .background(Color(white: 0.10))
                .transition(.move(edge: .trailing))
            }
        }
        .animation(UITestSupport.isRunning ? nil : .easeInOut(duration: 0.18), value: isPresented)
    }

    // MARK: - Layer list

    /// `ScrollView + LazyVStack` instead of `List` — SwiftUI `List` rows
    /// intercept `.dropDestination` events at the cell level, so drops over a
    /// row never fire and the dragged row springs back. The FramesStrip uses
    /// the same pattern for its drag-to-reorder.
    private var layerList: some View {
        let count = state.frame.layers.count
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(state.frame.layers.reversed().enumerated()), id: \.element.id) { displayIndex, layer in
                    LayerRow(
                        layer: layer,
                        size: state.size,
                        isActive: layer.id == state.frame.activeLayerID,
                        onTap: {
                            state.commitFloatingSelectionIfAny()
                            state.frame.setActive(id: layer.id)
                            onStructuralChange()
                        },
                        onToggleVisible: {
                            state.commitFloatingSelectionIfAny()
                            state.beginStructuralSnapshot()
                            state.frame.setVisible(id: layer.id, to: !layer.isVisible)
                            state.commitStructuralChange()
                            onStructuralChange()
                        },
                        onToggleLocked: {
                            state.commitFloatingSelectionIfAny()
                            state.beginStructuralSnapshot()
                            state.frame.setLocked(id: layer.id, to: !layer.isLocked)
                            state.commitStructuralChange()
                            onStructuralChange()
                        },
                        isPulsing: state.lockPulseLayerID == layer.id,
                        onRename: { newName in
                            onRenameLayer(layer.id, newName)
                        },
                        displayIndex: displayIndex,
                        layerCount: count,
                        onMoveByDisplayIndex: { from, to in performMove(displayFrom: from, displayTo: to) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Toolbar-consistent button: SF Symbol over an uppercase pixel-font label.
    /// Mirrors `ToolBar.iconLabel` / `FramesStrip.stripButton` so the panel's
    /// action bar matches the rest of the editor chrome.
    private func actionButton(systemImage: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
            Text(title)
                .font(.pixel(8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    /// Drop-on-target reorder: the moved layer takes the target row's display slot.
    /// Display order is the model layers reversed, so model index = count − 1 − display index.
    private func performMove(displayFrom: Int, displayTo: Int) {
        let count = state.frame.layers.count
        guard displayFrom != displayTo,
              (0..<count).contains(displayFrom),
              (0..<count).contains(displayTo) else { return }
        let modelFrom = count - 1 - displayFrom
        let modelTo = count - 1 - displayTo
        let id = state.frame.layers[modelFrom].id

        state.commitFloatingSelectionIfAny()
        state.beginStructuralSnapshot()
        state.frame.move(id: id, toIndex: modelTo)
        state.commitStructuralChange()
        onStructuralChange()
    }
}
