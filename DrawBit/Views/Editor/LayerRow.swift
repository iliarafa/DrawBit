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
    /// Reorder request in display order, mirroring `FrameRow.onMove`. Still used by the
    /// accessibility "Move up/down" actions as the non-drag fallback.
    let onMoveByDisplayIndex: (Int, Int) -> Void

    // Custom drag-reorder, driven by the parent `LayersPanel` (which owns the drag state so
    // sibling rows can open a gap). The row reports gesture phases up; the parent feeds back
    // this row's live vertical offset and whether it's the lifted one.
    let visualOffset: CGFloat
    let isLifted: Bool
    let onDragChanged: (Int, CGFloat) -> Void
    let onDragEnded: (Int) -> Void

    @State private var isEditingName = false
    @State private var draftName = ""

    /// Fixed row height so the parent's point→slot drag math is exact (44pt controls + 12pt).
    static let rowHeight: CGFloat = 56

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail reads as the "grip"; the whole row is the drag target (long-press to lift).
            thumbnail
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
        .frame(height: Self.rowHeight)
        .background(rowBackground)
        .overlay(
            // Lifted accent (drag) on top of the lock-pulse border — both hard-edged, no blur.
            Rectangle().stroke(isLifted ? Color.toolSelected.opacity(0.9)
                                        : Color.red.opacity(isPulsing ? 0.85 : 0),
                               lineWidth: 2)
        )
        .contentShape(Rectangle())
        // Pickup "pop": a small springy scale the instant the row is armed/lifted. Render-only,
        // so the parent's gap math (keyed on the fixed rowHeight) is undisturbed.
        .scaleEffect(isLifted ? 1.03 : 1.0)
        .animation(UITestSupport.isRunning ? nil : .spring(response: 0.22, dampingFraction: 0.6), value: isLifted)
        .offset(y: visualOffset)
        .onTapGesture { onTap() }
        // Reliable reorder: hold to lift, then drag. Long-press disambiguates from a scroll flick
        // (which moves immediately) and from a quick tap (select), so it composes with both.
        .gesture(
            LongPressGesture(minimumDuration: 0.22)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("layerList")))
                .onChanged { value in
                    // Catch the long-press-completed phase too (drag == nil ⇒ armed, not yet moved)
                    // so the pickup haptic + lifted "pop" fire the instant the row becomes grabbable.
                    if case .second(true, let drag) = value {
                        onDragChanged(displayIndex, drag?.translation.height ?? 0)
                    }
                }
                .onEnded { _ in onDragEnded(displayIndex) }
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

    /// Lifted (being dragged) reads brightest; otherwise the active row keeps its blue tint.
    private var rowBackground: Color {
        if isLifted { return Color(white: 0.24) }
        return isActive ? Color.blue.opacity(0.30) : Color.clear
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
