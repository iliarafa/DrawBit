import SwiftUI

struct RecentColorsStrip: View {
    @Binding var selectedColor: RGBA
    @Binding var recentHex: [String]
    var onRequestColorPicker: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(recentHex, id: \.self) { hex in
                    SwatchButton(
                        hex: hex,
                        isSelected: RGBA(hex: hex) == selectedColor,
                        action: {
                            if let c = RGBA(hex: hex) { selectedColor = c }
                        }
                    )
                }
                Button(action: onRequestColorPicker) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.white.opacity(0.25), style: .init(lineWidth: 1, dash: [2, 2]))
                        )
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct SwatchButton: View {
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
