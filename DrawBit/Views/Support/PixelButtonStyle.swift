import SwiftUI

/// Classic 90s-RPG raised pixel button: an opaque face + 1px border sitting on a hard
/// dark slab that pokes out the bottom edge by `depth` (no blur — pixel-aesthetic bevel).
/// Pressing drops the face down by `depth` onto the slab, so the bevel collapses and the
/// button reads as pressed flush — the satisfying "clunk." The drop is animated fast and
/// gated off under UI test (matching `HoverPop` / `LayerRow`) so XCUITest still reaches idle.
struct PixelButtonStyle: ButtonStyle {
    var face: Color
    var border: Color
    var depth: CGFloat = 2
    var shadow: Color = .black.opacity(0.55)

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        // Opaque face wrapping the label. `.offset` is render-only (doesn't move layout), so
        // on press the face visually drops by `depth` while the slab `.background` — sized to
        // the face and pushed down `depth` — stays put, and the face covers it (bevel collapses).
        configuration.label
            .background(Rectangle().fill(face))
            .overlay(Rectangle().stroke(border, lineWidth: 1))
            .offset(y: pressed ? depth : 0)
            .background(alignment: .top) {
                Rectangle().fill(shadow).offset(y: depth)   // slab pokes out `depth` at the bottom
            }
            .padding(.bottom, depth)                         // reserve room for the slab strip
            .animation(UITestSupport.isRunning ? nil : .easeOut(duration: 0.05), value: pressed)
            // Mechanical click + light-impact haptic the instant the finger lands (touch-down,
            // i.e. the false→true transition — `onChange` fires only on real changes).
            .onChange(of: pressed) { _, isDown in
                if isDown { ButtonClick.shared.fire() }
            }
    }
}
