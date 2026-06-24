import SwiftUI

/// Procreate-style hover feedback: while the Apple Pencil (or a trackpad
/// pointer) hovers this view, it springs up and lifts, snapping back on exit.
///
/// `.onHover` carries Pencil hover on M-series iPad Pros and pointer hover from
/// a trackpad; on hardware without hover it never fires, so this is a graceful
/// no-op there. `scaleEffect`/`offset` don't participate in layout — neighbors
/// never reflow and the underlying hit-target stays put, so taps are unaffected.
///
/// The animation is gated to `nil` under UI test: a live spring would prevent
/// XCUITest from reaching idle and wedge its automatic sync (same gating as
/// `LayersPanel`/`LayerRow`).
struct HoverPop: ViewModifier {
    var scale: CGFloat = 1.15
    var lift: CGFloat = 2
    /// Drop a soft shadow while hovering. Off for sites where the shadow would
    /// outline an otherwise-invisible card (e.g. the Help tiles, which share the
    /// screen's background colour — there the shadow reveals the tile, unwanted).
    var shadow: Bool = true
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1.0)
            .offset(y: hovering ? -lift : 0)
            .shadow(color: .black.opacity(hovering && shadow ? 0.45 : 0),
                    radius: hovering && shadow ? 6 : 0, y: hovering && shadow ? 3 : 0)
            .animation(UITestSupport.isRunning ? nil
                       : .spring(response: 0.25, dampingFraction: 0.6),
                       value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Adds Procreate-style hover pop. Tune `scale`/`lift` per-site if needed;
    /// pass `shadow: false` to lift without a drop shadow.
    func hoverPop(scale: CGFloat = 1.15, lift: CGFloat = 2, shadow: Bool = true) -> some View {
        modifier(HoverPop(scale: scale, lift: lift, shadow: shadow))
    }
}
