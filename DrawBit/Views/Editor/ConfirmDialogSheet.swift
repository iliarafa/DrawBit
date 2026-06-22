import SwiftUI

/// Themed confirmation dialog used across the editor (delete frame / delete layer /
/// remove reference). Presented as a `.sheet` so it reads as the app's own pixel UI
/// instead of the native gray `.confirmationDialog`. Mirrors the gallery's
/// `DeletePieceSheet` visual language (dark surface, pixel font, capsule buttons,
/// destructive red) so every confirm in the app looks the same.
struct ConfirmDialogSheet: View {
    let title: String
    /// Optional supporting line under the title. Pass `nil` for a title-only prompt.
    var message: String? = nil
    let confirmLabel: String
    /// When true the confirm button uses the destructive-red treatment.
    var isDestructive: Bool = true
    var onCancel: () -> Void
    var onConfirm: () -> Void

    private var accentColor: Color { isDestructive ? Color.destructive : .white }

    var body: some View {
        ZStack {
            Color(white: 0.10).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(title)
                    .font(.pixel(16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                    .padding(.horizontal, 20)

                if let message {
                    Text(message)
                        .font(.pixel(11))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 20)
                }

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
                    .accessibilityIdentifier("ConfirmDialog.cancel")

                    Button {
                        onConfirm()
                    } label: {
                        Text(confirmLabel)
                            .font(.pixel(12))
                            .foregroundStyle(accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(accentColor.opacity(0.15)))
                            .overlay(Capsule().stroke(accentColor.opacity(0.6), lineWidth: 1))
                    }
                    .accessibilityIdentifier("ConfirmDialog.confirm")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}
