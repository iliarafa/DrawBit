import Foundation

/// Composites every visible layer of a Frame and produces a small PNG suitable for
/// the timeline strip. Thin shim over `ThumbnailRenderer`, kept as a separately-named
/// type so timeline-strip call sites are self-documenting.
enum FrameThumbnailRenderer {
    static func render(frame: Frame, size: CanvasSize, targetEdge: Int) -> Data? {
        ThumbnailRenderer.render(frame: frame, size: size, targetEdge: targetEdge)
    }
}
