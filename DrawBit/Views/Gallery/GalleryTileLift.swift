import SwiftUI

/// Procreate-style "lifted off the canvas" feel for gallery tiles. A literal
/// black drop shadow is nearly invisible on the near-black gallery background
/// (no contrast to fall onto), so this pairs a faint light halo with a small
/// soft dark shadow — the dark-UI way to read as elevation. Tune the two
/// constants here; every tile that uses `.galleryTileLift()` inherits the change.
///
/// No animation, so (unlike `HoverPop`) there is nothing to gate under UI test.
struct GalleryTileLift: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.55), radius: 4, y: 2)   // soft dark drop
            .shadow(color: .white.opacity(0.05), radius: 6)         // faint light halo
    }
}

extension View {
    func galleryTileLift() -> some View { modifier(GalleryTileLift()) }
}
