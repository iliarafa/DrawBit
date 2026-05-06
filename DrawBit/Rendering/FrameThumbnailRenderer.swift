import Foundation

/// Composites every visible layer of a Frame and produces a small PNG suitable for
/// the timeline strip. This is a thin shim over `ThumbnailRenderer` — the existing
/// gallery thumbnail renderer — kept as a separately-named type to make timeline-
/// strip call sites self-documenting.
enum FrameThumbnailRenderer {
    static func render(frame: Frame, size: CanvasSize, targetEdge: Int) -> Data? {
        guard targetEdge >= 1 else { return nil }
        return ThumbnailRenderer.render(frame: frame, size: size, targetEdge: targetEdge)
    }
}
