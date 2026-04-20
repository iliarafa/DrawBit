import Foundation
import Observation

@Observable
final class EditorState {
    let pieceID: UUID
    var grid: PixelGrid
    var tool: Tool = .pencil
    var color: RGBA = RGBA(r: 255, g: 255, b: 255, a: 255)

    // View transform (rotation in radians). Rotation is view-only, not persisted.
    var translation: CGSize = .zero
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0

    private var undoStack: [Data] = []
    private var redoStack: [Data] = []
    private var preStrokeSnapshot: Data?

    private let undoLimit = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(piece: Piece) {
        self.pieceID = piece.id
        self.grid = PixelGrid(data: piece.pixels, size: piece.size)
    }

    func beginStrokeSnapshot() {
        preStrokeSnapshot = grid.data
    }

    func commitStroke() {
        guard let snap = preStrokeSnapshot else { return }
        undoStack.append(snap)
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
        redoStack.removeAll()
        preStrokeSnapshot = nil
    }

    func cancelStroke() {
        if let snap = preStrokeSnapshot {
            grid = PixelGrid(data: snap, size: grid.size)
        }
        preStrokeSnapshot = nil
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(grid.data)
        grid = PixelGrid(data: previous, size: grid.size)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(grid.data)
        grid = PixelGrid(data: next, size: grid.size)
    }
}
