import SwiftUI

struct NewPieceSheet: View {
    let onCreate: (CanvasSize) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.10).ignoresSafeArea()
                VStack(spacing: 0) {
                    ForEach(CanvasSize.allCases) { size in
                        Button {
                            onCreate(size)
                            dismiss()
                        } label: {
                            HStack {
                                Text(size.displayName)
                                    .font(.pixel(16))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(size.pixelCount) pixels")
                                    .font(.pixel(11))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("NewPiece-\(size.rawValue)")
                        if size != CanvasSize.allCases.last {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 0.5)
                                .padding(.horizontal, 20)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .navigationTitle("New piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("NEW PIECE")
                        .font(.pixel(14))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
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
}
