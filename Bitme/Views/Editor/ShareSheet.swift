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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Scale", selection: $selectedScale) {
                        ForEach([1, 2, 4, 8, 16], id: \.self) { s in
                            let edge = piece.size.dimension * s
                            Text("\(s)× · \(edge) × \(edge)")
                                .font(.pixel(12))
                                .tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("SCALE")
                        .font(.pixel(11))
                }
                Section {
                    Button {
                        share()
                    } label: {
                        Text("SHARE")
                            .font(.pixel(14))
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EXPORT")
                        .font(.pixel(14))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.pixel(12))
                }
            }
        }
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
