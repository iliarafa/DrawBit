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
    var onLineStraighten: (_ from: (Int, Int), _ to: (Int, Int), _ justSnapped: Bool) -> Void = { _, _, _ in }
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    private let resetHaptic = UIImpactFeedbackGenerator(style: .light)

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
                gridOverlay(base: base, viewport: geo.size)

                if let rect = state.pendingMarqueeRect {
                    pendingRectOverlay(rect: rect, base: base, viewport: geo.size)
                }

                if let sel = state.selection {
                    floatingSelectionLayer(selection: sel, base: base)
                    marchingAnts(bounds: sel.displayBounds, base: base, viewport: geo.size)
                }

                CanvasHostView(
                    state: state,
                    pencilAvailability: pencilAvailability,
                    baseSize: base,
                    onStrokePoint: onStrokePoint,
                    onStrokeBegin: onStrokeBegin,
                    onStrokeEnd: onStrokeEnd,
                    onStrokeCancel: onStrokeCancel,
                    onTap: onTap,
                    onLineStraighten: onLineStraighten,
                    onUndo: onUndo,
                    onRedo: onRedo
                )

                // Contextual "reset view" chip — topmost so it's tappable above the input layer;
                // shown only when the canvas is zoomed/panned/rotated. Tapping animates back home.
                if state.isViewTransformed {
                    resetViewChip
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 48)
                        .padding(.bottom, 8)
                        .transition(UITestSupport.isRunning ? .identity : .opacity)
                }

            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .clipped()
            .animation(UITestSupport.isRunning ? nil : .easeInOut(duration: 0.2), value: state.isViewTransformed)
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

    /// The contextual reset affordance: a small pixel-styled chip that snaps the canvas back to its
    /// default zoom/pan/rotation (animated), with a light haptic. Replaces the old two-finger
    /// double-tap reset (removed so two-finger-tap undo is unambiguous).
    private var resetViewChip: some View {
        Button {
            resetHaptic.impactOccurred()
            withAnimation(UITestSupport.isRunning ? nil : .easeOut(duration: 0.25)) {
                state.resetView()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .bold))
                Text("RESET").font(.pixel(9))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Faint translucent scrim (no border, no opaque box): floats over the canvas while
            // keeping "RESET" legible over artwork. Mirrors the selection bar's de-boxed look.
            .background(Color.black.opacity(0.4))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ResetView")
        .accessibilityLabel("Reset view")
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

    /// The pixel grid, drawn directly at viewport resolution so lines stay crisp at any zoom.
    /// The line `Path` is built in canvas-local (base) points, then its points are mapped to
    /// screen space via `canvasToScreenTransform` (matching the pixel image's transform exactly),
    /// and stroked with a constant 1pt hairline — no `.scaleEffect`, so nothing is resampled.
    private func gridOverlay(base: CGSize, viewport: CGSize) -> some View {
        Canvas { ctx, _ in
            let w = state.size.width
            let h = state.size.height
            let cell = base.width / CGFloat(w)   // square cells, in base points
            let t = canvasToScreenTransform(base: base, viewport: viewport,
                                            scale: state.scale, rotation: state.rotation,
                                            translation: state.translation)

            // Interior gridlines fade out as the on-screen cell shrinks, so a zoomed-out large
            // canvas reads as dark-canvas-with-art instead of a gray wash.
            let alpha = gridLineAlpha(screenCellPoints: cell * state.scale)
            if alpha > 0.01 {
                var grid = Path()
                for i in 1..<w {                   // interior verticals (0 and w are the border)
                    let p = CGFloat(i) * cell
                    grid.move(to: CGPoint(x: p, y: 0))
                    grid.addLine(to: CGPoint(x: p, y: base.height))
                }
                for j in 1..<h {                   // interior horizontals
                    let p = CGFloat(j) * cell
                    grid.move(to: CGPoint(x: 0, y: p))
                    grid.addLine(to: CGPoint(x: base.width, y: p))
                }
                ctx.stroke(grid.applying(t), with: .color(Color(white: 0.4).opacity(alpha)), lineWidth: 1)
            }

            // Canvas border — drawn as just another grid line (same grey, same fade via `alpha`),
            // so the edge is exactly as subtle as the interior lines and never reads as a frame.
            // It fades away with the grid when zoomed right out.
            let border = Path(CGRect(x: 0, y: 0, width: base.width, height: base.height))
            ctx.stroke(border.applying(t), with: .color(Color(white: 0.4).opacity(alpha)), lineWidth: 1)
        }
        .frame(width: viewport.width, height: viewport.height)
        .allowsHitTesting(false)
    }

    private func pendingRectOverlay(rect: PixelRect, base: CGSize, viewport: CGSize) -> some View {
        Canvas { ctx, _ in
            let perPixel = base.width / CGFloat(state.size.width)
            let r = CGRect(
                x: CGFloat(rect.x) * perPixel,
                y: CGFloat(rect.y) * perPixel,
                width: CGFloat(rect.width) * perPixel,
                height: CGFloat(rect.height) * perPixel
            )
            let t = canvasToScreenTransform(base: base, viewport: viewport,
                                            scale: state.scale, rotation: state.rotation,
                                            translation: state.translation)
            ctx.stroke(Path(r).applying(t), with: .color(.white), lineWidth: 1)
        }
        .frame(width: viewport.width, height: viewport.height)
        .allowsHitTesting(false)
    }

    private func marchingAnts(bounds: PixelRect, base: CGSize, viewport: CGSize) -> some View {
        let perPixel = base.width / CGFloat(state.size.width)
        // Dash length tracks the on-screen pixel size so the ants read consistently at any zoom.
        let screenPerPixel = perPixel * state.scale
        let dashLen = max(screenPerPixel * 0.75, 2)
        let t = canvasToScreenTransform(base: base, viewport: viewport,
                                        scale: state.scale, rotation: state.rotation,
                                        translation: state.translation)
        let r = CGRect(x: CGFloat(bounds.x) * perPixel, y: CGFloat(bounds.y) * perPixel,
                       width: CGFloat(bounds.width) * perPixel, height: CGFloat(bounds.height) * perPixel)
        let path = Path(r).applying(t)

        func drawAnts(_ ctx: GraphicsContext, phase: CGFloat) {
            ctx.stroke(path, with: .color(.black.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1, dash: [dashLen, dashLen], dashPhase: phase))
            ctx.stroke(path, with: .color(.white),
                       style: StrokeStyle(lineWidth: 1, dash: [dashLen, dashLen], dashPhase: phase + dashLen))
        }

        return Group {
            if UITestSupport.isRunning {
                // Static dashes under UI test: a live TimelineView(.animation) never idles, which
                // wedges XCUITest's automatic synchronization permanently (see CLAUDE.md test
                // conventions — same reason every other animation is gated here).
                Canvas { ctx, _ in drawAnts(ctx, phase: 0) }
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, _ in
                        let elapsed = timeline.date.timeIntervalSinceReferenceDate
                        let phase = elapsed.truncatingRemainder(dividingBy: 1.0) * Double(dashLen * 2)
                        drawAnts(ctx, phase: CGFloat(phase))
                    }
                }
            }
        }
        .frame(width: viewport.width, height: viewport.height)
        .allowsHitTesting(false)
    }
}
