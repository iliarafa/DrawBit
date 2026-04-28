import SwiftUI

extension Font {
    /// App-wide display font. Use for chrome text (titles, buttons, labels).
    /// Not for text-field input or alerts — those stay on the system font for legibility.
    static func pixel(_ size: CGFloat) -> Font {
        .custom("PressStart2P-Regular", size: size)
    }
}
