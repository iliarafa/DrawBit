import SwiftUI

struct FramesStrip: View {
    let state: EditorState
    let onAddFrame: () -> Void
    /// onDuplicateFrame / onDeleteFrame are invoked from FrameRow's per-frame
    /// context menu (wired up in FrameRow), not from the strip's own chrome.
    let onDuplicateFrame: () -> Void
    /// Index-based reorder (from, to) used by FrameRow drag-and-drop.
    let onReorderFrame: (Int, Int) -> Void
    let onRenameFrame: (UUID, String) -> Void
    let onActivateFrame: (Int) -> Void
    let onTogglePlay: () -> Void
    let onDeleteFrame: () -> Void

    @State private var renamingFrameID: UUID?
    @State private var renameText: String = ""
    @FocusState private var renameFieldFocused: Bool
    @State private var showingFPSMenu = false

    private static let fpsChoices = [4, 8, 12, 24, 30, 60]

    var body: some View {
        HStack(spacing: 18) {
            // Transport group
            HStack(spacing: 16) {
                Button(action: onTogglePlay) {
                    stripButton(systemImage: state.isPlaying ? "pause.fill" : "play.fill",
                                title: state.isPlaying ? "PAUSE" : "PLAY")
                        .hoverPop()
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.frames.count <= 1 ? Color.white.opacity(0.25) : Color.white)
                .disabled(state.frames.count <= 1)
                .accessibilityIdentifier("FramesStrip.playPause")
                .accessibilityLabel(state.isPlaying ? "Pause animation" : "Play animation")

                // Custom dark/pixel popover instead of a native Menu, which can't
                // take the app font or theme.
                Button { showingFPSMenu = true } label: {
                    stripButton(systemImage: "speedometer", title: "\(state.fps) FPS")
                        .hoverPop()
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.isPlaying ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                .disabled(state.isPlaying)
                .accessibilityIdentifier("FramesStrip.fps")
                .accessibilityLabel("Playback speed")
                .accessibilityValue("\(state.fps) frames per second")
                .popover(isPresented: $showingFPSMenu) { fpsMenu }

                Button(action: { state.isOnionSkinEnabled.toggle() }) {
                    stripButton(systemImage: "square.2.layers.3d", title: "ONION")
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

            // Frames
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(state.frames.enumerated()), id: \.element.id) { index, frame in
                        if renamingFrameID == frame.id {
                            // Dark, pixel-font inline field matching LayerRow's rename
                            // treatment — no native `.roundedBorder` white box in the strip.
                            TextField("Frame name", text: $renameText)
                                .font(.pixel(11))
                                .foregroundStyle(.white)
                                .tint(.white)
                                .focused($renameFieldFocused)
                                .frame(width: 100)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(white: 0.16))
                                        .overlay(RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.25), lineWidth: 1))
                                )
                                .onSubmit { commitRename() }
                                .submitLabel(.done)
                                .onAppear { renameFieldFocused = true }
                        } else {
                            FrameRow(
                                frame: frame,
                                size: state.size,
                                index: index,
                                isActive: frame.id == state.frames[state.activeFrameIndex].id,
                                frameCount: state.frames.count,
                                onTap: {
                                    if renamingFrameID != nil && renamingFrameID != frame.id {
                                        commitRename()
                                    }
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
                                onRename: {
                                    renamingFrameID = frame.id
                                    renameText = frame.name
                                },
                                onDelete: {
                                    if let idx = state.frames.firstIndex(where: { $0.id == frame.id }) {
                                        onActivateFrame(idx)
                                    }
                                    onDeleteFrame()
                                },
                                onMove: { from, to in onReorderFrame(from, to) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .disabled(state.isPlaying)

            divider

            // Actions
            Button(action: onAddFrame) {
                stripButton(systemImage: "plus", title: "ADD")
                    .hoverPop()
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.frames.count >= FrameSequence.frameCap
                             ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
            .disabled(state.frames.count >= FrameSequence.frameCap)
            .accessibilityIdentifier("FramesStrip.add")
            .accessibilityLabel("Add blank frame")
        }
        .padding(.horizontal, 18)
        .frame(height: 88)
        // No background of its own: the strip inherits the editor's Color(white: 0.10),
        // identical to the canvas and tool strip, and has no dividers above or below — so
        // it blends in as one continuous surface.
    }

    /// Dark, pixel-font replacement for a native fps `Menu` (which renders with
    /// system chrome we can't theme). Tap a row to set the speed.
    private var fpsMenu: some View {
        VStack(spacing: 0) {
            ForEach(Self.fpsChoices, id: \.self) { choice in
                Button {
                    state.fps = choice
                    showingFPSMenu = false
                } label: {
                    HStack(spacing: 8) {
                        Text("\(choice) FPS")
                            .font(.pixel(10))
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .opacity(choice == state.fps ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("FramesStrip.fps.\(choice)")
                .accessibilityAddTraits(choice == state.fps ? .isSelected : [])

                if choice != Self.fpsChoices.last {
                    Divider().overlay(Color.white.opacity(0.12))
                }
            }
        }
        .frame(width: 160)
        .background(Color(white: 0.12))
        .presentationCompactAdaptation(.popover)
        .presentationBackground(Color(white: 0.12))
    }

    private var divider: some View {
        Divider().frame(height: 52).overlay(Color.white.opacity(0.15))
    }

    private var onionColor: Color {
        if state.activeFrameIndex == 0 || state.isPlaying { return Color.white.opacity(0.25) }
        return state.isOnionSkinEnabled ? Color.white : Color.white.opacity(0.55)
    }

    /// Toolbar-consistent button: SF Symbol over an uppercase pixel-font label.
    /// Mirrors `ToolBar.iconLabel`.
    private func stripButton(systemImage: String, title: String) -> some View {
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

    private func commitRename() {
        guard let id = renamingFrameID else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           let current = state.frames.first(where: { $0.id == id }),
           trimmed != current.name {
            onRenameFrame(id, trimmed)
        }
        renamingFrameID = nil
        renameText = ""
    }
}
