import SwiftUI

struct LayerRow: View {
    let layer: Layer
    let size: CanvasSize
    let isActive: Bool
    let onTap: () -> Void
    let onToggleVisible: () -> Void
    let onToggleLocked: () -> Void
    let isPulsing: Bool
    let onRename: (String) -> Void
    /// Position in the reversed (top-of-stack-first) display order.
    let displayIndex: Int
    let layerCount: Int
    /// Reorder request in display order, mirroring `FrameRow.onMove`.
    let onMoveByDisplayIndex: (Int, Int) -> Void

    @State private var isEditingName = false
    @State private var draftName = ""

    private static let dragRowHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail is the drag handle — a clear visual "grip" without
            // making every tap on the row arm a drag.
            thumbnail
                .contentShape(Rectangle())
                .draggable("\(displayIndex)") {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 200, height: Self.dragRowHeight)
                }
            if isEditingName {
                TextField("", text: $draftName)
                    .font(.pixel(11))
                    .foregroundStyle(.white)
                    .onSubmit {
                        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != layer.name {
                            onRename(String(trimmed.prefix(32)))
                        }
                        isEditingName = false
                    }
            } else {
                Text(layer.name)
                    .font(.pixel(11))
                    .foregroundStyle(.white)
            }
            Spacer()
            // Inline pencil button replaces a context-menu Rename entry —
            // long-press is unreliable next to `.draggable`, and the system
            // context menu chrome doesn't match the app's pixel-font aesthetic.
            if !isEditingName {
                Button {
                    draftName = layer.name
                    isEditingName = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .hoverPop()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rename")
            }
            Button { onToggleVisible() } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(.white.opacity(layer.isVisible ? 0.85 : 0.45))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .hoverPop()
            }
            .buttonStyle(.plain)
            Button { onToggleLocked() } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(.white.opacity(layer.isLocked ? 0.85 : 0.45))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .hoverPop()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.blue.opacity(0.30) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        // Drop target is the entire row so users don't have to land precisely
        // on the 32-pt thumbnail to complete a reorder.
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let from = Int(s), from != displayIndex else { return false }
            onMoveByDisplayIndex(from, displayIndex)
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.red.opacity(isPulsing ? 0.85 : 0), lineWidth: 2)
        )
        .animation(UITestSupport.isRunning ? nil : .easeInOut(duration: 0.18), value: isPulsing)
        .accessibilityAction(named: "Rename") {
            draftName = layer.name
            isEditingName = true
        }
        .accessibilityAction(named: "Move up") {
            if displayIndex > 0 { onMoveByDisplayIndex(displayIndex, displayIndex - 1) }
        }
        .accessibilityAction(named: "Move down") {
            if displayIndex < layerCount - 1 { onMoveByDisplayIndex(displayIndex, displayIndex + 1) }
        }
    }

    private var thumbnail: some View {
        Group {
            if let img = LayerThumbnailRenderer.renderCGImage(layer: layer, size: size, targetEdge: 64) {
                Image(decorative: img, scale: 1.0, orientation: .up)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .frame(width: 32, height: 32)
                    .background(checkerboard)
            } else {
                Rectangle().fill(.gray).frame(width: 32, height: 32)
            }
        }
    }

    private var checkerboard: some View {
        Canvas { ctx, sz in
            let s: CGFloat = 4
            for y in stride(from: 0, to: sz.height, by: s) {
                for x in stride(from: 0, to: sz.width, by: s) {
                    let isDark = (Int(x / s) + Int(y / s)) % 2 == 0
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(isDark ? .gray.opacity(0.4) : .gray.opacity(0.2)))
                }
            }
        }
        .frame(width: 32, height: 32)
    }
}
