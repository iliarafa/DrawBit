import SwiftUI
import UIKit
import CoreGraphics

/// Renders the pixel grid as a crisp Image on a transparent background, with a medium-grey
/// grid overlay outlining each pixel cell, and hosts the input layer.
/// Uses Image(uiImage:).interpolation(.none).antialiased(false) so pixels stay sharp at any
/// zoom / rotation — Image.interpolation propagates through .scaleEffect/.rotationEffect.
struct CanvasView: View {
    let state: EditorState
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
                if state.isOnionSkinEnabled,
                   !state.isPlaying,
                   state.activeFrameIndex > 0,
                   let ghost = previousFrameImage() {
                    Image(uiImage: ghost)
                        .resizable()
                        .interpolation(.none)
                        .antialiased(false)
                        .frame(width: edge, height: edge)
                        .opacity(0.3)
                        .scaleEffect(state.scale)
                        .rotationEffect(.radians(state.rotation))
                        .offset(state.translation)
                        .allowsHitTesting(false)
                }
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
                    let dim = state.size.dimension
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

                if let rect = state.pendingMarqueeRect {
                    pendingRectOverlay(rect: rect, edge: edge)
                }

                if let sel = state.selection {
                    floatingSelectionLayer(selection: sel, edge: edge)
                    marchingAnts(bounds: sel.displayBounds, edge: edge)
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
        .accessibilityIdentifier("Canvas")
    }

    /// Canvas edge length at scale=1 in points. Integer multiple of `dimension` so each canvas
    /// pixel maps to an integer number of screen points for crisp 1× presentation.
    private func baseEdge(in geo: GeometryProxy) -> CGFloat {
        let m = Swift.min(geo.size.width, geo.size.height) * 0.85
        let dim = CGFloat(state.size.dimension)
        let perPixel = floor(m / dim)
        return max(perPixel, 1) * dim
    }

    /// Raw pixel data wrapped as a UIImage at canvas native resolution. Transparent where
    /// pixels are unset; grid outlines are drawn separately in SwiftUI at display resolution.
    private func pixelImage() -> UIImage? {
        let buffer = Compositor.composite(state.frame, size: state.size)
        guard let cg = bufferToCGImage(buffer) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Composite of the frame immediately before the active one, used as the onion-skin
    /// ghost. Returns nil if no previous frame exists. Recomputed every layout pass —
    /// the compositor walks every visible layer of the previous frame, so worst-case
    /// (256×256 × 16 visible layers, ~4 MB byte scan) at 60 fps drag is ~240 MB/s of
    /// scanning that ALWAYS produces the same bytes during a stroke on the active
    /// frame. Fine on M-series iPads, marginal on A12-class hardware. A frame-content
    /// memoization keyed on activeFrameIndex changes would eliminate the per-stroke
    /// cost; deferred to a Stage 5 follow-up since the simple `@State` cache pattern
    /// trips SwiftUI's "modifying state during view update" rule and a clean fix
    /// requires lifting the cache to a small helper class.
    private func previousFrameImage() -> UIImage? {
        let idx = state.activeFrameIndex - 1
        guard idx >= 0, idx < state.frames.count else { return nil }
        let buffer = Compositor.composite(state.frames[idx], size: state.size)
        guard let cg = bufferToCGImage(buffer) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func selectionImage(_ sel: MarqueeSelection) -> UIImage? {
        let buffer = CompositedBuffer(data: sel.extracted.pixels.data, size: sel.extracted.pixels.size)
        guard let cg = bufferToCGImage(buffer) else { return nil }
        return UIImage(cgImage: cg)
    }

    @ViewBuilder
    private func floatingSelectionLayer(selection sel: MarqueeSelection, edge: CGFloat) -> some View {
        if let image = selectionImage(sel) {
            let perPixel = edge / CGFloat(state.size.dimension)
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .frame(width: edge, height: edge)
                .offset(x: CGFloat(sel.dragOffset.dx) * perPixel,
                        y: CGFloat(sel.dragOffset.dy) * perPixel)
                .scaleEffect(state.scale)
                .rotationEffect(.radians(state.rotation))
                .offset(state.translation)
                .allowsHitTesting(false)
        }
    }

    private func pendingRectOverlay(rect: PixelRect, edge: CGFloat) -> some View {
        Canvas { ctx, size in
            let perPixel = size.width / CGFloat(state.size.dimension)
            let r = CGRect(
                x: CGFloat(rect.x) * perPixel,
                y: CGFloat(rect.y) * perPixel,
                width: CGFloat(rect.width) * perPixel,
                height: CGFloat(rect.height) * perPixel
            )
            ctx.stroke(Path(r), with: .color(.white), lineWidth: max(1.0 / state.scale, 0.25))
        }
        .frame(width: edge, height: edge)
        .scaleEffect(state.scale)
        .rotationEffect(.radians(state.rotation))
        .offset(state.translation)
        .allowsHitTesting(false)
    }

    private func marchingAnts(bounds: PixelRect, edge: CGFloat) -> some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let perPixel = size.width / CGFloat(state.size.dimension)
                let r = CGRect(
                    x: CGFloat(bounds.x) * perPixel,
                    y: CGFloat(bounds.y) * perPixel,
                    width: CGFloat(bounds.width) * perPixel,
                    height: CGFloat(bounds.height) * perPixel
                )
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let phase = elapsed.truncatingRemainder(dividingBy: 1.0) * Double(perPixel * 2)
                let dashLen = perPixel * 0.75
                let style = StrokeStyle(
                    lineWidth: max(1.0 / state.scale, 0.25),
                    dash: [dashLen, dashLen],
                    dashPhase: CGFloat(phase)
                )
                let path = Path(r)
                ctx.stroke(path, with: .color(.black.opacity(0.85)), style: style)
                ctx.stroke(path, with: .color(.white),
                           style: StrokeStyle(
                            lineWidth: max(1.0 / state.scale, 0.25),
                            dash: [dashLen, dashLen],
                            dashPhase: CGFloat(phase) + dashLen))
            }
        }
        .frame(width: edge, height: edge)
        .scaleEffect(state.scale)
        .rotationEffect(.radians(state.rotation))
        .offset(state.translation)
        .allowsHitTesting(false)
    }
}
