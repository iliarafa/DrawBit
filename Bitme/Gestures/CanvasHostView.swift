import SwiftUI
import UIKit

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
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)
        let rot = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        addGestureRecognizer(rot)
        let reset = UITapGestureRecognizer(target: self, action: #selector(handleReset(_:)))
        reset.numberOfTapsRequired = 2
        reset.numberOfTouchesRequired = 2
        addGestureRecognizer(reset)
        [pan, pinch, rot].forEach { $0.delegate = self }
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

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let state else { return }
        if g.state == .began { cancelStrokeIfAny() }
        let t = g.translation(in: self)
        state.translation = CGSize(
            width: state.translation.width + t.x,
            height: state.translation.height + t.y
        )
        g.setTranslation(.zero, in: self)
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let state else { return }
        if g.state == .began { cancelStrokeIfAny() }
        state.scale = max(0.25, min(40, state.scale * g.scale))
        g.scale = 1
    }

    @objc private func handleRotation(_ g: UIRotationGestureRecognizer) {
        guard let state else { return }
        if g.state == .began { cancelStrokeIfAny() }
        var next = state.rotation + g.rotation
        // Snap to 0 within ~4° to make straightening back up easy.
        if abs(next) < 0.0698 { next = 0 }
        state.rotation = next
        g.rotation = 0
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
