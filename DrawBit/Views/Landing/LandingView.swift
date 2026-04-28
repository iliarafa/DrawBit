import SwiftUI

struct LandingView: View {
    var onStart: () -> Void

    @State private var pressStartVisible: Bool = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 48) {
                Text("DRAWBIT")
                    .font(.pixel(72))
                    .foregroundStyle(.white)
                Text("PRESS START")
                    .font(.pixel(18))
                    .foregroundStyle(.white)
                    .opacity(pressStartVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pressStartVisible)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onStart() }
        .statusBarHidden(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("LandingStart")
        .onAppear { pressStartVisible.toggle() }
    }
}

#Preview {
    LandingView(onStart: {})
}
