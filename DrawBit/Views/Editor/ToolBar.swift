import SwiftUI

/// The editor's bottom toolbar: drawing tools, undo/redo, clear, and the recent
/// colors — all distributed evenly across the full width (each control gets an
/// equal-width slice), with light dividers marking the groups.
struct ToolBar: View {
    let state: EditorState
    @Binding var selectedColor: RGBA
    @Binding var recentHex: [String]
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

            ForEach(recentHex.prefix(RecentColors.maxSwatches), id: \.self) { hex in
                SwatchButton(
                    hex: hex,
                    isSelected: RGBA(hex: hex) == selectedColor,
                    action: {
                        if RGBA(hex: hex) == selectedColor {
                            onRequestColorPicker()
                        } else if let c = RGBA(hex: hex) {
                            selectedColor = c
                        }
                    }
                )
                .frame(maxWidth: .infinity)
            }

            Button(action: onRequestColorPicker) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.25), style: .init(lineWidth: 1, dash: [2, 2]))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("AddColor")
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
}
