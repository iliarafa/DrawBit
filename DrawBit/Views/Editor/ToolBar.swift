import SwiftUI

/// The editor's bottom toolbar: drawing tools, undo/redo, clear, and the active
/// color swatch — all distributed evenly across the full width (each control
/// gets an equal-width slice), with light dividers marking the groups. Tapping
/// the swatch opens the color picker; recent colors live inside the picker.
struct ToolBar: View {
    let state: EditorState
    @Binding var selectedColor: RGBA
    var onClear: () -> Void
    var onRequestColorPicker: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tool.allCases, id: \.self) { tool in
                Button {
                    SelectionFeedback.shared.fire()
                    if state.tool == tool, tool == .pencil || tool == .eraser {
                        state.cycleBrushSize(for: tool)
                    } else {
                        state.setTool(tool)
                    }
                } label: {
                    toolLabel(tool)
                        .foregroundStyle(state.tool == tool ? Color.toolSelected : Color.white.opacity(0.55))
                        .hoverPop()
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("Tool-\(tool.rawValue)")
                .accessibilityValue(tool == .pencil || tool == .eraser ? "\(state.brushSize(for: tool))" : "")
            }

            // MIRROR — stroke-modifier toggle. Lives next to the tools because
            // it changes how every tool draws.
            Button {
                SelectionFeedback.shared.fire()
                state.isMirrorEnabled.toggle()
            } label: {
                pixelIconLabel(pattern: PixelArtIcon.mirror, title: "Mirror")
                    .foregroundStyle(state.isMirrorEnabled ? Color.toolSelected : Color.white.opacity(0.55))
                    .hoverPop()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Mirror")
            .accessibilityLabel("Mirror")
            .frame(maxWidth: .infinity)

            divider

            Button(action: onClear) {
                pixelIconLabel(pattern: PixelArtIcon.clear, title: "Clear")
                    .foregroundStyle(Color.white.opacity(0.85))
                    .hoverPop()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Clear")
            .frame(maxWidth: .infinity)

            divider

            Button(action: onRequestColorPicker) {
                colorSwatchLabel(color: selectedColor)
                    .hoverPop()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ColorSwatch")
            .accessibilityLabel("COLOR")
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .onAppear { SelectionFeedback.shared.prepare() }
    }

    private var divider: some View {
        Divider().frame(height: 36).overlay(Color.white.opacity(0.15))
    }

    /// A pixel-art tool glyph over an 8pt pixel label. The 11×11 `PixelArtIcon` renders at 22pt
    /// (cell = 2pt, perfectly crisp) centered in a fixed 24×24 box — the *same* box `nibLabel` and
    /// the color swatch use. That shared icon-box height is what pins every tool's label to a common
    /// baseline. Inherits the foreground color (teal when selected/active, dim white otherwise).
    private func pixelIconLabel(pattern: [String], title: String) -> some View {
        VStack(spacing: 8) {
            PixelArtIcon(pattern: pattern, size: 22)
                .frame(width: 24, height: 24)
            Text(title.uppercased())
                .font(.pixel(8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    /// Pencil/eraser show scheme-C nib glyphs; every other tool shows its pixel-art glyph.
    @ViewBuilder
    private func toolLabel(_ tool: Tool) -> some View {
        switch tool {
        case .pencil, .eraser:
            nibLabel(filled: tool == .pencil, size: state.brushSize(for: tool), title: tool.displayName)
        case .fill:
            pixelIconLabel(pattern: PixelArtIcon.fillDroplet, title: tool.displayName)
        case .colorSwap:
            pixelIconLabel(pattern: PixelArtIcon.swapArrows, title: tool.displayName)
        case .eyedropper:
            pixelIconLabel(pattern: PixelArtIcon.eyedropper, title: tool.displayName)
        case .marquee:
            pixelIconLabel(pattern: PixelArtIcon.selectMarquee, title: tool.displayName)
        }
    }

    /// Scheme-C glyph: the tool's icon *is* the square it paints — pencil filled, eraser hollow.
    /// The on-screen side maps size 1...4 to a comfortable point range so size 1 still reads as a
    /// deliberate square. Mirrors `pixelIconLabel`'s 24-pt icon-box + 8-pt-pixel-label shape, and
    /// inherits the foreground colour (teal when selected, dim white otherwise).
    private func nibLabel(filled: Bool, size: Int, title: String) -> some View {
        let side = nibGlyphSide(for: size)
        return VStack(spacing: 8) {
            ZStack {
                if filled {
                    Rectangle().frame(width: side, height: side)
                } else {
                    Rectangle().stroke(lineWidth: 1.5).frame(width: side, height: side)
                }
            }
            .frame(width: 24, height: 24)
            Text(title.uppercased())
                .font(.pixel(8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    /// Nib size 1...4 → glyph side in points.
    private func nibGlyphSide(for size: Int) -> CGFloat {
        let sides: [CGFloat] = [8, 12, 16, 20]
        return sides[min(max(size, 1), 4) - 1]
    }

    /// Mirrors `pixelIconLabel`'s 24-pt icon-box + 8pt-pixel-label shape, but renders a filled
    /// square in the current color (hard pixel corners) instead of a glyph. The 1pt outline keeps
    /// very dark / very light fills legible against the near-black toolbar background.
    private func colorSwatchLabel(color: RGBA) -> some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color(rgba: color))
                .frame(width: 22, height: 22)
                .overlay(
                    Rectangle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .frame(width: 24, height: 24)
            Text("COLOR")
                .font(.pixel(8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .frame(minWidth: 44, minHeight: 44)
    }
}

/// Pixel-art glyphs for the toolbar tools, in the app's shared 11×11 `#`/`.` style. MIRROR and CLEAR
/// reuse the exact grids already drawn elsewhere (the selection bar's flip-horizontal arrow and the
/// layers/selection trash can) — the codebase intentionally duplicates these small string arrays per
/// file rather than sharing a private glyph enum across files.
private extension PixelArtIcon {
    /// FILL — a pixel droplet (teardrop). Carries the old `drop.fill` metaphor into the grid style.
    static let fillDroplet: [String] = [
        ".....#.....",
        "....###....",
        "....###....",
        "...#####...",
        "...#####...",
        "..#######..",
        "..#######..",
        "..#######..",
        "...#####...",
        "....###....",
        "...........",
    ]

    /// SWAP — two offset exchange arrows (top points right, bottom points left).
    static let swapArrows: [String] = [
        "...........",
        "...........",
        ".......#...",
        ".########..",
        ".......#...",
        "...........",
        "...#.......",
        "..########.",
        "...#.......",
        "...........",
        "...........",
    ]

    /// PICK — a diagonal eyedropper: fat squeeze-bulb top-right, thin nib to the bottom-left tip.
    static let eyedropper: [String] = [
        ".......###.",
        ".......###.",
        "......###..",
        ".....###...",
        "....##.....",
        "...##......",
        "..##.......",
        ".##........",
        ".#.........",
        "#..........",
        "...........",
    ]

    /// SELECT — a dotted marquee rectangle (marching ants). Carries the old `rectangle.dashed` look.
    static let selectMarquee: [String] = [
        "...........",
        ".#.#.#.#.#.",
        "...........",
        ".#.......#.",
        "...........",
        ".#.......#.",
        "...........",
        ".#.......#.",
        "...........",
        ".#.#.#.#.#.",
        "...........",
    ]

    /// MIRROR — the double-headed horizontal arrow (←→); the selection bar's `flipH`, same metaphor
    /// as the old `arrow.left.and.right`.
    static let mirror: [String] = [
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

    /// CLEAR — the trash can (lid + slats); the layers/selection `trash` glyph.
    static let clear: [String] = [
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
