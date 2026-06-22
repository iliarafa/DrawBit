import SwiftUI

extension Color {
    /// Signature highlight for an active / selected chrome control — the
    /// currently selected tool and the mirror-on state. This is the app's only
    /// chrome accent; everything else in the toolbar stays monochrome white.
    /// #0099CC.
    static let toolSelected = Color(red: 0x00 / 255, green: 0x99 / 255, blue: 0xCC / 255)

    /// Destructive accent for delete affordances (sheets, menu rows). The app's
    /// only red — kept off the monochrome chrome and reserved for "this removes
    /// something". #D95763.
    static let destructive = Color(red: 217.0 / 255.0, green: 87.0 / 255.0, blue: 99.0 / 255.0)
}
