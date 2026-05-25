import SwiftUI

struct FramesStrip: View {
    let state: EditorState
    let onAddFrame: () -> Void
    let onDuplicateFrame: () -> Void
    /// Index-based reorder (from, to) used by FrameRow drag-and-drop.
    let onReorderFrame: (Int, Int) -> Void
    let onRenameFrame: (UUID, String) -> Void
    let onActivateFrame: (Int) -> Void
    let onTogglePlay: () -> Void
    let onDeleteFrame: () -> Void

    @State private var renamingFrameID: UUID?
    @State private var renameText: String = ""

    private static let fpsChoices = [4, 8, 12, 24, 30, 60]

    var body: some View {
        HStack(spacing: 18) {
            // Transport group
            HStack(spacing: 16) {
                Button(action: onTogglePlay) {
                    stripButton(systemImage: state.isPlaying ? "pause.fill" : "play.fill",
                                title: state.isPlaying ? "PAUSE" : "PLAY")
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.frames.count <= 1 ? Color.white.opacity(0.25) : Color.white)
                .disabled(state.frames.count <= 1)
                .accessibilityIdentifier("FramesStrip.playPause")
                .accessibilityLabel(state.isPlaying ? "Pause animation" : "Play animation")

                Menu {
                    ForEach(Self.fpsChoices, id: \.self) { choice in
                        Button {
                            state.fps = choice
                        } label: {
                            if choice == state.fps {
                                Label("\(choice) FPS", systemImage: "checkmark")
                            } else {
                                Text("\(choice) FPS")
                            }
                        }
                    }
                } label: {
                    stripButton(systemImage: "speedometer", title: "\(state.fps) FPS")
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.isPlaying ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                .disabled(state.isPlaying)
                .accessibilityIdentifier("FramesStrip.fps")
                .accessibilityLabel("Playback speed")
                .accessibilityValue("\(state.fps) frames per second")

                Button(action: { state.isOnionSkinEnabled.toggle() }) {
                    stripButton(systemImage: "square.2.layers.3d", title: "ONION")
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
                HStack(spacing: 12) {
                    ForEach(Array(state.frames.enumerated()), id: \.element.id) { index, frame in
                        if renamingFrameID == frame.id {
                            TextField("Frame name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .onSubmit { commitRename() }
                                .submitLabel(.done)
                        } else {
                            FrameRow(
                                frame: frame,
                                size: state.size,
                                isActive: frame.id == state.frames[state.activeFrameIndex].id,
                                isEditing: false,
                                onTap: {
                                    if renamingFrameID != nil && renamingFrameID != frame.id {
                                        commitRename()
                                    }
                                    if let idx = state.frames.firstIndex(where: { $0.id == frame.id }) {
                                        onActivateFrame(idx)
                                    }
                                },
                                onLongPressRename: {
                                    renamingFrameID = frame.id
                                    renameText = frame.name
                                }
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
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.frames.count >= FrameSequence.frameCap
                             ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
            .disabled(state.frames.count >= FrameSequence.frameCap)
            .accessibilityIdentifier("FramesStrip.add")
            .accessibilityLabel("Add blank frame")
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .background(Color.black.opacity(0.4))
    }

    private var divider: some View {
        Divider().frame(height: 36).overlay(Color.white.opacity(0.15))
    }

    private var onionColor: Color {
        if state.activeFrameIndex == 0 || state.isPlaying { return Color.white.opacity(0.25) }
        return state.isOnionSkinEnabled ? Color.white : Color.white.opacity(0.55)
    }

    /// Toolbar-consistent button: SF Symbol over an uppercase pixel-font label.
    /// Mirrors `ToolBar.iconLabel`.
    private func stripButton(systemImage: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
            Text(title)
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
