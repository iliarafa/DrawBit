import SwiftUI

/// Single-source lighting for gallery tiles: the whole gallery is lit by one
/// overhead light, so every tile casts the same shadow straight down (`x: 0`,
/// positive `y`) — no horizontal offset, no all-around glow. A plain black shadow
/// is faint on the near-black gallery background, so the single drop is given a
/// larger offset/radius to stay clearly visible on its own. Tune the one constant
/// set here; every tile that uses `.galleryTileLift()` inherits the change.
///
/// No animation, so (unlike `HoverPop`) there is nothing to gate under UI test.
struct GalleryTileLift: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)   // single overhead light, faint
    }
}

extension View {
    func galleryTileLift() -> some View { modifier(GalleryTileLift()) }
}
