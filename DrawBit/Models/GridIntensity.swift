import Foundation

/// How strongly the pixel grid is drawn over the canvas. A tap-to-cycle top-bar control advances
/// `OFF → SOFT → STRONG` (wrapping), resting on `SOFT` by default.
///
/// The value is a single strength dial on the grid that already exists: `multiplier` scales the
/// output of `gridLineAlpha(screenCellPoints:)` in `CanvasView.gridOverlay`, so the zoom-fade keeps
/// working and `SOFT` calms the grid everywhere (including the big-cell/small-canvas case, which was
/// otherwise pinned at full strength).
///
/// The pre-feature grid drew at full strength (multiplier 1.0) and read as too loud, so no level
/// reproduces it: `STRONG` is the boldest step but deliberately sits below full strength.
///
/// Persisted globally via `AppSettings.gridIntensity` — it's a viewing preference, not part of the
/// artwork. `EditorState` holds the live session copy that the canvas renders.
enum GridIntensity: Int, CaseIterable {
    case off = 0
    case soft = 1
    case strong = 2

    /// Multiplies `gridLineAlpha(...)`: `OFF` hides the interior mesh, `SOFT` is the calm default,
    /// `STRONG` is the boldest step (still below the retired 1.0 full-strength look). Dialed on real
    /// captures with the founder.
    var multiplier: Double {
        switch self {
        case .off: 0
        case .soft: 0.35
        case .strong: 0.6
        }
    }

    /// Next step in the tap-to-cycle, wrapping `strong → off` — mirrors the brush-nib / FPS idiom.
    func next() -> GridIntensity {
        switch self {
        case .off: .soft
        case .soft: .strong
        case .strong: .off
        }
    }
}
