import SwiftUI

struct ToolBar: View {
    @Bindable var state: EditorState
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            ForEach(Tool.allCases, id: \.self) { tool in
                Button {
                    state.setTool(tool)
                } label: {
                    iconLabel(systemImage: tool.sfSymbol, title: tool.displayName)
                        .foregroundStyle(state.tool == tool ? Color.white : Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 36).overlay(Color.white.opacity(0.15))
            Button {
                state.undo()
            } label: {
                iconLabel(systemImage: "arrow.uturn.backward", title: "Undo")
                    .foregroundStyle(state.canUndo ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!state.canUndo)
            .accessibilityIdentifier("Undo")
            Button {
                state.redo()
            } label: {
                iconLabel(systemImage: "arrow.uturn.forward", title: "Redo")
                    .foregroundStyle(state.canRedo ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!state.canRedo)
            .accessibilityIdentifier("Redo")
            Divider().frame(height: 36).overlay(Color.white.opacity(0.15))
            Button {
                onClear()
            } label: {
                iconLabel(systemImage: "trash", title: "Clear")
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Clear")
        }
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
