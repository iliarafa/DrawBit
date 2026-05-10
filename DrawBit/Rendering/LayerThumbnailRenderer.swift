import CoreGraphics
import Foundation

/// Per-layer panel thumbnail. Wraps the layer's raw bytes in a one-layer Frame and
/// runs the standard ThumbnailRenderer so transparent areas are correctly transparent.
enum LayerThumbnailRenderer {
    static func render(layer: Layer, size: CanvasSize, targetEdge: Int) -> Data? {
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        return ThumbnailRenderer.render(frame: frame, size: size, targetEdge: targetEdge)
    }

    /// Direct-CGImage variant. UI hot paths should prefer this and wrap with
    /// `UIImage(cgImage:)` rather than `UIImage(data:)`.
    static func renderCGImage(layer: Layer, size: CanvasSize, targetEdge: Int) -> CGImage? {
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        return ThumbnailRenderer.renderCGImage(frame: frame, size: size, targetEdge: targetEdge)
    }
}
