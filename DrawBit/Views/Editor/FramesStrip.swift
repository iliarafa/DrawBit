import SwiftUI

struct FramesStrip: View {
    let state: EditorState
    let onAddFrame: () -> Void
    /// onDuplicateFrame / onDeleteFrame are invoked from FrameRow's per-frame
    /// context menu (wired up in FrameRow), not from the strip's own chrome.
    let onDuplicateFrame: () -> Void
    /// Index-based reorder (from, to) used by FrameRow drag-and-drop.
    let onReorderFrame: (Int, Int) -> Void
    let onActivateFrame: (Int) -> Void
    let onTogglePlay: () -> Void
    let onDeleteFrame: () -> Void

    /// Inter-frame gap and the frames-lane content inset — reused by the whole-frame snapping math.
    private static let frameSpacing: CGFloat = 16
    private static let frameInset: CGFloat = 4

    var body: some View {
        HStack(spacing: 18) {
            // Transport group
            HStack(spacing: 16) {
                Button(action: onTogglePlay) {
                    pixelStripButton(pattern: state.isPlaying ? PixelArtIcon.pause : PixelArtIcon.playTriangle,
                                     title: state.isPlaying ? "PAUSE" : "PLAY")
                        .hoverPop()
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.frames.count <= 1 ? Color.white.opacity(0.25) : Color.white)
                .disabled(state.frames.count <= 1)
                .accessibilityIdentifier("FramesStrip.playPause")
                .accessibilityLabel(state.isPlaying ? "Pause animation" : "Play animation")

                // Tap to cycle the playback speed — the same tap-to-cycle idiom as the brush nib.
                // Only the label under the gauge changes; nothing opens.
                Button {
                    SelectionFeedback.shared.fire()
                    state.cycleFPS()
                } label: {
                    // Fixed-width (2-digit) so the label — and the button — never changes width as
                    // the speed cycles; otherwise ONION and the frames lane jitter sideways.
                    pixelStripButton(pattern: PixelArtIcon.gauge, title: String(format: "%02d FPS", state.fps))
                        .hoverPop()
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.isPlaying ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                .disabled(state.isPlaying)
                .accessibilityIdentifier("FramesStrip.fps")
                .accessibilityLabel("Playback speed")
                .accessibilityValue("\(state.fps) frames per second")
                .accessibilityHint("Tap to change the playback speed")

                Button(action: { state.isOnionSkinEnabled.toggle() }) {
                    pixelStripButton(pattern: PixelArtIcon.onion, title: "ONION")
                        .hoverPop()
                }
                .buttonStyle(.plain)
                .foregroundStyle(onionColor)
                .disabled(state.activeFrameIndex == 0 || state.isPlaying)
                .accessibilityIdentifier("FramesStrip.onionSkin")
                .accessibilityLabel(state.isOnionSkinEnabled ? "Onion skin on" : "Onion skin off")
                .accessibilityHint("Shows a faded preview of the previous frame behind the current one")
            }

            divider

            // Frames. The scroll viewport is snapped to a whole number of frames so none is ever
            // shown half-cropped at rest, and it auto-scrolls to keep the active frame fully in view.
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Self.frameSpacing) {
                            ForEach(Array(state.frames.enumerated()), id: \.element.id) { index, frame in
                                FrameRow(
                                    frame: frame,
                                    size: state.size,
                                    index: index,
                                    isActive: frame.id == state.frames[state.activeFrameIndex].id,
                                    frameCount: state.frames.count,
                                    onTap: {
                                        if let idx = state.frames.firstIndex(where: { $0.id == frame.id }) {
                                            onActivateFrame(idx)
                                        }
                                    },
                                    onDuplicate: {
                                        if let idx = state.frames.firstIndex(where: { $0.id == frame.id }) {
                                            onActivateFrame(idx)
                                        }
                                        onDuplicateFrame()
                                    },
                                    onDelete: {
                                        if let idx = state.frames.firstIndex(where: { $0.id == frame.id }) {
                                            onActivateFrame(idx)
                                        }
                                        onDeleteFrame()
                                    },
                                    onMove: { from, to in onReorderFrame(from, to) }
                                )
                                .id(frame.id)
                            }
                        }
                        .padding(.horizontal, Self.frameInset)
                        .frame(height: geo.size.height)
                    }
                    .frame(width: snappedLaneWidth(available: geo.size.width, count: state.frames.count),
                           height: geo.size.height, alignment: .leading)
                    .disabled(state.isPlaying)
                    .onAppear { DispatchQueue.main.async { scrollToActiveFrame(proxy) } }
                    .onChange(of: state.activeFrameIndex) { scrollToActiveFrame(proxy) }
                    .onChange(of: state.frames.count) { scrollToActiveFrame(proxy) }
                }
            }

            divider

            // Actions
            Button(action: onAddFrame) {
                pixelStripButton(pattern: PixelArtIcon.addPlus, title: "ADD")
                    .hoverPop()
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.frames.count >= FrameSequence.frameCap || state.isPlaying
                             ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
            .disabled(state.frames.count >= FrameSequence.frameCap || state.isPlaying)
            .accessibilityIdentifier("FramesStrip.add")
            .accessibilityLabel("Add blank frame")
        }
        .padding(.horizontal, 52)
        .frame(height: 88)
        // No background of its own: the strip inherits the editor's Color(white: 0.10),
        // identical to the canvas and tool strip, and has no dividers above or below — so
        // it blends in as one continuous surface.
    }

    private var divider: some View {
        Divider().frame(height: 52).overlay(Color.white.opacity(0.15))
    }

    private var onionColor: Color {
        if state.activeFrameIndex == 0 || state.isPlaying { return Color.white.opacity(0.25) }
        return state.isOnionSkinEnabled ? Color.white : Color.white.opacity(0.55)
    }

    /// Width that shows the largest *whole* number of frames fitting `available` (so the trailing
    /// edge always lands between frames, never mid-frame), capped at the real content width so a
    /// few frames don't stretch the lane. The leftover stays as trailing space, keeping ADD aligned.
    private func snappedLaneWidth(available: CGFloat, count: Int) -> CGFloat {
        guard available > 0, count > 0 else { return max(available, 0) }
        let stride = FrameRow.edge + Self.frameSpacing
        let usable = available - 2 * Self.frameInset
        let fit = max(1, Int((usable + Self.frameSpacing) / stride))
        let shown = min(count, fit)
        let content = CGFloat(shown) * FrameRow.edge
                    + CGFloat(shown - 1) * Self.frameSpacing
                    + 2 * Self.frameInset
        return min(available, content)
    }

    /// Keep the active frame fully in view (centered when possible, clamped at the ends).
    private func scrollToActiveFrame(_ proxy: ScrollViewProxy) {
        guard state.frames.indices.contains(state.activeFrameIndex) else { return }
        proxy.scrollTo(state.frames[state.activeFrameIndex].id, anchor: .center)
    }

    /// Toolbar-consistent button: a pixel-art glyph over an uppercase pixel-font label. The 11×11
    /// `PixelArtIcon` renders at 22pt (crisp) centered in a fixed 24×24 box, so every control's
    /// label shares one baseline. Mirrors `ToolBar.pixelIconLabel`; inherits the foreground color.
    private func pixelStripButton(pattern: [String], title: String) -> some View {
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
}

/// Pixel-art glyphs for the animation strip's chrome, in the app's 11×11 `#`/`.` style. PLAY reuses
/// the shared `PixelArtIcon.playTriangle` (same sprite as the editor's ANIMATE button); the rest are
/// defined here, matching how `ToolBar` keeps its tool glyphs local to the file that draws them.
private extension PixelArtIcon {
    /// PAUSE — two vertical bars.
    static let pause: [String] = [
        "...........",
        "...........",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "..##...##..",
        "...........",
        "...........",
    ]

    /// FPS — a round gauge (speedometer) with a short needle pointing up-right.
    static let gauge: [String] = [
        "...........",
        "...#####...",
        "..#.....#..",
        ".#....#..#.",
        ".#....#..#.",
        ".#...#...#.",
        ".#.......#.",
        "..#.....#..",
        "...#####...",
        "...........",
        "...........",
    ]

    /// ONION — two overlapping frames (a previous frame stacked behind the current one). Clearest
    /// legible read at 11px, and the closest pixel match to the old `square.2.layers.3d`.
    static let onion: [String] = [
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

    /// ADD — the app's thin 1px plus cross (matches the layers/gallery add glyph).
    static let addPlus: [String] = [
        "...........",
        ".....#.....",
        ".....#.....",
        ".....#.....",
        ".....#.....",
        ".#########.",
        ".....#.....",
        ".....#.....",
        ".....#.....",
        ".....#.....",
        "...........",
    ]
}
