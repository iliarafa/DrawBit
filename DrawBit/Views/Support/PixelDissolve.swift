import SwiftUI

/// A pixel-block reveal mask. Fills every cell whose stable pseudo-random threshold is
/// ≤ `progress`, so animating `progress` 0→1 makes the masked view assemble from scattered
/// ~14pt blocks (and 1→0 dissolves it away). The threshold is a hash of the cell's grid
/// position, so the scatter is random-looking but deterministic frame-to-frame.
///
/// Shared by the help page (instruction boxes assemble in) and the launch intro
/// (`LaunchSequenceView` drives `progress` in both directions).
struct PixelDissolve: Shape {
    var progress: CGFloat
    var cell: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if progress <= 0 { return path }
        if progress >= 1 { path.addRect(rect); return path }
        let cols = Int(ceil(rect.width / cell))
        let rows = Int(ceil(rect.height / cell))
        for row in 0..<rows {
            for col in 0..<cols {
                let h = sin(Double(col) * 12.9898 + Double(row) * 78.233) * 43758.5453
                let threshold = CGFloat(h - h.rounded(.down))
                if threshold <= progress {
                    path.addRect(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell,
                                        width: cell, height: cell))
                }
            }
        }
        return path
    }
}

/// Animatable wrapper so the dissolve interpolates. SwiftUI tweens `progress`
/// between the transition's active (0) and identity (1) states, or whatever
/// explicit value `pixelDissolve(progress:)` is animated to.
struct PixelDissolveModifier: ViewModifier, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.mask(PixelDissolve(progress: progress).fill(style: FillStyle(antialiased: false)))
    }
}

extension View {
    /// Mask the view through the pixel-dissolve at an explicit progress
    /// (0 = fully gone, 1 = fully present). Animate `progress` to dissolve in or out.
    func pixelDissolve(progress: CGFloat) -> some View {
        modifier(PixelDissolveModifier(progress: progress))
    }
}

extension AnyTransition {
    /// Materialise the view from pixel blocks on insert; cut instantly on removal — so
    /// closing/switching is an instant snap and only the opening dissolve is animated.
    static var openDissolve: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: PixelDissolveModifier(progress: 0),
                                 identity: PixelDissolveModifier(progress: 1)),
            removal: .identity
        )
    }
}
