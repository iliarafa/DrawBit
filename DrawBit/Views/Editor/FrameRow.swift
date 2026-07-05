import SwiftUI

struct FrameRow: View {
    let frame: Frame
    let size: CanvasSize
    let index: Int
    let isActive: Bool
    let frameCount: Int
    let onTap: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    /// Index-based reorder (from, to).
    let onMove: (Int, Int) -> Void

    /// Thumbnail side. Also read by `FramesStrip` to snap its scroll viewport to whole frames.
    static let edge: CGFloat = 72

    var body: some View {
        thumbnail
            .frame(width: Self.edge, height: Self.edge)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isActive ? Color.white : Color.white.opacity(0.15),
                            lineWidth: isActive ? 2 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .draggable("\(index)") {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: Self.edge, height: Self.edge)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let s = items.first, let from = Int(s), from != index else { return false }
                onMove(from, index)
                return true
            }
            .modifier(FrameRowAccessibility(
                frame: frame, index: index, frameCount: frameCount,
                onDuplicate: onDuplicate, onDelete: onDelete, onMove: onMove
            ))
            // The action glyphs are overlaid *after* the accessibility collapse so each
            // stays its own element — both VoiceOver-reachable and XCUITest-queryable.
            // (A themed long-press popup can't coexist with `.draggable` reorder, so
            // Duplicate/Delete are direct on-frame affordances instead of a menu.)
            .overlay(actionBadges)
            .hoverPop()
    }

    // MARK: - Layers

    private var thumbnail: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.25))

            if let cg = FrameThumbnailRenderer.renderCGImage(frame: frame, size: size, targetEdge: Int(Self.edge)) {
                Image(uiImage: UIImage(cgImage: cg))
                    .interpolation(.none)
                    .antialiased(false)
                    .resizable()
            }

            numberBadge
        }
    }

    private var numberBadge: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("\(index + 1)")
                    .font(.pixel(8))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(isActive ? Color.white : Color.black.opacity(0.7))
                    .foregroundStyle(isActive ? Color.black : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(2)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    /// On-frame action glyphs, shown only on the selected frame (the number badge owns
    /// top-left, these sit top-right). Duplicate is always available; Delete hides on
    /// the last remaining frame. Monochrome to match the strip; the destructive confirm
    /// for Delete lives upstream.
    @ViewBuilder
    private var actionBadges: some View {
        if isActive {
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    Spacer(minLength: 0)
                    // NB: identifiers must NOT start with "FrameRow." — the animation UI
                    // tests enumerate frame rows via `BEGINSWITH 'FrameRow.'`, and a
                    // collision pollutes that list.
                    badgeButton(systemImage: "plus.square.on.square",
                                label: "Duplicate frame",
                                identifier: "FrameDuplicateButton",
                                action: onDuplicate)
                    if frameCount > 1 {
                        badgeButton(systemImage: "xmark",
                                    label: "Delete frame",
                                    identifier: "FrameDeleteButton",
                                    action: onDelete)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func badgeButton(systemImage: String,
                             label: String,
                             identifier: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                // Pad the hit target out beyond the visible chip.
                .padding(.vertical, 4)
                .padding(.horizontal, 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }
}

/// Pulled into its own modifier so `FrameRow.body` stays small enough for the
/// SwiftUI type-checker. Drag-to-reorder has no VoiceOver affordance, so the
/// move actions are exposed here alongside the menu actions.
private struct FrameRowAccessibility: ViewModifier {
    let frame: Frame
    let index: Int
    let frameCount: Int
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onMove: (Int, Int) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("FrameRow.\(frame.id.uuidString)")
            .accessibilityLabel("Frame \(index + 1)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Duplicate") { onDuplicate() }
            .accessibilityAction(named: "Delete") { if frameCount > 1 { onDelete() } }
            .accessibilityAction(named: "Move left") { if index > 0 { onMove(index, index - 1) } }
            .accessibilityAction(named: "Move right") { if index < frameCount - 1 { onMove(index, index + 1) } }
    }
}
