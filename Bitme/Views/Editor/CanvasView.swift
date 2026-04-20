import SwiftUI
import UIKit
import CoreGraphics

/// Renders the pixel grid as a crisp Image on a transparent background, with a medium-grey
/// grid overlay outlining each pixel cell, and hosts the input layer.
/// Uses Image(uiImage:).interpolation(.none).antialiased(false) so pixels stay sharp at any
/// zoom / rotation — Image.interpolation propagates through .scaleEffect/.rotationEffect.
struct CanvasView: View {
    @Bindable var state: EditorState
    let pencilAvailability: PencilAvailability

    var onStrokePoint: (Int, Int) -> Void = { _, _ in }
    var onStrokeBegin: () -> Void = {}
    var onStrokeEnd: () -> Void = {}
    var onStrokeCancel: () -> Void = {}
    var onTap: (Int, Int) -> Void = { _, _ in }

    var body: some View {
        GeometryReader { geo in
            let edge = baseEdge(in: geo)
            ZStack {
                if let image = pixelImage() {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .antialiased(false)
                        .frame(width: edge, height: edge)
                        .scaleEffect(state.scale)
                        .rotationEffect(.radians(state.rotation))
                        .offset(state.translation)
                }
                Canvas { ctx, size in
                    let dim = state.grid.dimension
                    let cell = size.width / CGFloat(dim)
                    var path = Path()
                    for i in 0...dim {
                        let p = CGFloat(i) * cell
                        path.move(to: CGPoint(x: p, y: 0))
                        path.addLine(to: CGPoint(x: p, y: size.height))
                        path.move(to: CGPoint(x: 0, y: p))
                        path.addLine(to: CGPoint(x: size.width, y: p))
                    }
                    ctx.stroke(path, with: .color(Color(white: 0.4)), lineWidth: max(0.5 / state.scale, 0.1))
                }
                .frame(width: edge, height: edge)
                .scaleEffect(state.scale)
                .rotationEffect(.radians(state.rotation))
                .offset(state.translation)
                .allowsHitTesting(false)
                CanvasHostView(
                    state: state,
                    pencilAvailability: pencilAvailability,
                    baseEdge: edge,
                    onStrokePoint: onStrokePoint,
                    onStrokeBegin: onStrokeBegin,
                    onStrokeEnd: onStrokeEnd,
                    onStrokeCancel: onStrokeCancel,
                    onTap: onTap
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .clipped()
        }
    }

    /// Canvas edge length at scale=1 in points. Integer multiple of `dimension` so each canvas
    /// pixel maps to an integer number of screen points for crisp 1× presentation.
    private func baseEdge(in geo: GeometryProxy) -> CGFloat {
        let m = Swift.min(geo.size.width, geo.size.height) * 0.85
        let dim = CGFloat(state.grid.dimension)
        let perPixel = floor(m / dim)
        return max(perPixel, 1) * dim
    }

    /// Raw pixel data wrapped as a UIImage at canvas native resolution. Transparent where
    /// pixels are unset; grid outlines are drawn separately in SwiftUI at display resolution.
    private func pixelImage() -> UIImage? {
        guard let cg = pixelsToCGImage(state.grid) else { return nil }
        return UIImage(cgImage: cg)
    }
}
