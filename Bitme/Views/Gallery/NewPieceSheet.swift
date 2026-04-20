import SwiftUI

struct NewPieceSheet: View {
    let onCreate: (CanvasSize) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(CanvasSize.allCases) { size in
                Button {
                    onCreate(size)
                    dismiss()
                } label: {
                    HStack {
                        Text(size.displayName)
                            .font(.pixel(16))
                        Spacer()
                        Text("\(size.pixelCount) pixels")
                            .foregroundStyle(.secondary)
                            .font(.pixel(11))
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("NewPiece-\(size.rawValue)")
            }
            .navigationTitle("New piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("NEW PIECE")
                        .font(.pixel(14))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.pixel(12))
                }
            }
        }
    }
}
