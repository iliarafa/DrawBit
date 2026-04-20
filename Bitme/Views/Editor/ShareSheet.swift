import SwiftUI
import UIKit

struct ShareSheet: View {
    let piece: Piece
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScale: Int

    init(piece: Piece) {
        self.piece = piece
        self._selectedScale = State(initialValue: Self.defaultScale(for: piece.size))
    }

    private let scales = [1, 2, 4, 8, 16]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.10).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("SCALE")
                        .font(.pixel(11))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 8)

                    VStack(spacing: 8) {
                        ForEach(scales, id: \.self) { s in
                            scaleRow(scale: s)
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        share()
                    } label: {
                        Text("SHARE")
                            .font(.pixel(14))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                    }
                    .padding(.bottom, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EXPORT")
                        .font(.pixel(14))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("CANCEL")
                            .font(.pixel(12))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .toolbarBackground(Color(white: 0.10), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func scaleRow(scale s: Int) -> some View {
        let edge = piece.size.dimension * s
        let isSelected = s == selectedScale
        return Button {
            selectedScale = s
        } label: {
            HStack {
                Text("\(s)×")
                    .font(.pixel(14))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(edge) × \(edge)")
                    .font(.pixel(11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isSelected ? 0.10 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.15),
                            lineWidth: isSelected ? 2 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func defaultScale(for size: CanvasSize) -> Int {
        switch size {
        case .s16: 16
        case .s32: 16
        case .s64: 8
        case .s128: 4
        }
    }

    private func share() {
        let grid = PixelGrid(data: piece.pixels, size: piece.size)
        guard let data = PNGExporter.export(grid: grid, scale: selectedScale) else { return }
        let filename = "\(piece.effectiveName)-\(selectedScale)x.png".replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.activeWindow?.rootViewController?.present(vc, animated: true)
        dismiss()
    }
}

private extension UIApplication {
    var activeWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }
}
