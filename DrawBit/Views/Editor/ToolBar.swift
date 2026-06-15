import SwiftUI

/// The editor's bottom toolbar: drawing tools, undo/redo, clear, and the active
/// color swatch — all distributed evenly across the full width (each control
/// gets an equal-width slice), with light dividers marking the groups. Tapping
/// the swatch opens the color picker; recent colors live inside the picker.
struct ToolBar: View {
    let state: EditorState
    @Binding var selectedColor: RGBA
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClear: () -> Void
    var onRequestColorPicker: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tool.allCases, id: \.self) { tool in
                Button {
                    state.setTool(tool)
                } label: {
                    iconLabel(systemImage: tool.sfSymbol, title: tool.displayName)
                        .foregroundStyle(state.tool == tool ? Color.white : Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }

            // MIRROR — stroke-modifier toggle. Lives next to the tools because
            // it changes how every tool draws.
            Button {
                state.isMirrorEnabled.toggle()
            } label: {
                iconLabel(systemImage: "arrow.left.and.right", title: "Mirror")
                    .foregroundStyle(state.isMirrorEnabled ? Color.white : Color.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Mirror")
            .accessibilityLabel("Mirror")
            .frame(maxWidth: .infinity)

            divider

            Button(action: onUndo) {
                iconLabel(systemImage: "arrow.uturn.backward", title: "Undo")
                    .foregroundStyle(state.canUndo ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!state.canUndo)
            .accessibilityIdentifier("Undo")
            .frame(maxWidth: .infinity)

            Button(action: onRedo) {
                iconLabel(systemImage: "arrow.uturn.forward", title: "Redo")
                    .foregroundStyle(state.canRedo ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!state.canRedo)
            .accessibilityIdentifier("Redo")
            .frame(maxWidth: .infinity)

            divider

            Button(action: onClear) {
                iconLabel(systemImage: "trash", title: "Clear")
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Clear")
            .frame(maxWidth: .infinity)

            divider

            Button(action: onRequestColorPicker) {
                colorSwatchLabel(color: selectedColor)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ColorSwatch")
            .accessibilityLabel("COLOR")
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Divider().frame(height: 36).overlay(Color.white.opacity(0.15))
    }

    private func iconLabel(systemImage: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
            Text(title.uppercased())
                .font(.pixel(8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    /// Mirrors `iconLabel`'s 20pt-glyph + 8pt-pixel-label shape, but renders a
    /// filled rounded square in the current color instead of an SF Symbol. The
    /// 1pt outline keeps very dark / very light fills legible against the
    /// near-black toolbar background.
    private func colorSwatchLabel(color: RGBA) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(rgba: color))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
            Text("COLOR")
                .font(.pixel(8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .frame(minWidth: 44, minHeight: 44)
    }
}
