import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct CanvasHostView: UIViewRepresentable {
    @Bindable var state: EditorState
    var pencilAvailability: PencilAvailability
    var baseEdge: CGFloat
    var onStrokePoint: (Int, Int) -> Void
    var onStrokeBegin: () -> Void
    var onStrokeEnd: () -> Void
    var onStrokeCancel: () -> Void
    var onTap: (Int, Int) -> Void

    func makeUIView(context: Context) -> CanvasInputView {
        let v = CanvasInputView()
        v.configure(state: state, pencilAvailability: pencilAvailability, baseEdge: baseEdge)
        v.onStrokePoint = onStrokePoint
        v.onStrokeBegin = onStrokeBegin
        v.onStrokeEnd = onStrokeEnd
        v.onStrokeCancel = onStrokeCancel
        v.onTap = onTap
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: CanvasInputView, context: Context) {
        uiView.configure(state: state, pencilAvailability: pencilAvailability, baseEdge: baseEdge)
    }
}

final class CanvasInputView: UIView {
    var state: EditorState?
    var pencilAvailability: PencilAvailability?
    var baseEdge: CGFloat = 0
    var onStrokePoint: ((Int, Int) -> Void)?
    var onStrokeBegin: (() -> Void)?
    var onStrokeEnd: (() -> Void)?
    var onStrokeCancel: (() -> Void)?
    var onTap: ((Int, Int) -> Void)?

    private var strokeInProgress = false
    private var lastPixel: (Int, Int)?
    private var didMove = false

    func configure(state: EditorState, pencilAvailability: PencilAvailability, baseEdge: CGFloat) {
        self.state = state
        self.pencilAvailability = pencilAvailability
        self.baseEdge = baseEdge
        isMultipleTouchEnabled = true
        installRecognizersIfNeeded()
    }

    private func installRecognizersIfNeeded() {
        guard gestureRecognizers?.isEmpty ?? true else { return }
        let xform = TwoFingerTransformGestureRecognizer(target: self, action: #selector(handleTransform(_:)))
        xform.delegate = self
        addGestureRecognizer(xform)
        let reset = UITapGestureRecognizer(target: self, action: #selector(handleReset(_:)))
        reset.numberOfTapsRequired = 2
        reset.numberOfTouchesRequired = 2
        addGestureRecognizer(reset)
    }

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
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard strokeInProgress else { return }
        if !didMove, let first = touches.first, let p = pixelCoord(for: first) {
            // Pure tap: emit a single-point paint via onTap.
            strokeInProgress = false
            lastPixel = nil
            didMove = false
            onTap?(p.0, p.1)
            return
        }
        strokeInProgress = false
        lastPixel = nil
        didMove = false
        onStrokeEnd?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard strokeInProgress else { return }
        strokeInProgress = false
        lastPixel = nil
        didMove = false
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
        onStrokeBegin?()
    }

    // MARK: - Two-finger transform gestures

    @objc private func handleTransform(_ g: TwoFingerTransformGestureRecognizer) {
        guard let state else { return }
        if g.state == .began { cancelStrokeIfAny() }
        let dt = g.translationDelta
        state.translation = CGSize(
            width: state.translation.width + dt.x,
            height: state.translation.height + dt.y
        )
        state.scale = max(0.25, min(40, state.scale * g.scaleDelta))
        var next = state.rotation + g.rotationDelta
        // Snap to 0 within ~4° to make straightening back up easy.
        if abs(next) < 0.0698 { next = 0 }
        state.rotation = next
    }

    @objc private func handleReset(_ g: UITapGestureRecognizer) {
        guard let state else { return }
        state.translation = .zero
        state.scale = 1.0
        state.rotation = 0.0
    }

    private func cancelStrokeIfAny() {
        guard strokeInProgress else { return }
        strokeInProgress = false
        lastPixel = nil
        didMove = false
        onStrokeCancel?()
    }

    // MARK: - Touch → pixel mapping

    /// Convert a UITouch in view coords to an integer pixel in the grid, accounting for the
    /// current editor transform (translation, scale, rotation). Returns nil if out of canvas.
    private func pixelCoord(for touch: UITouch) -> (Int, Int)? {
        guard let state else { return nil }
        let dim = CGFloat(state.grid.dimension)
        let size = bounds.size
        guard baseEdge > 0, dim > 0, state.scale > 0 else { return nil }

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
        // Step 3: un-scale to canvas-local centered coords (-baseEdge/2 … baseEdge/2).
        let local = CGPoint(x: rotated.x / state.scale, y: rotated.y / state.scale)
        // Step 4: shift to canvas-local top-left coords (0 … baseEdge).
        let canvasLocal = CGPoint(x: local.x + baseEdge / 2, y: local.y + baseEdge / 2)
        // Step 5: integer pixel index.
        let perPixel = baseEdge / dim
        let ix = Int(floor(canvasLocal.x / perPixel))
        let iy = Int(floor(canvasLocal.y / perPixel))
        guard ix >= 0, iy >= 0, ix < Int(dim), iy < Int(dim) else { return nil }
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
/// "sometimes responds, sometimes doesn't" behavior. This recognizer enters `.began` the moment
/// the second finger lands and exposes per-frame deltas — pan, pinch, and rotate are always in
/// lockstep with the fingers. Same approach Procreate uses.
final class TwoFingerTransformGestureRecognizer: UIGestureRecognizer {
    private(set) var translationDelta: CGPoint = .zero
    private(set) var scaleDelta: CGFloat = 1.0
    private(set) var rotationDelta: CGFloat = 0.0

    private var tracked: [UITouch] = []
    private var previous: (CGPoint, CGPoint)?

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
        if tracked.count == 2, previous == nil, let v = view {
            previous = (tracked[0].location(in: v), tracked[1].location(in: v))
            translationDelta = .zero
            scaleDelta = 1.0
            rotationDelta = 0.0
            state = .began
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard tracked.count == 2, let prev = previous, let v = view else { return }
        let cur0 = tracked[0].location(in: v)
        let cur1 = tracked[1].location(in: v)

        let prevMid = CGPoint(x: (prev.0.x + prev.1.x) / 2, y: (prev.0.y + prev.1.y) / 2)
        let curMid  = CGPoint(x: (cur0.x + cur1.x) / 2, y: (cur0.y + cur1.y) / 2)

        let prevDx = prev.1.x - prev.0.x
        let prevDy = prev.1.y - prev.0.y
        let curDx  = cur1.x - cur0.x
        let curDy  = cur1.y - cur0.y

        let prevDist = hypot(prevDx, prevDy)
        let curDist  = hypot(curDx, curDy)

        translationDelta = CGPoint(x: curMid.x - prevMid.x, y: curMid.y - prevMid.y)
        scaleDelta = prevDist > 0 ? curDist / prevDist : 1.0

        var dAngle = atan2(curDy, curDx) - atan2(prevDy, prevDx)
        if dAngle >  .pi { dAngle -= 2 * .pi }
        if dAngle <= -.pi { dAngle += 2 * .pi }
        rotationDelta = dAngle

        previous = (cur0, cur1)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        for t in touches { tracked.removeAll { $0 === t } }
        if tracked.count < 2 {
            previous = nil
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
            previous = nil
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
        previous = nil
        translationDelta = .zero
        scaleDelta = 1.0
        rotationDelta = 0.0
    }
}
