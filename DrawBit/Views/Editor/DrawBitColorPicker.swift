import SwiftUI

struct DrawBitColorPicker: View {
    @Binding var color: RGBA
    var onDismiss: () -> Void
    var recentHex: [String] = []
    /// Live binding to the user's global custom palettes. The picker mutates this directly
    /// (via the shared `[ColorPalette]` ops); EditorView persists it through PieceRepository.
    @Binding var customPalettes: [ColorPalette]
    /// Lazily yields the distinct colors used in the current piece, for "FROM PIECE".
    var pieceColors: () -> [String] = { [] }

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

    // Palette-browser state
    @State private var selectedPaletteID: UUID = BuiltInPalettes.db32.id
    @State private var showingSelector = false   // inline themed chooser (replaces the grid area)
    @State private var editing = false           // focused edit panel for a custom palette
    @State private var renameDraft = ""

    /// Stable id for the synthesized read-only RECENT palette.
    private static let recentPaletteID = UUID(uuidString: "0B17A1D0-0000-4000-A000-0000000000FF")!

    var body: some View {
        VStack(spacing: 18) {
            header
            tabPicker
            Group {
                switch tab {
                case .grid: paletteBrowser
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
            // Open on RECENT when there's history, else DB32.
            if let recent = recentPalette { selectedPaletteID = recent.id }
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

    // MARK: - Palette browser (GRID tab)
    //
    // Calm by design: the default view shows ONLY a palette name + its swatches. Switching is an
    // inline themed chooser; all management (create/rename/delete/add/remove) is hidden behind the
    // pencil's edit panel. Built-ins and RECENT are read-only.

    /// Synthesized read-only palette of recent colors; omitted when there's no history.
    private var recentPalette: ColorPalette? {
        recentHex.isEmpty ? nil : ColorPalette(id: Self.recentPaletteID, name: "RECENT", colors: recentHex)
    }

    /// One ordered list: RECENT → built-ins → custom.
    private var selectablePalettes: [ColorPalette] {
        (recentPalette.map { [$0] } ?? []) + BuiltInPalettes.all + customPalettes
    }

    private var selectedPalette: ColorPalette {
        selectablePalettes.first { $0.id == selectedPaletteID }
            ?? selectablePalettes.first
            ?? BuiltInPalettes.db32
    }

    private var isSelectedCustom: Bool {
        customPalettes.contains { $0.id == selectedPaletteID }
    }

    @ViewBuilder
    private var paletteBrowser: some View {
        if editing && isSelectedCustom {
            editPanel
        } else if showingSelector {
            selectorList
        } else {
            VStack(spacing: 14) {
                selectorRow
                paletteSwatches(selectedPalette, removeMode: false)
            }
        }
    }

    private var selectorRow: some View {
        HStack(spacing: 10) {
            Button { showingSelector = true } label: {
                HStack(spacing: 8) {
                    Text(selectedPalette.name)
                        .font(.pixel(12))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .hoverPop()
            .accessibilityIdentifier("PaletteSelector")

            Spacer()

            if isSelectedCustom {
                Button {
                    renameDraft = selectedPalette.name
                    editing = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .hoverPop()
                .accessibilityIdentifier("EditPalette")
            }
        }
    }

    // MARK: Inline chooser

    private var selectorList: some View {
        VStack(spacing: 8) {
            HStack {
                Text("PALETTES")
                    .font(.pixel(11))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button { showingSelector = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("CloseSelector")
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(selectablePalettes) { paletteRow($0) }
                    newPaletteRow
                }
            }
        }
    }

    private func paletteRow(_ p: ColorPalette) -> some View {
        let isSel = p.id == selectedPaletteID
        return Button {
            selectedPaletteID = p.id
            showingSelector = false
        } label: {
            HStack(spacing: 10) {
                Text(p.name)
                    .font(.pixel(11))
                    .foregroundStyle(.white)
                    .frame(width: 96, alignment: .leading)
                    .lineLimit(1)
                miniStrip(p.colors)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSel ? .white : .clear)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(isSel ? 0.10 : 0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("Palette-\(p.name)")
    }

    private var newPaletteRow: some View {
        Button {
            let p = customPalettes.addPalette()
            selectedPaletteID = p.id
            renameDraft = p.name
            showingSelector = false
            editing = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("NEW PALETTE")
                    .font(.pixel(11))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("NewPalette")
    }

    private func miniStrip(_ hexes: [String]) -> some View {
        HStack(spacing: 0) {
            if hexes.isEmpty {
                Text("empty")
                    .font(.pixel(9))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(hexes.prefix(14).enumerated()), id: \.offset) { _, h in
                    Rectangle()
                        .fill(Color(rgba: RGBA(hex: h) ?? .transparent))
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: Swatch grid

    private func paletteSwatches(_ p: ColorPalette, removeMode: Bool) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(p.colors.enumerated()), id: \.offset) { _, hex in
                swatchCell(hex: hex, removeMode: removeMode, paletteID: p.id)
            }
            if isSelectedCustom && !removeMode {
                addCurrentColorTile(paletteID: p.id)
            }
        }
    }

    private func swatchCell(hex: String, removeMode: Bool, paletteID: UUID) -> some View {
        let swatchColor = RGBA(hex: hex) ?? RGBA(r: 0, g: 0, b: 0, a: 255)
        let isSelected = !removeMode && swatchColor == color
        return Rectangle()
            .fill(Color(rgba: swatchColor))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Rectangle().stroke(
                    isSelected ? Color.white : Color.white.opacity(0.18),
                    lineWidth: isSelected ? 2 : 0.5
                )
            )
            .overlay(removeMode ? removeBadge : nil)
            .hoverPop()
            .contentShape(Rectangle())
            .onTapGesture {
                if removeMode {
                    customPalettes.removeColor(hex, fromPaletteID: paletteID)
                } else {
                    color = swatchColor
                    hexDraft = hex.replacingOccurrences(of: "#", with: "").uppercased()
                    brightness = currentHSB().brightness
                    hexFocused = false
                }
            }
    }

    private var removeBadge: some View {
        Image(systemName: "minus.circle.fill")
            .font(.system(size: 12))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color(red: 0.85, green: 0.2, blue: 0.2))
            .padding(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .allowsHitTesting(false)
    }

    private func addCurrentColorTile(paletteID: UUID) -> some View {
        Button {
            customPalettes.addColor(color.hex, toPaletteID: paletteID)
        } label: {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Rectangle().stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                )
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                )
        }
        .buttonStyle(.plain)
        .hoverPop()
        .accessibilityIdentifier("AddCurrentColor")
    }

    // MARK: Edit panel (focused; custom palettes only)

    private var editPanel: some View {
        let p = selectedPalette
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    commitRename()
                    editing = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                        Text("DONE").font(.pixel(11))
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("DonePalette")

                Spacer()

                Button {
                    deleteSelectedPalette()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 12))
                        Text("DELETE").font(.pixel(10))
                    }
                    .foregroundStyle(Color(red: 0.9, green: 0.35, blue: 0.35))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("DeletePalette")
            }

            TextField("", text: $renameDraft)
                .font(.pixel(14))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                .onSubmit { commitRename() }
                .accessibilityIdentifier("PaletteName")

            if p.colors.isEmpty {
                Text("Tap ADD or FROM DRAW to fill this palette.")
                    .font(.pixel(9))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("Tap a color to remove it.")
                    .font(.pixel(9))
                    .foregroundStyle(.white.opacity(0.5))
                paletteSwatches(p, removeMode: true)
            }

            HStack(spacing: 10) {
                editAction(icon: "plus", title: "ADD CURRENT", id: "AddCurrentColor") {
                    customPalettes.addColor(color.hex, toPaletteID: p.id)
                }
                editAction(icon: "square.on.square", title: "FROM DRAW", id: "FromPiece") {
                    for hex in pieceColors() {
                        customPalettes.addColor(hex, toPaletteID: p.id)
                    }
                }
            }
        }
    }

    private func editAction(icon: String, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                Text(title).font(.pixel(10))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .hoverPop()
        .accessibilityIdentifier(id)
    }

    private func commitRename() {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        customPalettes.renamePalette(id: selectedPaletteID, to: trimmed)
    }

    private func deleteSelectedPalette() {
        let id = selectedPaletteID
        editing = false
        selectedPaletteID = recentPalette?.id ?? BuiltInPalettes.db32.id
        customPalettes.deletePalette(id: id)
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
        @State var palettes: [ColorPalette] = []
        var body: some View {
            DrawBitColorPicker(
                color: $c,
                onDismiss: {},
                recentHex: ["#FF5078", "#5B6EE1", "#99E550"],
                customPalettes: $palettes
            )
        }
    }
    return Wrapper()
}
