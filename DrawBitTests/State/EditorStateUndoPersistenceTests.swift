import XCTest
import SwiftData
@testable import DrawBit

/// Regression coverage for the undo/redo save path that landed in commit `a5d50ed`
/// without an accompanying test (layers v2 cleanup follow-up).
///
/// `EditorView` calls `state.undo()` / `state.redo()` then immediately calls
/// `saveCurrentFrame()`. Without that save, the in-memory frame reverts but the
/// on-disk piece keeps the post-mutation state — so closing and reopening the
/// editor would reveal the supposedly-undone change.
///
/// These tests simulate the EditorView call sequence directly (no SwiftUI) and
/// assert that the persisted state actually matches the in-memory state after
/// undo + save.
@MainActor
final class EditorStateUndoPersistenceTests: XCTestCase {
    var container: ModelContainer!
    var modelContext: ModelContext!
    var repo: PieceRepository!

    override func setUpWithError() throws {
        let schema = Schema([Piece.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        modelContext = ModelContext(container)
        repo = PieceRepository(context: modelContext)
    }

    /// Mirror of `EditorView.saveCurrentFrame()` — persists the full sequence.
    private func saveCurrentFrame(_ state: EditorState, piece: Piece) throws {
        try repo.saveFrames(piece: piece,
                            frames: state.frames,
                            activeFrameIndex: state.activeFrameIndex,
                            fps: state.fps)
    }

    private func makeEditorState(for piece: Piece) throws -> EditorState {
        let loaded = try repo.loadFrames(piece: piece)
        return EditorState(piece: piece,
                           frames: loaded.frames,
                           activeFrameIndex: loaded.activeFrameIndex,
                           fps: loaded.fps)
    }

    /// Add a layer → save → undo → save. Reloading from disk should show the
    /// pre-mutation layer count, not the post-mutation count.
    func testStructuralUndoPersistsToDisk() throws {
        let piece = try repo.createPiece(size: .s16)
        let state = try makeEditorState(for: piece)
        XCTAssertEqual(state.frame.layers.count, 1, "baseline: 1 layer")

        // Mutate: add a layer with structural snapshot, then save.
        state.beginStructuralSnapshot()
        state.frame.addLayer(name: "Layer 2")
        state.commitStructuralChange()
        try saveCurrentFrame(state, piece: piece)

        var reloaded = try repo.loadFrames(piece: piece)
        XCTAssertEqual(reloaded.frames[0].layers.count, 2, "after add+save: 2 layers")

        // Undo the add — in memory the frame should drop back to 1 layer.
        state.undo()
        XCTAssertEqual(state.frame.layers.count, 1, "in-memory after undo: 1 layer")

        // Save again. Without this save the on-disk piece would still show 2 layers.
        try saveCurrentFrame(state, piece: piece)

        reloaded = try repo.loadFrames(piece: piece)
        XCTAssertEqual(reloaded.frames[0].layers.count, 1,
                       "after undo+save: on-disk piece reflects the undo")

        // Redo and re-save. Persistence should round-trip the other way too.
        state.redo()
        XCTAssertEqual(state.frame.layers.count, 2, "in-memory after redo: 2 layers")
        try saveCurrentFrame(state, piece: piece)

        reloaded = try repo.loadFrames(piece: piece)
        XCTAssertEqual(reloaded.frames[0].layers.count, 2,
                       "after redo+save: on-disk piece reflects the redo")
    }

    /// Modify layer pixels → save → undo → save. The on-disk layer's pixels
    /// must revert to the pre-modification bytes.
    func testLayerPixelUndoPersistsToDisk() throws {
        let piece = try repo.createPiece(size: .s16)
        let state = try makeEditorState(for: piece)
        let baselinePixels = state.frame.layers[0].pixels
        XCTAssertTrue(baselinePixels.allSatisfy { $0 == 0 },
                      "baseline: all-transparent")

        // Mutate: paint a single pixel via the stroke-snapshot lifecycle.
        state.beginStrokeSnapshot()
        state.mutateActiveLayerPixels { data in
            var grid = PixelGrid(data: data, size: state.size)
            Pencil.paint(on: &grid, at: (1, 1), color: RGBA(r: 200, g: 0, b: 0, a: 255))
            data = grid.data
        }
        state.commitStroke()
        try saveCurrentFrame(state, piece: piece)

        var reloaded = try repo.loadFrames(piece: piece)
        XCTAssertNotEqual(reloaded.frames[0].layers[0].pixels, baselinePixels,
                          "after stroke+save: pixels differ from baseline")

        // Undo the stroke. In memory the pixels revert.
        state.undo()
        XCTAssertEqual(state.frame.layers[0].pixels, baselinePixels,
                       "in-memory after undo: pixels match baseline")

        // Save. The on-disk pixels must also match the baseline now.
        try saveCurrentFrame(state, piece: piece)

        reloaded = try repo.loadFrames(piece: piece)
        XCTAssertEqual(reloaded.frames[0].layers[0].pixels, baselinePixels,
                       "after undo+save: on-disk pixels match baseline")
    }
}
