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

    /// Loads a Frame for the given piece. If the piece is still in v1 raw-RGBA shape (no
    /// "DBFR" magic prefix), migrates it in place and writes the result back. This is the
    /// per-read defense-in-depth for the eager migration in `migrateLegacyPiecesIfNeeded`.
    func loadFrame(piece: Piece) throws -> Frame {
        if FrameCodec.hasV1MagicPrefix(piece.frameData) {
            return try FrameCodec.decode(piece.frameData)
        }
        let frame = FrameCodec.wrapV1Data(piece.frameData, defaultName: "Layer 1")
        piece.frameData = FrameCodec.encode(frame)
        piece.updatedAt = Date()
        try context.save()
        return frame
    }

    /// Persists the given Frame to the piece, regenerates its thumbnail, bumps updatedAt, and saves.
    func saveFrame(piece: Piece, _ frame: Frame) throws {
        piece.frameData = FrameCodec.encode(frame)
        piece.thumbnail = ThumbnailRenderer.render(frame: frame, size: piece.size, targetEdge: 256) ?? Data()
        piece.updatedAt = Date()
        try context.save()
    }

    /// Walks every piece and migrates any that still hold raw v1 data.
    func migrateLegacyPiecesIfNeeded() throws {
        let descriptor = FetchDescriptor<Piece>()
        let pieces = try context.fetch(descriptor)
        var dirty = false
        for piece in pieces where !FrameCodec.hasV1MagicPrefix(piece.frameData) {
            let frame = FrameCodec.wrapV1Data(piece.frameData, defaultName: "Layer 1")
            piece.frameData = FrameCodec.encode(frame)
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

    /// Duplicates a piece by reading its Frame and rebuilding with fresh layer UUIDs so
    /// the duplicate's layers don't share IDs with the source (important for undo entries
    /// and any future animation work that references layers by id).
    func duplicate(piece: Piece) throws -> Piece {
        let sourceFrame = try loadFrame(piece: piece)
        let copy = Piece(size: piece.size)
        // Rebuild layers with fresh ids while preserving order and contents.
        let freshLayers = sourceFrame.layers.map { Layer(name: $0.name, pixels: $0.pixels,
                                                          isVisible: $0.isVisible, isLocked: $0.isLocked) }
        // The active layer in source maps to the same array index in the copy.
        let activeIdx = sourceFrame.layers.firstIndex(where: { $0.id == sourceFrame.activeLayerID }) ?? 0
        let freshFrame = Frame(layers: freshLayers, activeLayerID: freshLayers[activeIdx].id)
        copy.frameData = FrameCodec.encode(freshFrame)
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
