import SwiftUI

struct BitmeColorPicker: View {
    @Binding var color: RGBA
    var onDismiss: () -> Void

    @State private var hexDraft: String = ""
    @FocusState private var hexFocused: Bool

    private static let db32Hex: [String] = [
        "000000", "222034", "45283c", "663931", "8f563b", "df7126", "d9a066", "eec39a",
        "fbf236", "99e550", "6abe30", "37946e", "4b692f", "524b24", "323c39", "3f3f74",
        "306082", "5b6ee1", "639bff", "5fcde4", "cbdbfc", "ffffff", "9badb7", "847e87",
        "696a6a", "595652", "76428a", "ac3232", "d95763", "d77bba", "8f974a", "8a6f30",
    ]

    var body: some View {
        VStack(spacing: 20) {
            header
            paletteGrid
            hexRow
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.10).ignoresSafeArea())
        .onAppear { hexDraft = color.hex.replacingOccurrences(of: "#", with: "") }
    }

    private var header: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(rgba: color))
                .frame(width: 56, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )

            Text("COLORS")
                .font(.pixel(14))
                .foregroundStyle(.white)

            Spacer()

            Button {
                commitHexIfValid()
                onDismiss()
            } label: {
                Text("USE")
                    .font(.pixel(12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
            }
        }
    }

    private var paletteGrid: some View {
        let cols = 8
        let rows = Self.db32Hex.count / cols
        return VStack(spacing: 4) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<cols, id: \.self) { col in
                        let hex = Self.db32Hex[row * cols + col]
                        swatch(hex: hex)
                    }
                }
            }
        }
    }

    private func swatch(hex: String) -> some View {
        let swatchColor = RGBA(hex: hex) ?? RGBA(r: 0, g: 0, b: 0, a: 255)
        let isSelected = swatchColor == color
        return Rectangle()
            .fill(Color(rgba: swatchColor))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Rectangle().stroke(
                    isSelected ? Color.white : Color.white.opacity(0.18),
                    lineWidth: isSelected ? 2 : 0.5
                )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                color = swatchColor
                hexDraft = hex.uppercased()
                hexFocused = false
            }
    }

    private var hexRow: some View {
        HStack(spacing: 12) {
            Text("HEX")
                .font(.pixel(12))
                .foregroundStyle(.white.opacity(0.8))

            TextField("", text: $hexDraft)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .focused($hexFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .onSubmit { commitHexIfValid() }

            RoundedRectangle(cornerRadius: 4)
                .fill(hexPreviewColor)
                .frame(width: 34, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        }
    }

    private var hexPreviewColor: Color {
        if let rgba = RGBA(hex: hexDraft) { return Color(rgba: rgba) }
        return Color(rgba: color)
    }

    private func commitHexIfValid() {
        if let rgba = RGBA(hex: hexDraft) {
            color = rgba
            hexDraft = rgba.hex.replacingOccurrences(of: "#", with: "")
        }
    }
}

#Preview {
    struct Wrapper: View {
        @State var c = RGBA(r: 255, g: 255, b: 255, a: 255)
        var body: some View {
            BitmeColorPicker(color: $c, onDismiss: {})
        }
    }
    return Wrapper()
}
