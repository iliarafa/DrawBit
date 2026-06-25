import SwiftUI
import UIKit
import CoreGraphics

/// Renders the pixel grid as a crisp Image on a transparent background, with a medium-grey
/// grid overlay outlining each pixel cell, and hosts the input layer.
/// Uses Image(uiImage:).interpolation(.none).antialiased(false) so pixels stay sharp at any
/// zoom / rotation — Image.interpolation propagates through .scaleEffect/.rotationEffect.
/// Memoizes the composited previous-frame UIImage used by onion-skin so
/// `Compositor.composite` doesn't re-run on every SwiftUI body pass (it walks
/// every visible layer's pixel buffer; ~16 MB at 256²×16-layers per call).
///
/// Cache key is the previous frame's full value, compared via `Frame ==`. A
/// `Frame.id`-only key would miss cases where the user undoes/redoes a stroke
/// on the previous frame: `Frame.id` is `let`, so it stays equal while the
/// layer pixel data underneath changes — the cached image would go stale.
/// Value equality fixes that: any pixel change to the previous frame's layers
/// flips the equality and forces a recomposite.
///
/// Cost: each body pass with onion skin on runs a `Frame ==` (byte compare of
/// every layer's pixel `Data`). For a worst-case 16-layer × 128² frame that's
/// ~1 MiB of byte compare — meaningfully cheaper than the alternative
/// `Compositor.composite` walk (~3 MiB with conditional copies + alpha checks),
/// and a fast-path on `Frame.id` (cached id != incoming id → immediate miss)
/// keeps the cross-frame case essentially free.
///
/// Class (not `@State` value) so internal `var` mutations from within view body
/// don't trip SwiftUI's "modifying state during view update" rule. SwiftUI tracks
/// the reference identity, not the class's internal vars.
private final class OnionSkinCache {
    private var cachedFrame: Frame?
    private var cachedImage: UIImage?

    func image(for frame: Frame, size: CanvasSize) -> UIImage? {
        // Fast-path: different frame.id can't be a cache hit no matter what.
        if let cached = cachedFrame, cached.id == frame.id, cached == frame,
           let cachedImage {
            return cachedImage
        }
        let buffer = Compositor.composite(frame, size: size)
        guard let cg = bufferToCGImage(buffer) else { return nil }
        let img = UIImage(cgImage: cg)
        cachedFrame = frame
        cachedImage = img
        return img
    }

    func invalidate() {
        cachedFrame = nil
        cachedImage = nil
    }
}

struct CanvasView: View {
    let state: EditorState
    let pencilAvailability: PencilAvailability

    var onStrokePoint: (Int, Int) -> Void = { _, _ in }
    var onStrokeBegin: () -> Void = {}
    var onStrokeEnd: () -> Void = {}

    @State private var onionCache = OnionSkinCache()
    var onStrokeCancel: () -> Void = {}
    var onTap: (Int, Int) -> Void = { _, _ in }

    var body: some View {
        GeometryReader { geo in
            let base = baseSize(in: geo)
            ZStack {
                if state.isReferenceVisible,
                   !state.isPlaying,
                   let reference = state.referenceImage {
                    Image(uiImage: reference)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: base.width, height: base.height)
                        .opacity(state.referenceOpacity)
                        .scaleEffect(state.scale)
                        .rotationEffect(.radians(state.rotation))
                        .offset(state.translation)
                        .allowsHitTesting(false)
                }
                if state.isOnionSkinEnabled,
                   !state.isPlaying,
                   state.activeFrameIndex > 0,
                   let ghost = previousFrameImage() {
                    Image(uiImage: ghost)
                        .resizable()
                        .interpolation(.none)
                        .antialiased(false)
                        .frame(width: base.width, height: base.height)
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
                        .frame(width: base.width, height: base.height)
                        .scaleEffect(state.scale)
                        .rotationEffect(.radians(state.rotation))
                        .offset(state.translation)
                }
                Canvas { ctx, size in
                    let w = state.size.width
                    let h = state.size.height
                    let cell = size.width / CGFloat(w)   // square cells
                    var path = Path()
                    for i in 0...w {                       // vertical gridlines
                        let p = CGFloat(i) * cell
                        path.move(to: CGPoint(x: p, y: 0))
                        path.addLine(to: CGPoint(x: p, y: size.height))
                    }
                    for j in 0...h {                       // horizontal gridlines
                        let p = CGFloat(j) * cell
                        path.move(to: CGPoint(x: 0, y: p))
                        path.addLine(to: CGPoint(x: size.width, y: p))
                    }
                    ctx.stroke(path, with: .color(Color(white: 0.4)), lineWidth: max(0.5 / state.scale, 0.1))
                }
                .frame(width: base.width, height: base.height)
                .scaleEffect(state.scale)
                .rotationEffect(.radians(state.rotation))
                .offset(state.translation)
                .allowsHitTesting(false)

                if let rect = state.pendingMarqueeRect {
                    pendingRectOverlay(rect: rect, base: base)
                }

                if let sel = state.selection {
                    floatingSelectionLayer(selection: sel, base: base)
                    marchingAnts(bounds: sel.displayBounds, base: base)
                }

                CanvasHostView(
                    state: state,
                    pencilAvailability: pencilAvailability,
                    baseSize: base,
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
        .onChange(of: state.activeFrameIndex) { _, _ in
            // Onion-skin cache holds the composited previous-frame UIImage keyed
            // on Frame.id only; switching active frames may bring us back to a
            // previously-cached frame whose pixels have since changed, so
            // invalidate eagerly on every active-frame transition.
            onionCache.invalidate()
        }
    }

    /// Canvas display size at scale=1 in points. One square `perPixel` (integer points per
    /// canvas pixel) governs both axes, so a non-square canvas keeps true proportions and
    /// crisp 1× presentation; the perPixel is sized off the LONGEST edge so the whole canvas
    /// fits the available area. Square → width == height (unchanged behavior).
    private func baseSize(in geo: GeometryProxy) -> CGSize {
        let m = Swift.min(geo.size.width, geo.size.height) * 0.85
        let perPixel = max(floor(m / CGFloat(state.size.longestEdge)), 1)
        return CGSize(width: perPixel * CGFloat(state.size.width),
                      height: perPixel * CGFloat(state.size.height))
    }

    /// Raw pixel data wrapped as a UIImage at canvas native resolution. Transparent where
    /// pixels are unset; grid outlines are drawn separately in SwiftUI at display resolution.
    private func pixelImage() -> UIImage? {
        let buffer = Compositor.composite(state.frame, size: state.size)
        guard let cg = bufferToCGImage(buffer) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Composite of the frame immediately before the active one, used as the onion-skin
    /// ghost. Returns nil if no previous frame exists. Result is memoized by
    /// `OnionSkinCache` keyed on `frame.id` — the previous frame's composite doesn't
    /// change during a stroke on the active frame, so the per-body-pass compositor
    /// walk is wasted work. See `OnionSkinCache` for the cache contract and its
    /// accepted staleness window.
    private func previousFrameImage() -> UIImage? {
        let idx = state.activeFrameIndex - 1
        guard idx >= 0, idx < state.frames.count else { return nil }
        return onionCache.image(for: state.frames[idx], size: state.size)
    }

    private func selectionImage(_ sel: MarqueeSelection) -> UIImage? {
        let buffer = CompositedBuffer(data: sel.extracted.pixels.data, size: sel.extracted.pixels.size)
        guard let cg = bufferToCGImage(buffer) else { return nil }
        return UIImage(cgImage: cg)
    }

    @ViewBuilder
    private func floatingSelectionLayer(selection sel: MarqueeSelection, base: CGSize) -> some View {
        if let image = selectionImage(sel) {
            let perPixel = base.width / CGFloat(state.size.width)
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .frame(width: base.width, height: base.height)
                .offset(x: CGFloat(sel.dragOffset.dx) * perPixel,
                        y: CGFloat(sel.dragOffset.dy) * perPixel)
                .scaleEffect(state.scale)
                .rotationEffect(.radians(state.rotation))
                .offset(state.translation)
                .allowsHitTesting(false)
        }
    }

    private func pendingRectOverlay(rect: PixelRect, base: CGSize) -> some View {
        Canvas { ctx, size in
            let perPixel = size.width / CGFloat(state.size.width)
            let r = CGRect(
                x: CGFloat(rect.x) * perPixel,
                y: CGFloat(rect.y) * perPixel,
                width: CGFloat(rect.width) * perPixel,
                height: CGFloat(rect.height) * perPixel
            )
            ctx.stroke(Path(r), with: .color(.white), lineWidth: max(1.0 / state.scale, 0.25))
        }
        .frame(width: base.width, height: base.height)
        .scaleEffect(state.scale)
        .rotationEffect(.radians(state.rotation))
        .offset(state.translation)
        .allowsHitTesting(false)
    }

    private func marchingAnts(bounds: PixelRect, base: CGSize) -> some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let perPixel = size.width / CGFloat(state.size.width)
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
        .frame(width: base.width, height: base.height)
        .scaleEffect(state.scale)
        .rotationEffect(.radians(state.rotation))
        .offset(state.translation)
        .allowsHitTesting(false)
    }
}
