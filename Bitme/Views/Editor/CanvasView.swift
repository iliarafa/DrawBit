import SwiftUI
import UIKit
import CoreGraphics

/// Renders the pixel grid as a crisp Image + a checkered background, and hosts the input layer.
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
                if let image = composedImage() {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .antialiased(false)
                        .frame(width: edge, height: edge)
                        .scaleEffect(state.scale)
                        .rotationEffect(.radians(state.rotation))
                        .offset(state.translation)
                }
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

    /// Composite checkerboard + pixel data into a single UIImage at canvas native resolution.
    private func composedImage() -> UIImage? {
        let dim = state.grid.dimension
        guard let pixels = pixelsToCGImage(state.grid) else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(
            data: nil,
            width: dim,
            height: dim,
            bitsPerComponent: 8,
            bytesPerRow: dim * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)

        // Checkerboard (2-pixel tiles). Fill the full canvas first, then overlay pixels.
        let tile = 2
        for y in stride(from: 0, to: dim, by: tile) {
            for x in stride(from: 0, to: dim, by: tile) {
                let isDark = ((x / tile) + (y / tile)) % 2 == 0
                ctx.setFillColor(UIColor(white: isDark ? 0.72 : 0.88, alpha: 1).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: tile, height: tile))
            }
        }
        ctx.draw(pixels, in: CGRect(x: 0, y: 0, width: dim, height: dim))

        // Grid overlay: only when zoomed in enough that grid lines read as visible hairlines.
        if state.scale >= 4 {
            ctx.setStrokeColor(UIColor(white: 0, alpha: 0.35).cgColor)
            ctx.setLineWidth(max(1.0 / state.scale, 0.1))
            for i in 1..<dim {
                let p = CGFloat(i)
                ctx.move(to: CGPoint(x: p, y: 0))
                ctx.addLine(to: CGPoint(x: p, y: CGFloat(dim)))
                ctx.move(to: CGPoint(x: 0, y: p))
                ctx.addLine(to: CGPoint(x: CGFloat(dim), y: p))
            }
            ctx.strokePath()
        }

        guard let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }
}
