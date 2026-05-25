import SwiftUI

/// Recent-color configuration shared by the bottom toolbar (which shows the most
/// recent swatches) and the color picker (which shows the older ones beyond them).
enum RecentColors {
    /// How many recent swatches the bottom toolbar displays.
    static let maxSwatches = 3
}

/// A single recent-color swatch. Tapping a non-selected swatch selects it; tapping
/// the already-selected swatch opens the color picker (handled by the caller).
struct SwatchButton: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let rgba = RGBA(hex: hex) ?? .transparent
        let color = Color(rgba: rgba)
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 26, height: 26)
                if isSelected {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color, lineWidth: 3)
                        .frame(width: 30, height: 30)
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RGBA <-> hex / CGColor bridges

extension RGBA {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let n = UInt32(s, radix: 16) else { return nil }
        self = RGBA(
            r: UInt8((n >> 16) & 0xFF),
            g: UInt8((n >> 8) & 0xFF),
            b: UInt8(n & 0xFF),
            a: 255
        )
    }

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    init?(cgColor: CGColor) {
        guard let components = cgColor.components, components.count >= 3 else { return nil }
        self = RGBA(
            r: UInt8((components[0] * 255).rounded().clamped(0, 255)),
            g: UInt8((components[1] * 255).rounded().clamped(0, 255)),
            b: UInt8((components[2] * 255).rounded().clamped(0, 255)),
            a: 255
        )
    }
}

extension Color {
    init(rgba: RGBA) {
        self.init(
            .sRGB,
            red: Double(rgba.r) / 255.0,
            green: Double(rgba.g) / 255.0,
            blue: Double(rgba.b) / 255.0,
            opacity: Double(rgba.a) / 255.0
        )
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
