import SwiftUI

struct ToolBar: View {
    @Bindable var state: EditorState

    var body: some View {
        HStack(spacing: 22) {
            ForEach(Tool.allCases, id: \.self) { tool in
                Button {
                    state.tool = tool
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tool.sfSymbol)
                            .font(.system(size: 20, weight: .regular))
                        Text(tool.displayName)
                            .font(.caption2)
                    }
                    .foregroundStyle(state.tool == tool ? Color.white : Color.white.opacity(0.55))
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
