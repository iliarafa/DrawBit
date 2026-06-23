import SwiftUI

struct NewPieceSheet: View {
    let onCreate: (CanvasSize) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Single source of truth for the custom dial; the field shows it verbatim while
    /// typing, `dim` is the clamped value everything downstream uses.
    @State private var text: String = "32"
    @FocusState private var fieldFocused: Bool

    private var dim: Int {
        min(CanvasSize.maxDimension, max(CanvasSize.minDimension, Int(text) ?? CanvasSize.minDimension))
    }

    private func setDim(_ n: Int) {
        text = String(min(CanvasSize.maxDimension, max(CanvasSize.minDimension, n)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.10).ignoresSafeArea()
                VStack(spacing: 22) {
                    dialRow
                    PixelSlider(value: Binding(get: { dim }, set: { setDim($0) }),
                                range: CanvasSize.minDimension...CanvasSize.maxDimension)
                    presetChips
                    createButton
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
            }
            .navigationTitle("New piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("NEW PIECE").font(.pixel(14)).foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("CANCEL").font(.pixel(12)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .toolbarBackground(Color(white: 0.10), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Preview + number + steppers

    private var dialRow: some View {
        HStack(spacing: 20) {
            CanvasPreview(dimension: dim)
                .frame(width: 84, height: 84)

            HStack(spacing: 16) {
                stepper("−") { setDim(dim - 1) }
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .font(.pixel(26))
                    .foregroundStyle(.white)
                    .tint(Color.toolSelected)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 72)
                    .focused($fieldFocused)
                    .accessibilityIdentifier("NewPiece-dimField")
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused { text = String(dim) }   // normalize on blur
                    }
                stepper("+") { setDim(dim + 1) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stepper(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.pixel(16))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.25), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(label == "+" ? "NewPiece-plus" : "NewPiece-minus")
    }

    // MARK: - Presets

    private var presetChips: some View {
        HStack(spacing: 10) {
            ForEach(CanvasSize.presets) { size in
                let active = size.dimension == dim
                Button {
                    onCreate(size)
                    dismiss()
                } label: {
                    Text("\(size.dimension)")
                        .font(.pixel(12))
                        .foregroundStyle(active ? Color.toolSelected : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(active ? Color.toolSelected.opacity(0.14) : .clear)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(active ? Color.toolSelected : .white.opacity(0.2), lineWidth: 1))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("NewPiece-\(size.rawValue)")
            }
        }
    }

    private var createButton: some View {
        Button {
            onCreate(CanvasSize(dim))
            dismiss()
        } label: {
            Text("CREATE · \(dim) × \(dim)")
                .font(.pixel(12))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.toolSelected.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.toolSelected, lineWidth: 1))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("NewPiece-create")
    }
}

/// A pixel-grid square that *grows with the chosen size* — small at the minimum,
/// filling the frame near the maximum — so the preview reads as "bigger canvas".
/// The square's side is `sqrt`-mapped across the size range so every step is visible;
/// the grid keeps a ~constant on-screen cell, so a larger square also shows more cells.
private struct CanvasPreview: View {
    let dimension: Int

    var body: some View {
        Canvas { ctx, size in
            let maxSide = min(size.width, size.height)
            let minSide = maxSide * 0.26
            let lo = sqrt(Double(CanvasSize.minDimension))
            let hi = sqrt(Double(CanvasSize.maxDimension))
            let frac = max(0, min(1, (sqrt(Double(dimension)) - lo) / (hi - lo)))
            let side = minSide + CGFloat(frac) * (maxSide - minSide)
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2,
                              width: side, height: side)

            ctx.fill(Path(rect), with: .color(Color(white: 0.15)))

            let count = max(2, Int((side / 6).rounded()))
            let cell = side / CGFloat(count)
            var path = Path()
            for i in 0...count {
                let x = rect.minX + CGFloat(i) * cell
                let y = rect.minY + CGFloat(i) * cell
                path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            ctx.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 1)
            ctx.stroke(Path(rect), with: .color(.white.opacity(0.25)), lineWidth: 1)
        }
    }
}

/// On-brand replacement for the native `Slider` (which can't take the app's flat,
/// square pixel styling): a thin track, an accent fill, and a square thumb dragged
/// across `range`.
private struct PixelSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    private static let thumb: CGFloat = 16

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
                Text("\(range.lowerBound)").font(.pixel(8)).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("\(range.upperBound)").font(.pixel(8)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}
