import SwiftUI
import UIKit

struct LayersPanel: View {
    let state: EditorState
    let isPresented: Bool
    let onRenameLayer: (UUID, String) -> Void
    let onStructuralChange: () -> Void
    let onReferenceImport: (Data) -> Void
    let onReferenceRemove: () -> Void
    let onReferenceOpacityCommit: () -> Void
    let onDismiss: () -> Void

    @State private var confirmDeleteLayerID: UUID?

    /// Live drag-reorder state. `start` is the dragged row's original display slot; `translation`
    /// is the running vertical drag in points. `nil` when no drag is in flight.
    @State private var drag: (id: UUID, start: Int, translation: CGFloat)?
    /// Last slot the drag crossed — used to fire a selection tick only on a new slot.
    @State private var lastDragTarget: Int?

    private let liftHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let dropHaptic = UIImpactFeedbackGenerator(style: .light)
    private let crossHaptic = UISelectionFeedbackGenerator()

    var body: some View {
        ZStack(alignment: .trailing) {
            if isPresented {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    HStack {
                        Text("LAYERS").font(.pixel(11)).foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Button {
                            onDismiss()
                        } label: {
                            PixelArtIcon(pattern: PixelArtIcon.panelClose, size: 16)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                                .hoverPop()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider().overlay(Color.white.opacity(0.08))

                    // Top of list = top of stack (layers stored bottom-up; reverse for display).
                    layerList

                    // Action bar — wired in stage 3.
                    HStack(spacing: 12) {
                        let addDisabled = state.frame.layers.count >= Frame.maxLayers || state.isPlaying
                        Button {
                            state.commitFloatingSelectionIfAny()
                            state.beginStructuralSnapshot()
                            state.frame.addLayer(name: "Layer \(state.frame.layers.count + 1)")
                            state.commitStructuralChange()
                            onStructuralChange()
                        } label: {
                            actionButton(pattern: PixelArtIcon.layerAdd, title: "ADD")
                                .foregroundStyle(addDisabled ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                                .hoverPop()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("LayersPanel-plus")
                        .disabled(addDisabled)

                        let dupDisabled = state.frame.layers.count >= Frame.maxLayers || state.isPlaying
                        Button {
                            state.commitFloatingSelectionIfAny()
                            state.beginStructuralSnapshot()
                            state.frame.duplicateActiveLayer()
                            state.commitStructuralChange()
                            onStructuralChange()
                        } label: {
                            actionButton(pattern: PixelArtIcon.layerDuplicate, title: "DUPE")
                                .foregroundStyle(dupDisabled ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                                .hoverPop()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("LayersPanel-duplicate")
                        .disabled(dupDisabled)

                        let delDisabled = state.frame.layers.count <= 1 || state.isPlaying
                        Button {
                            // Commit any floating marquee FIRST so the isEmpty check sees
                            // the post-commit layer pixels — without this reorder, a
                            // layer whose content has been entirely lifted into a marquee
                            // selection reads as empty (because extractAndCut zeroes the
                            // stored buffer) and would be silently deleted along with the
                            // selection it just received back.
                            state.commitFloatingSelectionIfAny()
                            let active = state.frame.activeLayer
                            let isEmpty = active.pixels.allSatisfy { $0 == 0 }
                            if isEmpty {
                                state.beginStructuralSnapshot()
                                state.frame.removeLayer(id: active.id)
                                state.commitStructuralChange()
                                onStructuralChange()
                            } else {
                                confirmDeleteLayerID = active.id
                            }
                        } label: {
                            actionButton(pattern: PixelArtIcon.layerTrash, title: "DELETE")
                                .foregroundStyle(delDisabled ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                                .hoverPop()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("LayersPanel-delete")
                        .disabled(delDisabled)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .sheet(isPresented: Binding(
                        get: { confirmDeleteLayerID != nil },
                        set: { if !$0 { confirmDeleteLayerID = nil } }
                    )) {
                        ConfirmDialogSheet(
                            title: "DELETE LAYER?",
                            confirmLabel: "DELETE",
                            onCancel: { confirmDeleteLayerID = nil },
                            onConfirm: {
                                if let id = confirmDeleteLayerID {
                                    state.commitFloatingSelectionIfAny()
                                    state.beginStructuralSnapshot()
                                    state.frame.removeLayer(id: id)
                                    state.commitStructuralChange()
                                    onStructuralChange()
                                }
                                confirmDeleteLayerID = nil
                            }
                        )
                        .presentationDetents([.height(200)])
                        .presentationCornerRadius(0)
                        .presentationBackground(Color(white: 0.10))
                    }
                    Divider().overlay(Color.white.opacity(0.08))
                    ReferenceRow(
                        state: state,
                        onImport: onReferenceImport,
                        onRemove: onReferenceRemove,
                        onOpacityCommit: onReferenceOpacityCommit
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(width: 360)
                .background(Color(white: 0.10))
                .transition(.move(edge: .trailing))
            }
        }
        .animation(UITestSupport.isRunning ? nil : .easeInOut(duration: 0.18), value: isPresented)
    }

    // MARK: - Layer list

    /// `ScrollView + LazyVStack` instead of `List` — `List` reorder chrome can't be themed and
    /// fought the pixel aesthetic. Reorder is a custom long-press-then-drag (see `rowDrag*`).
    /// Scrolling is locked while a drag is armed so the two gestures don't fight.
    private var layerList: some View {
        let count = state.frame.layers.count
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(state.frame.layers.reversed().enumerated()), id: \.element.id) { displayIndex, layer in
                    LayerRow(
                        layer: layer,
                        size: state.size,
                        isActive: layer.id == state.frame.activeLayerID,
                        onTap: {
                            state.commitFloatingSelectionIfAny()
                            state.frame.setActive(id: layer.id)
                            onStructuralChange()
                        },
                        onToggleVisible: {
                            state.commitFloatingSelectionIfAny()
                            state.beginStructuralSnapshot()
                            state.frame.setVisible(id: layer.id, to: !layer.isVisible)
                            state.commitStructuralChange()
                            onStructuralChange()
                        },
                        onToggleLocked: {
                            state.commitFloatingSelectionIfAny()
                            state.beginStructuralSnapshot()
                            state.frame.setLocked(id: layer.id, to: !layer.isLocked)
                            state.commitStructuralChange()
                            onStructuralChange()
                        },
                        isPulsing: state.lockPulseLayerID == layer.id,
                        onRename: { newName in
                            onRenameLayer(layer.id, newName)
                        },
                        displayIndex: displayIndex,
                        layerCount: count,
                        onMoveByDisplayIndex: { from, to in performMove(displayFrom: from, displayTo: to) },
                        visualOffset: rowVisualOffset(displayIndex: displayIndex, count: count),
                        isLifted: drag?.id == layer.id,
                        onDragChanged: { start, translation in rowDragChanged(id: layer.id, start: start, translation: translation, count: count) },
                        onDragEnded: { start in rowDragEnded(start: start, count: count) },
                        onDelete: { deleteLayer(id: layer.id) }
                    )
                    .zIndex(drag?.id == layer.id ? 1 : 0)
                    .animation(UITestSupport.isRunning ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.82),
                               value: drag?.translation)
                }
            }
        }
        .coordinateSpace(name: "layerList")
        .scrollDisabled(drag != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            liftHaptic.prepare(); dropHaptic.prepare(); crossHaptic.prepare()
        }
    }

    // MARK: - Custom drag-reorder

    /// This row's live vertical offset: the lifted row follows the finger; the rows it passes
    /// open a gap. All derived from `drag` + the pure `LayerDragMath` helpers.
    private func rowVisualOffset(displayIndex i: Int, count: Int) -> CGFloat {
        guard let drag else { return 0 }
        if i == drag.start { return drag.translation }
        let target = draggedDisplayIndex(start: drag.start, translation: drag.translation,
                                         rowHeight: LayerRow.rowHeight, count: count)
        return rowGapShift(displayIndex: i, start: drag.start, target: target, rowHeight: LayerRow.rowHeight)
    }

    private func rowDragChanged(id: UUID, start: Int, translation: CGFloat, count: Int) {
        if drag == nil { liftHaptic.impactOccurred() }   // first frame of the lift
        drag = (id, start, translation)
        let target = draggedDisplayIndex(start: start, translation: translation,
                                         rowHeight: LayerRow.rowHeight, count: count)
        if target != lastDragTarget {
            if lastDragTarget != nil { crossHaptic.selectionChanged() }
            lastDragTarget = target
        }
    }

    private func rowDragEnded(start: Int, count: Int) {
        let translation = drag?.translation ?? 0
        let target = draggedDisplayIndex(start: start, translation: translation,
                                         rowHeight: LayerRow.rowHeight, count: count)
        drag = nil
        lastDragTarget = nil
        if target != start {
            dropHaptic.impactOccurred()
            performMove(displayFrom: start, displayTo: target)
        }
    }

    /// Toolbar-consistent button: a hard-pixel glyph over an uppercase pixel-font
    /// label. Mirrors `ToolBar.iconLabel` / `FramesStrip.stripButton` so the panel's
    /// action bar matches the rest of the editor chrome.
    private func actionButton(pattern: [String], title: String) -> some View {
        VStack(spacing: 6) {
            PixelArtIcon(pattern: pattern, size: 20)
            Text(title)
                .font(.pixel(8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    /// Swipe-left-to-delete a specific row's layer. Mirrors the DELETE button: never removes the
    /// last layer, deletes an empty layer outright, and routes a non-empty one through the confirm
    /// sheet (reusing `confirmDeleteLayerID`). Commits any floating marquee first so a layer whose
    /// pixels are currently lifted into a selection isn't misread as empty.
    private func deleteLayer(id: UUID) {
        guard state.frame.layers.count > 1 else { return }
        state.commitFloatingSelectionIfAny()
        guard let target = state.frame.layers.first(where: { $0.id == id }) else { return }
        let isEmpty = target.pixels.allSatisfy { $0 == 0 }
        if isEmpty {
            state.beginStructuralSnapshot()
            state.frame.removeLayer(id: id)
            state.commitStructuralChange()
            onStructuralChange()
        } else {
            confirmDeleteLayerID = id
        }
    }

    /// Drop-on-target reorder: the moved layer takes the target row's display slot.
    /// Display order is the model layers reversed, so model index = count − 1 − display index.
    private func performMove(displayFrom: Int, displayTo: Int) {
        let count = state.frame.layers.count
        guard displayFrom != displayTo,
              (0..<count).contains(displayFrom),
              (0..<count).contains(displayTo) else { return }
        let modelFrom = count - 1 - displayFrom
        let modelTo = count - 1 - displayTo
        let id = state.frame.layers[modelFrom].id

        state.commitFloatingSelectionIfAny()
        state.beginStructuralSnapshot()
        state.frame.move(id: id, toIndex: modelTo)
        state.commitStructuralChange()
        onStructuralChange()
    }
}

/// Hard-pixel glyphs for the Layers panel + reference row, so the panel speaks the same
/// pixel-art language as the toolbar, HELP tiles, and selection bar instead of SF Symbols.
/// All 11×11 in the `#`/`.` grid `PixelArtIcon` renders; `.` is transparent.
extension PixelArtIcon {
    /// Rename — a diagonal pencil, sharp tip bottom-left, eraser end top-right.
    static let layerRename: [String] = [
        ".........##",
        "........###",
        ".......###.",
        "......###..",
        ".....###...",
        "....###....",
        "...###.....",
        "..###......",
        ".###.......",
        "##.........",
        "#..........",
    ]

    /// Visibility ON — an open almond eye with a solid pupil.
    static let layerEyeOpen: [String] = [
        "...........",
        "...........",
        "..#######..",
        ".#.......#.",
        "#...###...#",
        "#..#####..#",
        "#...###...#",
        ".#.......#.",
        "..#######..",
        "...........",
        "...........",
    ]

    /// Visibility OFF — a closed, downcast lid with lashes.
    static let layerEyeClosed: [String] = [
        "...........",
        "...........",
        "...........",
        "...........",
        ".#########.",
        "..#######..",
        "...#.#.#...",
        "..#.#.#.#..",
        "...........",
        "...........",
        "...........",
    ]

    /// Locked — a closed padlock (shackle down, keyhole slot).
    static let layerLockClosed: [String] = [
        "...........",
        "....###....",
        "...#...#...",
        "...#...#...",
        "..#######..",
        "..#######..",
        "..##.#.##..",
        "..##.#.##..",
        "..#######..",
        "..#######..",
        "...........",
    ]

    /// Unlocked — the padlock with its shackle swung open to the left.
    static let layerLockOpen: [String] = [
        "..####.....",
        ".#....#....",
        ".#.........",
        ".#.........",
        "..#######..",
        "..#######..",
        "..##.#.##..",
        "..##.#.##..",
        "..#######..",
        "..#######..",
        "...........",
    ]

    /// Add layer — a bold plus.
    static let layerAdd: [String] = [
        "...........",
        "....###....",
        "....###....",
        "....###....",
        ".#########.",
        ".#########.",
        ".#########.",
        "....###....",
        "....###....",
        "....###....",
        "...........",
    ]

    /// Duplicate — two overlapping squares (same metaphor as the selection bar's copy).
    static let layerDuplicate: [String] = [
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

    /// Delete — a trash can with slats.
    static let layerTrash: [String] = [
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

    /// Reference photo — a framed picture with a sun and a mountain.
    static let refPhoto: [String] = [
        ".#########.",
        ".#.......#.",
        ".#.##....#.",
        ".#.##....#.",
        ".#.......#.",
        ".#....#..#.",
        ".#..######.",
        ".#########.",
        "...........",
        "...........",
        "...........",
    ]

    /// Opacity/fade — a half-filled circle (left solid, right outline).
    static let refFade: [String] = [
        "...........",
        "...####....",
        "..####.#...",
        ".#####..#..",
        ".#####..#..",
        ".#####..#..",
        ".#####..#..",
        ".#####..#..",
        "..####.#...",
        "...####....",
        "...........",
    ]

    /// Panel close — a hard X.
    static let panelClose: [String] = [
        "...........",
        ".#.......#.",
        ".##.....##.",
        "..##...##..",
        "...##.##...",
        "....###....",
        "...##.##...",
        "..##...##..",
        ".##.....##.",
        ".#.......#.",
        "...........",
    ]
}
