import XCTest
@testable import DrawBit

/// "Profile sequence-undo memory" — the cleanup follow-up flagged in the
/// 2026-05-09 animation handoff (Stage 2 plan Task 2.4 step 2).
///
/// The numbers up front, derived from current constants:
/// - Largest canvas: `.s128` → 128² × 4 bytes = 65,536 bytes = 64 KiB per layer.
/// - Max layers per frame (`Frame.maxLayers`): 16 → 1 MiB per frame at worst case.
/// - Max frames per sequence (`FrameSequence.frameCap`): 60 → 60 MiB per snapshot.
///
/// A `.sequenceStructure` undo entry holds a full `[Frame]` snapshot, so at the
/// generic `undoLimit = 50` a fully-loaded undo stack of nothing but
/// sequence-structure snapshots would be 50 × 60 MiB = ~3 GiB — well above the
/// foreground-memory budget iOS gives an iPad app (typically 1–3 GiB before
/// jetsam). The tighter `sequenceStructureUndoLimit = 10` keeps the worst case
/// at ~600 MiB.
///
/// These tests document the math AND verify the cap actually trims the stack.
@MainActor
final class SequenceUndoMemoryTests: XCTestCase {
    /// Pure-math sanity check: the constants currently in `EditorState` and the
    /// model layer should produce a sequence-structure worst case below a
    /// 1 GiB headroom budget. If this assertion ever fails, either lower the
    /// sequence-structure cap, switch `.sequenceStructure` to delta encoding,
    /// raise the budget intentionally, or shrink the model maxima.
    func testWorstCaseSequenceUndoFitsBudget() {
        let bytesPerLayer = CanvasSize.s128.byteCount               // 65,536
        let bytesPerFrame = bytesPerLayer * Frame.maxLayers          // 1,048,576 (1 MiB)
        let bytesPerSnapshot = bytesPerFrame * FrameSequence.frameCap // 62,914,560 (60 MiB)

        // The effective cap that bounds memory. EditorState exposes this only
        // via the behavior tested below; mirror the constant here so this test
        // can stand alone as documentation.
        let sequenceStructureUndoLimit = 10
        let worstCaseBytes = bytesPerSnapshot * sequenceStructureUndoLimit
        let budgetBytes = 1024 * 1024 * 1024 // 1 GiB headroom budget
        XCTAssertLessThanOrEqual(
            worstCaseBytes, budgetBytes,
            """
            Worst-case sequence-undo footprint \(worstCaseBytes / (1024 * 1024)) MiB
            exceeds the \(budgetBytes / (1024 * 1024)) MiB budget. Options:
              - Lower EditorState.sequenceStructureUndoLimit
              - Switch .sequenceStructure to a delta-encoded enum
              - Raise the budget if the device target changed
              - Shrink Frame.maxLayers or FrameSequence.frameCap
            """
        )
    }

    /// Behavior: pushing more than `sequenceStructureUndoLimit` structural
    /// frame mutations evicts the oldest sequence-structure entries, even
    /// though the generic `undoLimit=50` would otherwise allow them.
    /// Layer-pixel entries are unaffected by the sequence-specific cap.
    func testSequenceStructureCapEvictsOldestSnapshots() {
        // Tiny piece so the test stays cheap.
        let layer = Layer(name: "L", pixels: Data(count: CanvasSize.s16.byteCount))
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        let state = EditorState(pieceID: UUID(), size: .s16,
                                frames: [frame], activeFrameIndex: 0, fps: 12)

        // Push 15 sequence-structure mutations. Each one snapshots `state.frames`
        // before the mutation. With sequenceStructureUndoLimit = 10, the stack
        // should drop the 5 oldest entries.
        for i in 0..<15 {
            state.beginSequenceSnapshot()
            // Append a synthetic frame (test bypasses the FrameSequence frameCap
            // for measurement purposes; the cap-eviction logic doesn't depend on
            // the model's structural rules).
            let newLayer = Layer(name: "L\(i + 2)", pixels: Data(count: CanvasSize.s16.byteCount))
            let newFrame = Frame(name: "F\(i + 2)", layers: [newLayer], activeLayerID: newLayer.id)
            state.frames.append(newFrame)
            state.commitSequenceChange()
        }

        // Count sequence-structure entries in the undo stack via the public
        // undo/redo behaviour: undo back through the whole stack and count.
        var sequenceUndos = 0
        var safety = 100
        while state.canUndo, safety > 0 {
            let before = state.frames.count
            state.undo()
            let after = state.frames.count
            if before != after {
                sequenceUndos += 1
            }
            safety -= 1
        }

        XCTAssertEqual(sequenceUndos, 10,
                       "Expected exactly 10 sequence-structure undo entries to "
                       + "survive; saw \(sequenceUndos). Cap eviction may be broken.")
    }

    /// Negative case: layer-pixel undo entries should NOT be evicted by the
    /// sequence-structure cap. Push many pixel strokes and confirm they all
    /// survive (subject only to the generic undoLimit).
    func testLayerPixelEntriesUnaffectedBySequenceCap() {
        let layer = Layer(name: "L", pixels: Data(count: CanvasSize.s16.byteCount))
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        let state = EditorState(pieceID: UUID(), size: .s16,
                                frames: [frame], activeFrameIndex: 0, fps: 12)

        // 20 distinct pixel-stroke undo entries.
        for i in 0..<20 {
            state.beginStrokeSnapshot()
            state.mutateActiveLayerPixels { data in
                // Write a unique byte so each entry is materially different.
                var copy = data
                copy[i % copy.count] = UInt8((i + 1) & 0xFF)
                data = copy
            }
            state.commitStroke()
        }

        var pixelUndos = 0
        var safety = 100
        while state.canUndo, safety > 0 {
            state.undo()
            pixelUndos += 1
            safety -= 1
        }

        XCTAssertEqual(pixelUndos, 20,
                       "Layer-pixel entries should be unaffected by sequence cap; "
                       + "saw \(pixelUndos) undos instead of 20.")
    }
}
