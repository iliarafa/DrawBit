import SwiftUI

struct DeletePieceSheet: View {
    var onCancel: () -> Void
    var onDelete: () -> Void

    private static let destructiveRed = Color(red: 217.0/255.0, green: 87.0/255.0, blue: 99.0/255.0)

    var body: some View {
        ZStack {
            Color(white: 0.10).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("DELETE PIECE?")
                    .font(.pixel(16))
                    .foregroundStyle(.white)
                    .padding(.top, 24)

                Text("This cannot be undone.")
                    .font(.pixel(11))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button {
                        onCancel()
                    } label: {
                        Text("CANCEL")
                            .font(.pixel(12))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    Button {
                        onDelete()
                    } label: {
                        Text("DELETE")
                            .font(.pixel(12))
                            .foregroundStyle(Self.destructiveRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Self.destructiveRed.opacity(0.15)))
                            .overlay(Capsule().stroke(Self.destructiveRed.opacity(0.6), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}
