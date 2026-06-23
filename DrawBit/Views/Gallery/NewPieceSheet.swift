import SwiftUI

struct NewPieceSheet: View {
    let onCreate: (CanvasSize) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var customText: String = ""

    /// A valid in-range custom dimension, or nil (CREATE stays disabled).
    private var customDimension: Int? {
        guard let n = Int(customText),
              n >= CanvasSize.minDimension, n <= CanvasSize.maxDimension else { return nil }
        return n
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.10).ignoresSafeArea()
                VStack(spacing: 0) {
                    ForEach(CanvasSize.presets) { size in
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
                        rowDivider
                    }

                    customRow

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

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    /// CUSTOM: any square N in [min, max]. Odd N gives a true center pixel for mirror.
    private var customRow: some View {
        HStack(spacing: 12) {
            Text("CUSTOM")
                .font(.pixel(16))
                .foregroundStyle(.white)

            TextField("N", text: $customText)
                .keyboardType(.numberPad)
                .font(.pixel(16))
                .foregroundStyle(.white)
                .tint(.white)
                .multilineTextAlignment(.center)
                .frame(width: 64)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.16))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1))
                )
                .accessibilityIdentifier("NewPiece-customField")

            Spacer(minLength: 0)

            Button {
                if let n = customDimension {
                    onCreate(CanvasSize(n))
                    dismiss()
                }
            } label: {
                Text("CREATE")
                    .font(.pixel(12))
                    .foregroundStyle(customDimension == nil ? .white.opacity(0.3) : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(customDimension == nil ? 0.05 : 0.14)))
                    .overlay(Capsule().stroke(Color.white.opacity(customDimension == nil ? 0.1 : 0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(customDimension == nil)
            .accessibilityIdentifier("NewPiece-customCreate")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
