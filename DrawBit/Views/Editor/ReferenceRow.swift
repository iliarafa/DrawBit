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

    /// Drive the controls off the stored bytes, not the decoded image, so a reference
    /// that somehow failed to decode can still be removed (the thumbnail falls back to
    /// its placeholder). In practice the two are always in lock-step via `setReference`.
    private var hasReference: Bool { state.referenceImageData != nil }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                thumbnail
                // "TRACE" in the app accent marks this slab as the special backdrop —
                // the sheet that sits behind every layer, not a layer itself.
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRACE")
                        .font(.pixel(11))
                        .foregroundStyle(Color.toolSelected)
                    Text("BEHIND ALL LAYERS")
                        .font(.pixel(7))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                if hasReference {
                    Button { state.isReferenceVisible.toggle() } label: {
                        Text(state.isReferenceVisible ? "ON" : "OFF")
                            .font(.pixel(9))
                            .foregroundStyle(.white.opacity(state.isReferenceVisible ? 0.9 : 0.4))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .hoverPop()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("Reference-toggle")
                    .accessibilityLabel("Reference visibility")
                    .accessibilityValue(state.isReferenceVisible ? "visible" : "hidden")
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    // Empty → a plus ("add one"); set → the photo glyph ("choose another").
                    PixelArtIcon(pattern: hasReference ? PixelArtIcon.refPhoto : PixelArtIcon.layerAdd, size: 20)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .hoverPop()
                }
                // PhotosPicker doesn't expose its own standalone accessibility element to
                // XCUITest unless we force one: setting only `.accessibilityIdentifier` lets
                // it inherit the parent VStack's identifier. Pairing an explicit label +
                // `.isButton` trait promotes it to a distinct element, after which the
                // identifier ("Reference-pick", used by ReferencePhotoUITests) resolves.
                // The label stays human-readable for VoiceOver.
                .accessibilityLabel(hasReference ? "Replace reference photo" : "Add reference photo")
                .accessibilityIdentifier("Reference-pick")
                .accessibilityAddTraits(.isButton)
                if hasReference {
                    Button(role: .destructive) { confirmRemove = true } label: {
                        PixelArtIcon(pattern: PixelArtIcon.layerTrash, size: 20)
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .hoverPop()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("Reference-remove")
                }
            }
            if hasReference {
                HStack(spacing: 8) {
                    PixelArtIcon(pattern: PixelArtIcon.refFade, size: 16)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20, height: 20)
                    Slider(
                        value: Binding(get: { state.referenceOpacity },
                                       set: { state.referenceOpacity = $0 }),
                        in: 0...1
                    ) { editing in
                        if !editing { onOpacityCommit() }
                    }
                    .tint(Color.toolSelected)
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
        .sheet(isPresented: $confirmRemove) {
            ConfirmDialogSheet(
                title: "REMOVE REFERENCE?",
                confirmLabel: "REMOVE",
                onCancel: { confirmRemove = false },
                onConfirm: {
                    confirmRemove = false
                    onRemove()
                }
            )
            .presentationDetents([.height(200)])
            .presentationCornerRadius(0)
            .presentationBackground(Color(white: 0.10))
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
                        PixelArtIcon(pattern: PixelArtIcon.refPhoto, size: 18)
                            .foregroundStyle(.white.opacity(0.4))
                    )
            }
        }
    }
}
