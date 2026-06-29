import SwiftUI

/// Contextual actions for a floating selection — flip, rotate, duplicate, delete.
///
/// Designed to *float*: no border, and a fill that matches the app background (`Color(white: 0.10)`),
/// so against the empty band below the canvas only the white buttons read — not a boxed menu. Icons
/// are hand-drawn `PixelArtIcon` glyphs (the same renderer the undo/redo top bar uses) so they match
/// the pixel-art aesthetic — no SF Symbols.
///
/// Purely presentational — every action is injected as a closure, so feedback, persistence, and
/// the rotate-refusal check all live in the owner (`EditorView`). Buttons size to their content
/// (icon over a `.pixel(8)` caps label), so labels never collide.
struct SelectionActionBar: View {
    var onFlipHorizontal: () -> Void = {}
    var onFlipVertical: () -> Void = {}
    var onRotate: () -> Void = {}
    var onDuplicate: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            button(Glyph.flipH, "FLIP H", onFlipHorizontal)
            button(Glyph.flipV, "FLIP V", onFlipVertical)
            button(Glyph.rotate, "ROTATE", onRotate)
            button(Glyph.copy, "COPY", onDuplicate)
            Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 32)
            button(Glyph.delete, "DELETE", onDelete)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.10))   // the app background → buttons float, not boxed
        .contentShape(Rectangle())        // absorb taps so they don't fall through to the canvas
    }

    // The `title` doubles as each button's accessibility label (the canvas's own
    // `.accessibilityIdentifier("Canvas")` propagates onto these descendants and would clobber a
    // custom identifier, so UI tests query these by label).
    private func button(_ glyph: [String], _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 5) {
                PixelArtIcon(pattern: glyph, size: 19)
                Text(title).font(.pixel(8)).fixedSize()
            }
            .foregroundStyle(.white)
            .frame(minHeight: 44)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverPop()
    }
}

/// 11×11 pixel-art glyphs for the selection actions, in the `PixelArtIcon` `#`/`.` format.
private enum Glyph {
    /// Double-headed horizontal arrow (mirror left↔right).
    static let flipH = [
        "...........",
        "...........",
        "...........",
        "...#...#...",
        "..#.....#..",
        ".#########.",
        "..#.....#..",
        "...#...#...",
        "...........",
        "...........",
        "...........",
    ]
    /// Double-headed vertical arrow (mirror top↔bottom).
    static let flipV = [
        "...........",
        ".....#.....",
        "....###....",
        "...#.#.#...",
        ".....#.....",
        ".....#.....",
        ".....#.....",
        "...#.#.#...",
        "....###....",
        ".....#.....",
        "...........",
    ]
    /// A ring with an arrowhead — rotate.
    static let rotate = [
        "...........",
        "...####....",
        "..#....#...",
        ".#......#..",
        ".#.......#.",
        ".#......###",
        ".#.......#.",
        "..#....#...",
        "...####....",
        "...........",
        "...........",
    ]
    /// Two overlapping squares — duplicate / copy.
    static let copy = [
        "...........",
        "....######.",
        "....#....#.",
        "....#....#.",
        ".######..#.",
        ".#..#.#..#.",
        ".#..######.",
        ".#....#....",
        ".#....#....",
        ".######....",
        "...........",
    ]
    /// A trash can — delete.
    static let delete = [
        "...........",
        "....###....",
        "..#######..",
        "..#.#.#.#..",
        "..#.#.#.#..",
        "..#.#.#.#..",
        "..#.#.#.#..",
        "..#.#.#.#..",
        "..#.#.#.#..",
        "..#######..",
        "...........",
    ]
}
