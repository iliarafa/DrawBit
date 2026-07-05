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
    /// Swipe-left-to-delete this row (in addition to the DELETE button). No-op on the last layer.
    let onDelete: () -> Void

    @State private var isEditingName = false
    @State private var draftName = ""
    /// Drives keyboard focus for the rename field so entering edit immediately shows a cursor.
    @FocusState private var nameFieldFocused: Bool
    /// Live horizontal offset while swiping left to delete; springs back if released short.
    @State private var swipeX: CGFloat = 0

    /// Fixed row height so the parent's point→slot drag math is exact (44pt controls + 12pt).
    static let rowHeight: CGFloat = 56
    /// Left-swipe distance past which release commits the delete.
    static let deleteThreshold: CGFloat = 90

    var body: some View {
        ZStack {
            // Delete zone, stationary behind the row. The opaque foreground occludes it at
            // rest; a left-swipe slides the foreground off it to reveal the trash.
            HStack(spacing: 0) {
                Spacer()
                PixelArtIcon(pattern: PixelArtIcon.layerTrash, size: 22)
                    .foregroundStyle(.white)
                    .padding(.trailing, 22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.destructive)
            .opacity(swipeX < 0 ? 1 : 0)

            rowForeground
                .offset(x: swipeX)
        }
        .frame(height: Self.rowHeight)
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
        // Swipe-left-to-delete. Runs simultaneously with reorder but is axis- and direction-locked
        // (leftward, horizontal-dominant) and never engages while a reorder is lifted or on the
        // last remaining layer, so it can't fight the vertical drag or the scroll.
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in
                    guard !isLifted, layerCount > 1 else { return }
                    if v.translation.width < 0 && abs(v.translation.width) > abs(v.translation.height) {
                        swipeX = max(v.translation.width, -140)
                    }
                }
                .onEnded { _ in
                    let commit = swipeX <= -Self.deleteThreshold
                    withAnimation(UITestSupport.isRunning ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                        swipeX = 0
                    }
                    if commit { onDelete() }
                }
        )
        .onChange(of: isLifted) { _, lifted in if lifted { swipeX = 0 } }
        // Focus the field the instant edit mode opens (runs after the field is built, so
        // focus lands on the live TextField → cursor + keyboard appear immediately).
        .onChange(of: isEditingName) { _, editing in if editing { nameFieldFocused = true } }
        // Losing focus while still editing (e.g. tapping away) commits rather than
        // silently abandoning. commitRename() clears isEditingName first, so a DONE/Return
        // commit doesn't re-enter here.
        .onChange(of: nameFieldFocused) { _, focused in if !focused && isEditingName { commitRename() } }
        .animation(UITestSupport.isRunning ? nil : .easeInOut(duration: 0.18), value: isPulsing)
        .accessibilityAction(named: "Rename") {
            draftName = layer.name
            isEditingName = true
        }
        .accessibilityAction(named: "Delete") { onDelete() }
        .accessibilityAction(named: "Move up") {
            if displayIndex > 0 { onMoveByDisplayIndex(displayIndex, displayIndex - 1) }
        }
        .accessibilityAction(named: "Move down") {
            if displayIndex < layerCount - 1 { onMoveByDisplayIndex(displayIndex, displayIndex + 1) }
        }
    }

    /// Commit the in-progress rename and leave edit mode. Shared by Return (`onSubmit`),
    /// the DONE button, and focus-loss. Setting `isEditingName = false` first makes the
    /// focus-loss handler a no-op so a single edit commits exactly once.
    private func commitRename() {
        isEditingName = false
        nameFieldFocused = false
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != layer.name {
            onRename(String(trimmed.prefix(32)))
        }
    }

    /// The visible row content that slides on a delete-swipe. Opaque base (panel color) so the
    /// delete zone behind it stays hidden until the swipe reveals it.
    private var rowForeground: some View {
        HStack(spacing: 10) {
            // Thumbnail reads as the "grip"; the whole row is the drag target (long-press to lift).
            thumbnail
            if isEditingName {
                TextField("", text: $draftName)
                    .font(.pixel(11))
                    .foregroundStyle(.white)
                    .focused($nameFieldFocused)
                    .onSubmit { commitRename() }
            } else {
                Text(layer.name)
                    .font(.pixel(11))
                    .foregroundStyle(.white)
            }
            Spacer()
            // Controls read left→right: visibility, edit-name, lock.
            Button { onToggleVisible() } label: {
                Text(layer.isVisible ? "ON" : "OFF")
                    .font(.pixel(9))
                    .foregroundStyle(.white.opacity(layer.isVisible ? 0.9 : 0.4))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .hoverPop()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("LayerRow-visibility")
            .accessibilityLabel("Visibility")
            .accessibilityValue(layer.isVisible ? "visible" : "hidden")
            // Inline edit-name control (replaces a context-menu Rename entry — long-press
            // is unreliable next to the drag gesture, and the system menu doesn't match
            // the app's pixel aesthetic). While editing it becomes an explicit DONE that
            // commits, so there's always a visible way out of the field.
            if isEditingName {
                Button { commitRename() } label: {
                    Text("DONE")
                        .font(.pixel(9))
                        .foregroundStyle(Color.toolSelected)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .hoverPop()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("LayerRow-doneEditing")
                .accessibilityLabel("Done")
            } else {
                Button {
                    draftName = layer.name
                    isEditingName = true
                } label: {
                    Text("EDIT")
                        .font(.pixel(9))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .hoverPop()
                }
                .buttonStyle(.plain)
                // Keep the "Rename" a11y label — the rename UI tests query by it, and
                // it keeps this button distinct from the removed EDIT-mode gate.
                .accessibilityLabel("Rename")
            }
            // One word, two states: dark/inactive when unlocked, red when locked.
            Button { onToggleLocked() } label: {
                Text("LOCK")
                    .font(.pixel(9))
                    .foregroundStyle(layer.isLocked ? Color.layerLocked : Color.white.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .hoverPop()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("LayerRow-lock")
            .accessibilityLabel("Lock")
            .accessibilityValue(layer.isLocked ? "locked" : "unlocked")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: Self.rowHeight)
        .background {
            // Opaque panel base occludes the delete zone; the translucent selection/lifted
            // tint rides on top.
            Color(white: 0.10)
            rowBackground
        }
    }

    /// Lifted (being dragged) reads brightest; otherwise the active row keeps its
    /// brand-cyan tint (the app accent, not a raw system blue).
    private var rowBackground: Color {
        if isLifted { return Color(white: 0.24) }
        return isActive ? Color.toolSelected.opacity(0.30) : Color.clear
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
