import SwiftUI

/// Contextual actions for a floating selection — flip, rotate, duplicate, delete.
///
/// Shares the `resetViewChip` visual language so every transient affordance over the canvas reads
/// as one family: a sharp-cornered rectangle, `Color(white: 0.16)` fill, a 1pt cyan
/// (`Color.toolSelected`) border, white pixel-font content. The buttons themselves use the
/// `ToolBar` blueprint (icon over a `.pixel(8)` caps label, `.hoverPop()`, 44pt hit target).
///
/// Purely presentational — every action is injected as a closure, so feedback, persistence, and
/// the rotate-refusal check all live in the owner (`EditorView`).
struct SelectionActionBar: View {
    var onFlipHorizontal: () -> Void = {}
    var onFlipVertical: () -> Void = {}
    var onRotate: () -> Void = {}
    var onDuplicate: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(spacing: 2) {
            button("arrow.left.and.right", "FLIP H", onFlipHorizontal)
            button("arrow.up.and.down",    "FLIP V", onFlipVertical)
            button("rotate.right",         "ROTATE", onRotate)
            button("square.on.square",     "COPY",   onDuplicate)
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 30)
            button("trash",                "DELETE", onDelete)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(white: 0.16))
        .overlay(Rectangle().stroke(Color.toolSelected, lineWidth: 1))
        .contentShape(Rectangle())   // absorb taps so they don't fall through to the canvas
    }

    // The `title` doubles as the button's accessibility label (the canvas's own
    // `.accessibilityIdentifier("Canvas")` propagates onto these descendants and would clobber a
    // custom identifier, so tests query these by label).
    private func button(_ systemImage: String, _ title: String,
                        _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 3) {
                Image(systemName: systemImage).font(.system(size: 14, weight: .regular))
                Text(title).font(.pixel(8)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(.white)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverPop()
    }
}
