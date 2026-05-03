import Foundation

/// Per-layer panel thumbnail. Wraps the layer's raw bytes in a one-layer Frame and
/// runs the standard ThumbnailRenderer so transparent areas are correctly transparent.
enum LayerThumbnailRenderer {
    static func render(layer: Layer, size: CanvasSize, targetEdge: Int) -> Data? {
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        return ThumbnailRenderer.render(frame: frame, size: size, targetEdge: targetEdge)
    }
}
