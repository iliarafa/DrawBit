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

    func save(piece: Piece, pixels: Data) throws {
        precondition(pixels.count == piece.size.byteCount)
        piece.pixels = pixels
        piece.thumbnail = ThumbnailRenderer.render(
            grid: PixelGrid(data: pixels, size: piece.size),
            targetEdge: 256
        ) ?? Data()
        piece.updatedAt = Date()
        try context.save()
    }

    func rename(piece: Piece, to name: String?) throws {
        piece.name = (name?.isEmpty ?? true) ? nil : name
        piece.updatedAt = Date()
        try context.save()
    }

    func duplicate(piece: Piece) throws -> Piece {
        let copy = Piece(size: piece.size)
        copy.pixels = piece.pixels
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
