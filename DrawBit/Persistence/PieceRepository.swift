import Foundation
import SwiftData

@MainActor
final class PieceRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func allPieces() throws -> [Piece] {
        var descriptor = FetchDescriptor<Piece>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor)
    }

    func createPiece(size: CanvasSize) throws -> Piece {
        let piece = Piece(size: size)
        context.insert(piece)
        try context.save()
        return piece
    }

    // MARK: - Sequence load/save (V2)

    /// Loads the full frame sequence + active index + fps. If the piece is still in V1
    /// (single-frame "DBFR" blob) or raw legacy bytes, migrates in place to V2 ("DBFS")
    /// before returning.
    func loadFrames(piece: Piece) throws
        -> (frames: [Frame], activeFrameIndex: Int, fps: Int)
    {
        // Fast path: already V2 — no migration or re-encode needed.
        if FrameCodec.hasV2SequenceMagicPrefix(piece.frameData) {
            return try FrameCodec.decodeSequence(piece.frameData)
        }
        // V1 or raw bytes: migrate in place and persist the canonical V2 form.
        let result = FrameCodec.decodeAnyFrameData(piece.frameData,
                                                    fallbackByteCount: piece.size.byteCount)
        piece.frameData = FrameCodec.encodeSequence(frames: result.frames,
                                                    activeFrameIndex: result.activeFrameIndex,
                                                    fps: result.fps)
        piece.updatedAt = Date()
        do {
            try context.save()
        } catch {
            // Defensive: if persistence fails, the in-memory blob is already V2.
            // A subsequent saveFrames will write the canonical V2 form to disk.
        }
        return result
    }

    /// Persists the full sequence and regenerates the gallery thumbnail from the FIRST frame.
    func saveFrames(piece: Piece, frames: [Frame], activeFrameIndex: Int, fps: Int) throws {
        piece.frameData = FrameCodec.encodeSequence(frames: frames,
                                                    activeFrameIndex: activeFrameIndex,
                                                    fps: fps)
        if let firstThumb = ThumbnailRenderer.render(frame: frames[0],
                                                     size: piece.size,
                                                     targetEdge: 256) {
            piece.thumbnail = firstThumb
        }
        piece.updatedAt = Date()
        try context.save()
    }

    // MARK: - Single-frame shims (V1 API, delegates to sequence methods)

    /// Loads a Frame for the given piece. Delegates to `loadFrames` which handles all
    /// migration paths (V2 sequence, V1 single-frame, and raw legacy bytes).
    func loadFrame(piece: Piece) throws -> Frame {
        let result = try loadFrames(piece: piece)
        return result.frames[result.activeFrameIndex]
    }

    /// Persists the given Frame to the piece. Delegates to `saveFrames`, preserving fps
    /// if the piece already has a V2 sequence blob.
    func saveFrame(piece: Piece, _ frame: Frame) throws {
        let existing = try? loadFrames(piece: piece)
        try saveFrames(piece: piece,
                       frames: [frame],
                       activeFrameIndex: 0,
                       fps: existing?.fps ?? FrameCodec.defaultFPS)
    }

    // MARK: - Migration

    /// Walks every piece and migrates any that are NOT already V2 sequence blobs.
    func migrateLegacyPiecesIfNeeded() throws {
        let descriptor = FetchDescriptor<Piece>()
        let pieces = try context.fetch(descriptor)
        var dirty = false
        for piece in pieces where !FrameCodec.hasV2SequenceMagicPrefix(piece.frameData) {
            let result = FrameCodec.decodeAnyFrameData(piece.frameData,
                                                        fallbackByteCount: piece.size.byteCount)
            piece.frameData = FrameCodec.encodeSequence(frames: result.frames,
                                                        activeFrameIndex: result.activeFrameIndex,
                                                        fps: result.fps)
            piece.updatedAt = Date()
            dirty = true
        }
        if dirty { try context.save() }
    }

    func rename(piece: Piece, to name: String?) throws {
        piece.name = (name?.isEmpty ?? true) ? nil : name
        piece.updatedAt = Date()
        try context.save()
    }

    /// Duplicates a piece, rebuilding every frame with fresh layer UUIDs so the duplicate's
    /// layers don't share IDs with the source. Preserves the full frame sequence.
    func duplicate(piece: Piece) throws -> Piece {
        let source = try loadFrames(piece: piece)
        let copy = Piece(size: piece.size)

        // Rebuild every frame with fresh layer UUIDs (consistent across the sequence).
        let firstFrame = source.frames[0]
        let freshLayerIDs = firstFrame.layers.map { _ in UUID() }
        let freshFrames: [Frame] = source.frames.map { sourceFrame in
            let freshLayers = zip(sourceFrame.layers, freshLayerIDs).map { layer, newID in
                Layer(id: newID, name: layer.name, pixels: layer.pixels,
                      isVisible: layer.isVisible, isLocked: layer.isLocked)
            }
            let activeIdx = sourceFrame.layers.firstIndex(where: { $0.id == sourceFrame.activeLayerID }) ?? 0
            return Frame(name: sourceFrame.name,
                         layers: freshLayers,
                         activeLayerID: freshLayers[activeIdx].id)
        }

        copy.frameData = FrameCodec.encodeSequence(frames: freshFrames,
                                                   activeFrameIndex: source.activeFrameIndex,
                                                   fps: source.fps)
        copy.thumbnail = piece.thumbnail
        if let original = piece.name, !original.isEmpty {
            copy.name = "\(original) copy"
        } else {
            copy.name = "\(piece.effectiveName) copy"
        }
        context.insert(copy)
        try context.save()
        return copy
    }

    func delete(piece: Piece) throws {
        context.delete(piece)
        try context.save()
    }

    func appSettings() throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try context.fetch(descriptor).first { return existing }
        let created = AppSettings()
        context.insert(created)
        try context.save()
        return created
    }
}
