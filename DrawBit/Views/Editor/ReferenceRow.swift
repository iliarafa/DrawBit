import SwiftUI
import PhotosUI

/// Pinned footer in the Layers panel for the tracing reference photo. NOT a real layer:
/// not in `frame.layers`, not reorderable, not deletable as a layer. Holds a thumbnail,
/// a show/hide eye, a fade slider, and add/replace/remove (system photo picker).
struct ReferenceRow: View {
    let state: EditorState
    /// Raw picked bytes — the caller processes (ReferenceImageProcessor) + persists.
    let onImport: (Data) -> Void
    let onRemove: () -> Void
    /// Called when the fade slider finishes editing, so the caller can persist.
    let onOpacityCommit: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var confirmRemove = false

    private var hasReference: Bool { state.referenceImage != nil }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                thumbnail
                Text("REFERENCE")
                    .font(.pixel(11))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if hasReference {
                    Button { state.isReferenceVisible.toggle() } label: {
                        Image(systemName: state.isReferenceVisible ? "eye" : "eye.slash")
                            .foregroundStyle(.white.opacity(state.isReferenceVisible ? 0.85 : 0.45))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("Reference-toggle")
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: hasReference ? "arrow.triangle.2.circlepath" : "photo.badge.plus")
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("Reference-pick")
                if hasReference {
                    Button(role: .destructive) { confirmRemove = true } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("Reference-remove")
                }
            }
            if hasReference {
                HStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.white.opacity(0.6))
                    Slider(
                        value: Binding(get: { state.referenceOpacity },
                                       set: { state.referenceOpacity = $0 }),
                        in: 0...1
                    ) { editing in
                        if !editing { onOpacityCommit() }
                    }
                    .accessibilityIdentifier("Reference-opacity")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(white: 0.07))
        .accessibilityIdentifier("ReferenceRow")
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    onImport(data)
                }
                pickerItem = nil
            }
        }
        .confirmationDialog("Remove reference photo?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { onRemove() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var thumbnail: some View {
        Group {
            if let img = state.referenceImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(white: 0.18))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    )
            }
        }
    }
}
