import SwiftUI

struct NewPieceSheet: View {
    let onCreate: (CanvasSize) -> Void
    /// Called when the user dismisses without creating (CANCEL / scrim tap is wired
    /// by the presenter). Presented as a custom in-gallery overlay rather than a system
    /// sheet, so there is no `@Environment(\.dismiss)` — the presenter owns close/create.
    let onCancel: () -> Void

    /// Single source of truth for the dial; the field shows it verbatim while typing,
    /// `dim` is the clamped value everything downstream uses. With a non-square ratio
    /// `dim` is the LONGEST edge; the ratio derives the short edge.
    @State private var text: String = "32"
    @State private var ratio: CanvasSize.Ratio = .square
    @FocusState private var fieldFocused: Bool

    private var dim: Int {
        min(CanvasSize.maxDimension, max(CanvasSize.minDimension, Int(text) ?? CanvasSize.minDimension))
    }

    /// The actual canvas the current (ratio, longest-edge) selection produces.
    private var selectedSize: CanvasSize { CanvasSize(ratio: ratio, longestEdge: dim) }

    private func setDim(_ n: Int) {
        text = String(min(CanvasSize.maxDimension, max(CanvasSize.minDimension, n)))
    }

    var body: some View {
        // A fixed-width padded block; the sheet uses `.presentationSizing(.fitted)`
        // (set in GalleryView) to hug it, giving an equal margin on all four sides.
        VStack(spacing: 20) {
            header
            CanvasPreview(size: selectedSize)
                .frame(width: 96, height: 96)
            numberRow
            PixelSlider(value: Binding(get: { dim }, set: { setDim($0) }),
                        range: CanvasSize.minDimension...CanvasSize.maxDimension)
            ratioSelector
            createButton
        }
        .frame(width: 320)
        .padding(20)
    }

    // MARK: - Aspect ratio selector (1:1 / 16:9 / 9:16)

    private var ratioSelector: some View {
        HStack(spacing: 8) {
            ratioChip("1:1", .square)
            ratioChip("16:9", .r16x9)
            ratioChip("9:16", .r9x16)
        }
    }

    private func ratioChip(_ label: String, _ r: CanvasSize.Ratio) -> some View {
        let active = ratio == r
        return Button {
            ratio = r
        } label: {
            Text(label)
                .font(.pixel(11))
                .foregroundStyle(active ? Color.toolSelected : .white.opacity(0.7))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(PixelButtonStyle(
            face: active ? Color.toolSelected.opacity(0.22) : Color(white: 0.16),
            border: active ? Color.toolSelected : .white.opacity(0.2)
        ))
        .accessibilityIdentifier("NewPiece-ratio-\(r)")
    }

    // MARK: - Header (NEW DRAW left, CANCEL right)

    private var header: some View {
        HStack {
            Text("NEW DRAW")
                .font(.pixel(14))
                .foregroundStyle(.white)
            Spacer()
            Button { onCancel() } label: {
                Text("CANCEL")
                    .font(.pixel(11))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .overlay(Rectangle().stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Big number + steppers (centered)

    private var numberRow: some View {
        HStack(spacing: 24) {
            stepper(isPlus: false) { setDim(dim - 1) }
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .font(.pixel(34))
                .foregroundStyle(.white)
                .tint(Color.toolSelected)
                .multilineTextAlignment(.center)
                .frame(width: 120)
                .focused($fieldFocused)
                .accessibilityIdentifier("NewPiece-dimField")
                .onChange(of: fieldFocused) { _, focused in
                    if !focused { text = String(dim) }   // normalize on blur
                }
            stepper(isPlus: true) { setDim(dim + 1) }
        }
    }

    /// Steppers draw their +/− as pixel bars rather than font glyphs so both sit
    /// perfectly centred (Press Start 2P's minus glyph isn't vertically centred).
    private func stepper(isPlus: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Rectangle().fill(.white).frame(width: 16, height: 3)
                if isPlus {
                    Rectangle().fill(.white).frame(width: 3, height: 16)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PixelButtonStyle(face: Color(white: 0.16), border: .white.opacity(0.25)))
        .accessibilityIdentifier(isPlus ? "NewPiece-plus" : "NewPiece-minus")
        .accessibilityLabel(isPlus ? "Increase size" : "Decrease size")
    }

    private var createButton: some View {
        Button {
            onCreate(selectedSize)
        } label: {
            Text("CREATE")
                .font(.pixel(12))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(PixelButtonStyle(face: Color.toolSelected.opacity(0.22), border: Color.toolSelected))
        .padding(.top, 4)
        .accessibilityIdentifier("NewPiece-create")
    }
}

/// A pixel-grid square that *grows with the chosen size* and shows the *actual
/// pixels* at low resolution — an 8×8 draws 8 countable cells. As the size rises the
/// grid densifies until cells hit a ~3pt legibility floor, where the grain plateaus
/// (`count = min(dimension, side/minCell)`) while the square keeps growing toward
/// filling the frame — so every size still reads distinctly.
private struct CanvasPreview: View {
    let size: CanvasSize

    var body: some View {
        Canvas { ctx, canvas in
            let box = min(canvas.width, canvas.height)
            let minSide = box * 0.36
            let lo = sqrt(Double(CanvasSize.minDimension))
            let hi = sqrt(Double(CanvasSize.maxDimension))
            let frac = max(0, min(1, (sqrt(Double(size.longestEdge)) - lo) / (hi - lo)))
            // Longest edge grows with the chosen size; the short edge keeps the canvas aspect.
            let longSide = minSide + CGFloat(frac) * (box - minSide)
            let w = size.width >= size.height ? longSide : longSide * CGFloat(size.width) / CGFloat(size.height)
            let h = size.height >= size.width ? longSide : longSide * CGFloat(size.height) / CGFloat(size.width)
            let rect = CGRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h)

            ctx.fill(Path(rect), with: .color(Color(white: 0.15)))

            // Real pixels while they stay ≥ minCell on screen, then a fixed fine grain.
            // Square cells, sized off the longest edge; gridlines walk each axis to its edge.
            let minCell: CGFloat = 3
            let countLong = max(2, min(size.longestEdge, Int(longSide / minCell)))
            let cell = longSide / CGFloat(countLong)
            var path = Path()
            var x = rect.minX
            while x <= rect.maxX + 0.5 {
                path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += cell
            }
            var y = rect.minY
            while y <= rect.maxY + 0.5 {
                path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += cell
            }
            ctx.stroke(path, with: .color(.white.opacity(0.14)), lineWidth: 1)
            ctx.stroke(Path(rect), with: .color(.white.opacity(0.3)), lineWidth: 1)
        }
    }
}

/// Flat, square slider: a thin track, an accent fill, and a square thumb dragged
/// across `range`. End labels in the VT323 body font.
private struct PixelSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    private static let thumb: CGFloat = 14

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let span = max(1, range.upperBound - range.lowerBound)
                let frac = CGFloat(value - range.lowerBound) / CGFloat(span)
                let usable = geo.size.width - Self.thumb
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 6)
                    Rectangle().fill(Color.toolSelected)
                        .frame(width: max(0, frac * usable + Self.thumb / 2), height: 6)
                    Rectangle().fill(Color.white)
                        .frame(width: Self.thumb, height: Self.thumb)
                        .offset(x: frac * usable)
                }
                .frame(height: Self.thumb)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { g in
                        let f = min(1, max(0, (g.location.x - Self.thumb / 2) / usable))
                        value = range.lowerBound + Int((f * CGFloat(span)).rounded())
                    }
                )
            }
            .frame(height: Self.thumb)

            HStack {
                Text("\(range.lowerBound)").font(.pixelBody(15)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text("\(range.upperBound)").font(.pixelBody(15)).foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}
