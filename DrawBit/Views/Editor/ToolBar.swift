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
                iconLabel(systemImage: "arrow.left.and.right", title: "Mirror")
                    .foregroundStyle(state.isMirrorEnabled ? Color.toolSelected : Color.white.opacity(0.55))
                    .hoverPop()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Mirror")
            .accessibilityLabel("Mirror")
            .frame(maxWidth: .infinity)

            divider

            Button(action: onClear) {
                iconLabel(systemImage: "trash", title: "Clear")
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

    private func iconLabel(systemImage: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
            Text(title.uppercased())
                .font(.pixel(8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    /// Pencil/eraser show scheme-C nib glyphs; every other tool keeps its SF Symbol.
    @ViewBuilder
    private func toolLabel(_ tool: Tool) -> some View {
        if tool == .pencil || tool == .eraser {
            nibLabel(filled: tool == .pencil, size: state.brushSize(for: tool), title: tool.displayName)
        } else {
            iconLabel(systemImage: tool.sfSymbol, title: tool.displayName)
        }
    }

    /// Scheme-C glyph: the tool's icon *is* the square it paints — pencil filled, eraser hollow.
    /// The on-screen side maps size 1...4 to a comfortable point range so size 1 still reads as a
    /// deliberate square. Mirrors `iconLabel`'s 24-pt-glyph + 8-pt-pixel-label shape, and inherits
    /// the foreground colour (teal when selected, dim white otherwise).
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

    /// Mirrors `iconLabel`'s 20pt-glyph + 8pt-pixel-label shape, but renders a
    /// filled rounded square in the current color instead of an SF Symbol. The
    /// 1pt outline keeps very dark / very light fills legible against the
    /// near-black toolbar background.
    private func colorSwatchLabel(color: RGBA) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(rgba: color))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
            Text("COLOR")
                .font(.pixel(8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .frame(minWidth: 44, minHeight: 44)
    }
}
