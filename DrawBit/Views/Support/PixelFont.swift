import SwiftUI

extension Font {
    /// App-wide display font. Use for chrome text (titles, buttons, labels).
    /// Not for text-field input or alerts — those stay on the system font for legibility.
    static func pixel(_ size: CGFloat) -> Font {
        .custom("PressStart2P-Regular", size: size)
    }

    /// Retro body font for long-form copy (help instructions). VT323 is a CRT-terminal
    /// pixel font — far more legible than Press Start 2P for sentences while staying true
    /// to the app's look. Use for paragraphs, not chrome/titles (those stay on `pixel`).
    static func pixelBody(_ size: CGFloat) -> Font {
        .custom("VT323-Regular", size: size)
    }
}
