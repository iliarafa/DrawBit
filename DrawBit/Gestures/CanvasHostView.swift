import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct CanvasHostView: UIViewRepresentable {
    let state: EditorState
    var pencilAvailability: PencilAvailability
    var baseSize: CGSize
    var onStrokePoint: (Int, Int) -> Void
    var onStrokeBegin: () -> Void
    var onStrokeEnd: () -> Void
    var onStrokeCancel: () -> Void
    var onTap: (Int, Int) -> Void
    /// Pencil "hold to straighten": fired when the freehand stroke snaps to a straight line and on
    /// each subsequent re-aim. `justSnapped` is true only on the first (lock) event.
    var onLineStraighten: (_ from: (Int, Int), _ to: (Int, Int), _ justSnapped: Bool) -> Void = { _, _, _ in }
    var onUndo: () -> Void = {}   // two-finger tap
    var onRedo: () -> Void = {}   // three-finger tap

    func makeUIView(context: Context) -> CanvasInputView {
        let v = CanvasInputView()
        v.configure(state: state, pencilAvailability: pencilAvailability, baseSize: baseSize)
        v.onStrokePoint = onStrokePoint
        v.onStrokeBegin = onStrokeBegin
        v.onStrokeEnd = onStrokeEnd
        v.onStrokeCancel = onStrokeCancel
        v.onTap = onTap
        v.onLineStraighten = onLineStraighten
        v.onUndo = onUndo
        v.onRedo = onRedo
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: CanvasInputView, context: Context) {
        uiView.configure(state: state, pencilAvailability: pencilAvailability, baseSize: baseSize)
    }
}

final class CanvasInputView: UIView {
    var state: EditorState?
    var pencilAvailability: PencilAvailability?
    var baseSize: CGSize = .zero
    var onStrokePoint: ((Int, Int) -> Void)?
    var onStrokeBegin: (() -> Void)?
    var onStrokeEnd: (() -> Void)?
    var onStrokeCancel: (() -> Void)?
    var onTap: ((Int, Int) -> Void)?
    var onLineStraighten: ((_ from: (Int, Int), _ to: (Int, Int), _ justSnapped: Bool) -> Void)?
    var onUndo: (() -> Void)?   // two-finger tap
    var onRedo: (() -> Void)?   // three-finger tap

    private var strokeInProgress = false
    private var lastPixel: (Int, Int)?
    private var didMove = false

    // MARK: - Pencil "hold to straighten" (QuickLine)
    /// Pixel under the touch-down — the line's fixed start. Only set for the pencil tool.
    private var lineAnchor: (Int, Int)?
    /// Once true, the stroke has snapped to a straight line; freehand emission stops and moves re-aim.
    private var lineMode = false
    /// Latest pixel/screen position of the active touch, used by the dwell timer and re-aim.
    private var lastTouchPixel: (Int, Int)?
    private var lastTouchLocation: CGPoint?
    /// Screen anchor for stillness: the dwell timer is rescheduled only when the finger moves beyond
    /// `dwellRadius` of this point, so holding still lets it fire.
    private var dwellOrigin: CGPoint?
    private var dwellWorkItem: DispatchWorkItem?
    private let dwellDuration: TimeInterval = 0.5
    private let dwellRadius: CGFloat = 10

    func configure(state: EditorState, pencilAvailability: PencilAvailability, baseSize: CGSize) {
        self.state = state
        self.pencilAvailability = pencilAvailability
        self.baseSize = baseSize
        isMultipleTouchEnabled = true
        installRecognizersIfNeeded()
    }

    private func installRecognizersIfNeeded() {
        guard gestureRecognizers?.isEmpty ?? true else { return }
        let xform = TwoFingerTransformGestureRecognizer(target: self, action: #selector(handleTransform(_:)))
        xform.delegate = self
        addGestureRecognizer(xform)
        // Two-finger tap = undo, three-finger tap = redo (iPad/Procreate convention). No double-tap
        // gesture exists anymore, so the two-finger single tap fires instantly (no require-toFail
        // wait) and rapid two-finger taps undo repeatedly. They recognize simultaneously with the
        // transform recognizer (delegate returns true); a two-finger *drag* fails the tap → pan/zoom.
        let undoTap = UITapGestureRecognizer(target: self, action: #selector(handleUndoTap))
        undoTap.numberOfTapsRequired = 1
        undoTap.numberOfTouchesRequired = 2
        undoTap.delegate = self
        addGestureRecognizer(undoTap)
        let redoTap = UITapGestureRecognizer(target: self, action: #selector(handleRedoTap))
        redoTap.numberOfTapsRequired = 1
        redoTap.numberOfTouchesRequired = 3
        redoTap.delegate = self
        addGestureRecognizer(redoTap)
    }

    @objc private func handleUndoTap() { onUndo?() }
    @objc private func handleRedoTap() { onRedo?() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state else { return }
        if let pencil = touches.first(where: { $0.type == .pencil }) {
            pencilAvailability?.updateFromTouch(pencil)
            beginStrokeIfDrawable(touch: pencil)
            return
        }
        if pencilAvailability?.isPencilAvailable == true {
            // Pencil is available — finger input is treated as pan/zoom; do not draw.
            return
        }
        if let touch = touches.first, touches.count == 1 {
            beginStrokeIfDrawable(touch: touch)
        }
        _ = state
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard strokeInProgress, let event else { return }
        let drawingTouches = touches.filter { shouldDraw(with: $0) }

        // Line mode: the stroke has snapped straight — moves re-aim the endpoint, no freehand.
        if lineMode {
            if let touch = drawingTouches.first, let p = pixelCoord(for: touch), let anchor = lineAnchor {
                lastTouchPixel = p
                onLineStraighten?(anchor, p, false)
            }
            return
        }

        for touch in drawingTouches {
            let coalesced = event.coalescedTouches(for: touch) ?? [touch]
            for t in coalesced {
                if let p = pixelCoord(for: t) {
                    if let last = lastPixel, (last.0 != p.0 || last.1 != p.1) {
                        for pt in bresenhamLine(from: last, to: p) {
                            onStrokePoint?(pt.0, pt.1)
                        }
                        didMove = true
                    } else if lastPixel == nil {
                        onStrokePoint?(p.0, p.1)
                    }
                    lastPixel = p
                }
            }
            lastTouchPixel = pixelCoord(for: touch)
        }

        // Drive the hold-to-straighten dwell timer (pencil only, and only once the stroke has
        // actually drawn something — so a plain tap/hold never snaps). The timer is rescheduled
        // when the finger moves beyond `dwellRadius`; holding still lets it fire → snapToLine().
        if isLineEligible, didMove, let touch = drawingTouches.first {
            let loc = touch.location(in: self)
            lastTouchLocation = loc
            if let origin = dwellOrigin, hypot(loc.x - origin.x, loc.y - origin.y) <= dwellRadius {
                // Still within the stillness radius — keep the running timer.
            } else {
                dwellOrigin = loc
                scheduleDwell()
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard strokeInProgress else { return }
        // A snapped line commits like any stroke (its pixels are already drawn); never a tap.
        if !lineMode, !didMove, let first = touches.first, let p = pixelCoord(for: first) {
            // Pure tap: emit a single-point paint via onTap.
            strokeInProgress = false
            lastPixel = nil
            didMove = false
            resetLineState()
            onTap?(p.0, p.1)
            return
        }
        strokeInProgress = false
        lastPixel = nil
        didMove = false
        resetLineState()
        onStrokeEnd?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard strokeInProgress else { return }
        strokeInProgress = false
        lastPixel = nil
        didMove = false
        resetLineState()
        onStrokeCancel?()
    }

    private func shouldDraw(with touch: UITouch) -> Bool {
        if pencilAvailability?.isPencilAvailable == true {
            return touch.type == .pencil
        }
        return true
    }

    private func beginStrokeIfDrawable(touch: UITouch) {
        guard shouldDraw(with: touch) else { return }
        strokeInProgress = true
        lastPixel = nil
        didMove = false
        resetLineState()
        // Capture the line's fixed start (pencil only). The anchor is the touch-down pixel so the
        // line is well-defined even before the first freehand point is emitted.
        if isLineEligible { lineAnchor = pixelCoord(for: touch) }
        onStrokeBegin?()
    }

    /// Hold-to-straighten is pencil-only in v1.
    private var isLineEligible: Bool { state?.tool == .pencil }

    private func resetLineState() {
        lineAnchor = nil
        lineMode = false
        lastTouchPixel = nil
        lastTouchLocation = nil
        dwellOrigin = nil
        dwellWorkItem?.cancel()
        dwellWorkItem = nil
    }

    /// (Re)arm the dwell timer from the current finger position. Fires after `dwellDuration` of
    /// stillness → snap to a straight line.
    private func scheduleDwell() {
        dwellWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.snapToLine() }
        dwellWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dwellDuration, execute: work)
    }

    private func snapToLine() {
        guard strokeInProgress, !lineMode, let anchor = lineAnchor, let end = lastTouchPixel else { return }
        lineMode = true
        onLineStraighten?(anchor, end, true)
    }

    // MARK: - Two-finger transform gestures

    private var gestureStartTranslation: CGSize?
    private var gestureStartScale: CGFloat?
    private var gestureStartRotation: CGFloat?

    @objc private func handleTransform(_ g: TwoFingerTransformGestureRecognizer) {
        guard let state else { return }
        switch g.state {
        case .began:
            cancelStrokeIfAny()
            gestureStartTranslation = state.translation
            gestureStartScale = state.scale
            gestureStartRotation = state.rotation
        case .changed:
            guard let t0 = gestureStartTranslation,
                  let s0 = gestureStartScale,
                  let r0 = gestureStartRotation else { return }
            state.translation = CGSize(
                width: t0.width + g.cumulativeTranslation.x,
                height: t0.height + g.cumulativeTranslation.y
            )
            state.scale = max(0.25, min(40, s0 * g.cumulativeScale))
            var next = r0 + g.cumulativeRotation
            // Snap to 0 within ~4° to make straightening back up easy.
            if abs(next) < 0.0698 { next = 0 }
            state.rotation = next
        case .ended, .cancelled, .failed:
            gestureStartTranslation = nil
            gestureStartScale = nil
            gestureStartRotation = nil
        default:
            break
        }
    }

    private func cancelStrokeIfAny() {
        guard strokeInProgress else { return }
        strokeInProgress = false
        lastPixel = nil
        didMove = false
        resetLineState()
        onStrokeCancel?()
    }

    // MARK: - Touch → pixel mapping

    /// Convert a UITouch in view coords to an integer pixel in the grid, accounting for the
    /// current editor transform (translation, scale, rotation). Returns nil if out of canvas.
    private func pixelCoord(for touch: UITouch) -> (Int, Int)? {
        guard let state else { return nil }
        let cw = CGFloat(state.size.width)
        let ch = CGFloat(state.size.height)
        let size = bounds.size
        guard baseSize.width > 0, baseSize.height > 0, cw > 0, ch > 0, state.scale > 0 else { return nil }

        let p = touch.location(in: self)
        // Step 1: recenter so canvas center is at origin (canvas is drawn centered, then translated).
        let centered = CGPoint(
            x: p.x - size.width / 2 - state.translation.width,
            y: p.y - size.height / 2 - state.translation.height
        )
        // Step 2: un-rotate.
        let cosR = Foundation.cos(-state.rotation)
        let sinR = Foundation.sin(-state.rotation)
        let rotated = CGPoint(x: centered.x * cosR - centered.y * sinR,
                              y: centered.x * sinR + centered.y * cosR)
        // Step 3: un-scale to canvas-local centered coords (-baseSize/2 … baseSize/2).
        let local = CGPoint(x: rotated.x / state.scale, y: rotated.y / state.scale)
        // Step 4: shift to canvas-local top-left coords (0 … baseSize), per axis.
        let canvasLocal = CGPoint(x: local.x + baseSize.width / 2, y: local.y + baseSize.height / 2)
        // Step 5: integer pixel index. perPixel is square (same on both axes).
        let perPixel = baseSize.width / cw
        let ix = Int(floor(canvasLocal.x / perPixel))
        let iy = Int(floor(canvasLocal.y / perPixel))
        guard ix >= 0, iy >= 0, ix < Int(cw), iy < Int(ch) else { return nil }
        return (ix, iy)
    }
}

extension CanvasInputView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Custom two-finger transform recognizer. Replaces the trio of UIPanGestureRecognizer +
/// UIPinchGestureRecognizer + UIRotationGestureRecognizer because each of those has its own
/// internal activation threshold and they race for the touches, producing inconsistent
/// "sometimes responds, sometimes doesn't" behavior. This recognizer enters `.began` the
/// moment the second finger lands so all three transforms respond from frame one.
///
/// Exposes cumulative values *relative to the gesture's start*, not per-frame deltas. That's
/// what kills the zoom-leaking-into-rotation drift: hand wobble can't compound across frames
/// when each frame is computed against a fixed baseline.
final class TwoFingerTransformGestureRecognizer: UIGestureRecognizer {
    /// Distance ratio relative to baseline finger spacing. 1.0 means no zoom from start.
    private(set) var cumulativeScale: CGFloat = 1.0
    /// Angle in radians relative to baseline finger angle. Normalized to (-π, π].
    private(set) var cumulativeRotation: CGFloat = 0.0
    /// Midpoint shift in view points relative to baseline finger midpoint.
    private(set) var cumulativeTranslation: CGPoint = .zero

    private var tracked: [UITouch] = []
    private var baselineDistance: CGFloat = 1
    private var baselineAngle: CGFloat = 0
    private var baselineMidpoint: CGPoint = .zero
    private var hasBaseline = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        // Single-touch draws must reach the view immediately. Without this, the view's
        // touchesEnded is held back while we sit in .possible, so onStrokeEnd never fires
        // and the undo button stays disabled. cancelsTouchesInView (default true) still
        // cancels the stroke when we recognize a 2-finger gesture.
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        for t in touches where tracked.count < 2 { tracked.append(t) }
        if tracked.count == 2, !hasBaseline, let v = view {
            let p0 = tracked[0].location(in: v)
            let p1 = tracked[1].location(in: v)
            baselineDistance = max(hypot(p1.x - p0.x, p1.y - p0.y), 1)
            baselineAngle = atan2(p1.y - p0.y, p1.x - p0.x)
            baselineMidpoint = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
            hasBaseline = true
            cumulativeScale = 1.0
            cumulativeRotation = 0.0
            cumulativeTranslation = .zero
            state = .began
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard tracked.count == 2, hasBaseline, let v = view else { return }
        let p0 = tracked[0].location(in: v)
        let p1 = tracked[1].location(in: v)

        let curDist = hypot(p1.x - p0.x, p1.y - p0.y)
        cumulativeScale = curDist / baselineDistance

        var dAngle = atan2(p1.y - p0.y, p1.x - p0.x) - baselineAngle
        if dAngle >  .pi { dAngle -= 2 * .pi }
        if dAngle <= -.pi { dAngle += 2 * .pi }
        cumulativeRotation = dAngle

        let curMid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        cumulativeTranslation = CGPoint(
            x: curMid.x - baselineMidpoint.x,
            y: curMid.y - baselineMidpoint.y
        )

        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        for t in touches { tracked.removeAll { $0 === t } }
        if tracked.count < 2 {
            switch state {
            case .began, .changed: state = .ended
            case .possible:        state = .failed
            default:               break
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        for t in touches { tracked.removeAll { $0 === t } }
        if tracked.count < 2 {
            switch state {
            case .began, .changed: state = .cancelled
            case .possible:        state = .failed
            default:               break
            }
        }
    }

    override func reset() {
        super.reset()
        tracked.removeAll()
        hasBaseline = false
        cumulativeScale = 1.0
        cumulativeRotation = 0.0
        cumulativeTranslation = .zero
    }
}
