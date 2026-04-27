import SwiftUI

struct BitmeColorPicker: View {
    @Binding var color: RGBA
    var onDismiss: () -> Void
    var recentHex: [String] = []

    private enum Tab: String, CaseIterable, Identifiable {
        case grid = "GRID"
        case spectrum = "SPECTRUM"
        case sliders = "SLIDERS"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .grid
    @State private var hexDraft: String = ""
    @State private var brightness: Double = 1.0
    @FocusState private var hexFocused: Bool

    private static let db32Hex: [String] = [
        "000000", "222034", "45283c", "663931", "8f563b", "df7126", "d9a066", "eec39a",
        "fbf236", "99e550", "6abe30", "37946e", "4b692f", "524b24", "323c39", "3f3f74",
        "306082", "5b6ee1", "639bff", "5fcde4", "cbdbfc", "ffffff", "9badb7", "847e87",
        "696a6a", "595652", "76428a", "ac3232", "d95763", "d77bba", "8f974a", "8a6f30",
    ]

    var body: some View {
        VStack(spacing: 18) {
            header
            tabPicker
            Group {
                switch tab {
                case .grid: paletteGrid
                case .spectrum: spectrumView
                case .sliders: slidersView
                }
            }
            hexRow
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.10).ignoresSafeArea())
        .onAppear {
            hexDraft = color.hex.replacingOccurrences(of: "#", with: "")
            brightness = currentHSB().brightness
        }
    }

    // MARK: - Header

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

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    Text(t.rawValue)
                        .font(.pixel(11))
                        .foregroundStyle(tab == t ? .white : Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tab == t ? Color.white.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Grid tab (DB32 palette + user history)

    private var paletteGrid: some View {
        VStack(spacing: 14) {
            if !olderRecents.isEmpty {
                historySection
            }
            swatchGrid(hexes: Self.db32Hex, columns: 8)
        }
    }

    private var olderRecents: [String] {
        Array(recentHex.dropFirst(RecentColorsStrip.maxSwatches).prefix(16))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HISTORY")
                .font(.pixel(9))
                .foregroundStyle(.white.opacity(0.55))
            swatchGrid(hexes: olderRecents, columns: 8)
        }
    }

    private func swatchGrid(hexes: [String], columns: Int) -> some View {
        let rows = Int((Double(hexes.count) / Double(columns)).rounded(.up))
        return VStack(spacing: 4) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<columns, id: \.self) { col in
                        let i = row * columns + col
                        if i < hexes.count {
                            swatch(hex: hexes[i])
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
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
                brightness = currentHSB().brightness
                hexFocused = false
            }
    }

    // MARK: - Spectrum tab (hue × saturation at current brightness)

    private var spectrumView: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        let tilesX = 48
                        let tilesY = 32
                        let tw = size.width / CGFloat(tilesX)
                        let th = size.height / CGFloat(tilesY)
                        for i in 0..<tilesX {
                            for j in 0..<tilesY {
                                let h = Double(i) / Double(tilesX - 1)
                                let s = 1.0 - Double(j) / Double(tilesY - 1)
                                let c = Color(hue: h, saturation: s, brightness: brightness)
                                ctx.fill(
                                    Path(CGRect(
                                        x: CGFloat(i) * tw,
                                        y: CGFloat(j) * th,
                                        width: tw + 1,
                                        height: th + 1
                                    )),
                                    with: .color(c)
                                )
                            }
                        }
                    }
                    marker(in: geo.size)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateFromSpectrumDrag(at: value.location, in: geo.size)
                        }
                )
            }
            .aspectRatio(1.5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )

            HStack(spacing: 12) {
                pixelSun
                    .frame(width: 22, height: 22)
                Slider(value: Binding(
                    get: { brightness },
                    set: { newB in
                        brightness = newB
                        let hs = currentHSB()
                        color = rgbaFromHSB(h: hs.hue, s: hs.saturation, b: newB)
                        hexDraft = color.hex.replacingOccurrences(of: "#", with: "")
                    }
                ), in: 0...1)
                .tint(.white)
            }
        }
    }

    private var pixelSun: some View {
        Canvas { ctx, size in
            let cols = 11
            let pixel = min(size.width, size.height) / CGFloat(cols)
            let pattern: [[Int]] = [
                [0,0,0,0,0,1,0,0,0,0,0],
                [0,1,0,0,0,1,0,0,0,1,0],
                [0,0,1,0,0,0,0,0,1,0,0],
                [0,0,0,0,1,1,1,0,0,0,0],
                [0,0,0,1,1,1,1,1,0,0,0],
                [1,1,0,1,1,1,1,1,0,1,1],
                [0,0,0,1,1,1,1,1,0,0,0],
                [0,0,0,0,1,1,1,0,0,0,0],
                [0,0,1,0,0,0,0,0,1,0,0],
                [0,1,0,0,0,1,0,0,0,1,0],
                [0,0,0,0,0,1,0,0,0,0,0],
            ]
            for (j, row) in pattern.enumerated() {
                for (i, v) in row.enumerated() where v == 1 {
                    let rect = CGRect(x: CGFloat(i) * pixel,
                                      y: CGFloat(j) * pixel,
                                      width: pixel,
                                      height: pixel)
                    ctx.fill(Path(rect), with: .color(.white.opacity(0.85)))
                }
            }
        }
    }

    private func marker(in size: CGSize) -> some View {
        let hs = currentHSB()
        let x = CGFloat(hs.hue) * size.width
        let y = (1.0 - CGFloat(hs.saturation)) * size.height
        return Circle()
            .stroke(Color.white, lineWidth: 2)
            .frame(width: 18, height: 18)
            .shadow(radius: 1)
            .position(x: x, y: y)
            .allowsHitTesting(false)
    }

    private func updateFromSpectrumDrag(at point: CGPoint, in size: CGSize) {
        let h = max(0, min(1, Double(point.x / size.width)))
        let s = max(0, min(1, Double(1.0 - point.y / size.height)))
        color = rgbaFromHSB(h: h, s: s, b: brightness)
        hexDraft = color.hex.replacingOccurrences(of: "#", with: "")
    }

    // MARK: - Sliders tab (RGB)

    private var slidersView: some View {
        VStack(spacing: 14) {
            channelSlider(label: "R", value: rBinding, tint: .red)
            channelSlider(label: "G", value: gBinding, tint: .green)
            channelSlider(label: "B", value: bBinding, tint: .blue)
        }
    }

    private func channelSlider(label: String, value: Binding<Double>, tint: Color) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.pixel(12))
                .foregroundStyle(.white)
                .frame(width: 18, alignment: .leading)
            Slider(value: value, in: 0...255, step: 1)
                .tint(tint)
            Text("\(Int(value.wrappedValue))")
                .font(.pixel(11))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 36, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private var rBinding: Binding<Double> {
        Binding(
            get: { Double(color.r) },
            set: {
                color = RGBA(r: UInt8($0), g: color.g, b: color.b, a: color.a)
                syncAfterChannelChange()
            }
        )
    }
    private var gBinding: Binding<Double> {
        Binding(
            get: { Double(color.g) },
            set: {
                color = RGBA(r: color.r, g: UInt8($0), b: color.b, a: color.a)
                syncAfterChannelChange()
            }
        )
    }
    private var bBinding: Binding<Double> {
        Binding(
            get: { Double(color.b) },
            set: {
                color = RGBA(r: color.r, g: color.g, b: UInt8($0), a: color.a)
                syncAfterChannelChange()
            }
        )
    }

    private func syncAfterChannelChange() {
        hexDraft = color.hex.replacingOccurrences(of: "#", with: "")
        brightness = currentHSB().brightness
    }

    // MARK: - Hex row

    private var hexRow: some View {
        HStack(spacing: 12) {
            Text("HEX")
                .font(.pixel(12))
                .foregroundStyle(.white.opacity(0.8))

            TextField("", text: $hexDraft)
                .font(.pixel(14))
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
            brightness = currentHSB().brightness
        }
    }

    // MARK: - HSB conversion

    private func currentHSB() -> (hue: Double, saturation: Double, brightness: Double) {
        rgbToHsb(r: color.r, g: color.g, b: color.b)
    }

    private func rgbToHsb(r: UInt8, g: UInt8, b: UInt8) -> (hue: Double, saturation: Double, brightness: Double) {
        let rr = Double(r) / 255.0
        let gg = Double(g) / 255.0
        let bb = Double(b) / 255.0
        let maxV = max(rr, gg, bb)
        let minV = min(rr, gg, bb)
        let delta = maxV - minV
        var h: Double = 0
        if delta > 0 {
            if maxV == rr {
                h = ((gg - bb) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxV == gg {
                h = ((bb - rr) / delta) + 2
            } else {
                h = ((rr - gg) / delta) + 4
            }
            h /= 6
            if h < 0 { h += 1 }
        }
        let s = maxV == 0 ? 0 : delta / maxV
        return (h, s, maxV)
    }

    private func rgbaFromHSB(h: Double, s: Double, b: Double) -> RGBA {
        let c = b * s
        let hh = h * 6
        let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
        var rr: Double = 0, gg: Double = 0, bb: Double = 0
        switch Int(hh) {
        case 0: rr = c; gg = x; bb = 0
        case 1: rr = x; gg = c; bb = 0
        case 2: rr = 0; gg = c; bb = x
        case 3: rr = 0; gg = x; bb = c
        case 4: rr = x; gg = 0; bb = c
        default: rr = c; gg = 0; bb = x
        }
        let m = b - c
        return RGBA(
            r: UInt8(max(0, min(255, ((rr + m) * 255).rounded()))),
            g: UInt8(max(0, min(255, ((gg + m) * 255).rounded()))),
            b: UInt8(max(0, min(255, ((bb + m) * 255).rounded()))),
            a: 255
        )
    }
}

#Preview {
    struct Wrapper: View {
        @State var c = RGBA(r: 255, g: 80, b: 120, a: 255)
        var body: some View {
            BitmeColorPicker(color: $c, onDismiss: {})
        }
    }
    return Wrapper()
}
