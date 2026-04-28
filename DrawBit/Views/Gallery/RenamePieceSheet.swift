import SwiftUI

struct RenamePieceSheet: View {
    @Binding var draft: String
    var onCancel: () -> Void
    var onSave: () -> Void

    @FocusState private var textFieldFocused: Bool

    var body: some View {
        ZStack {
            Color(white: 0.10).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("RENAME")
                    .font(.pixel(16))
                    .foregroundStyle(.white)
                    .padding(.top, 24)

                TextField("Name", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($textFieldFocused)
                    .padding(.horizontal, 20)
                    .onSubmit { onSave() }

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
                        onSave()
                    } label: {
                        Text("SAVE")
                            .font(.pixel(12))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

                Spacer(minLength: 0)
            }
        }
        .onAppear { textFieldFocused = true }
    }
}
