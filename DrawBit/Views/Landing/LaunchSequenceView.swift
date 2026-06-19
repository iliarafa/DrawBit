import SwiftUI

/// The intro played once after the user taps PRESS START: the landing page
/// dissolves out, the app-icon logo dissolves in, holds, dissolves out, and then
/// the gallery's solid grey page assembles from black — at which point `onFinished`
/// lets `RootView` uncover the (already laid-out) gallery on top of the finished
/// page. Building the grey page first keeps the background colour continuous
/// (black → grey) so the gallery never "jumps" colour when it appears. Reuses the
/// help page's pixel-dissolve mask.
///
/// Status bar is intentionally NOT hidden: the gallery shows it, so leaving it
/// visible through the intro means the safe area doesn't change at the reveal
/// (which would otherwise shift the gallery content down — the old "bounce").
///
/// Skipped entirely under UI test — `RootView.start()` jumps straight to the
/// gallery so XCUITest never waits on this motion.
struct LaunchSequenceView: View {
    let onFinished: () -> Void

    /// Landing content starts fully present and dissolves to nothing.
    @State private var titleProgress: CGFloat = 1
    /// Logo starts absent, dissolves in, then back out.
    @State private var logoProgress: CGFloat = 0
    /// The gallery's grey page assembles from black as the final beat.
    @State private var pageProgress: CGFloat = 0

    // Tunable beats.
    private let dissolveOut: Double = 0.5
    private let dissolveIn: Double = 0.5
    private let logoHold: Double = 0.4
    private let pageIn: Double = 0.5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Layer A — the landing "page" (matches LandingView so the hand-off
            // from the tap is seamless). DRAWBIT dissolves out; the app-icon logo
            // is an overlay on DRAWBIT so it shares DRAWBIT's exact center and
            // dissolves in/out in place. The overlay doesn't affect layout, so
            // PRESS START stays put.
            VStack(spacing: 48) {
                Text("DRAWBIT")
                    .font(.pixel(72))
                    .foregroundStyle(.white)
                    .pixelDissolve(progress: titleProgress)
                    .overlay {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                            .pixelDissolve(progress: logoProgress)
                    }
                Text("PRESS START")
                    .font(.pixel(18))
                    .foregroundStyle(.white)
                    .pixelDissolve(progress: titleProgress)
            }

            // Layer B — the gallery's grey background assembling from black. Its
            // final solid frame matches GalleryView's bg, so uncovering the gallery
            // changes only the content, never the background colour.
            Color(white: 0.10).ignoresSafeArea()
                .pixelDissolve(progress: pageProgress)
        }
        // Center on the FULL screen (status bar is shown here), matching LandingView
        // so the title doesn't shift between the tap and the intro.
        .ignoresSafeArea()
        .onAppear { runSequence() }
    }

    /// Chain the beats off each animation's completion so each starts only when the
    /// previous finishes: title out → logo in → hold → logo out → grey page in → done.
    private func runSequence() {
        withAnimation(.easeIn(duration: dissolveOut)) {
            titleProgress = 0                       // landing dissolves out
        } completion: {
            withAnimation(.easeOut(duration: dissolveIn)) {
                logoProgress = 1                    // logo dissolves in
            } completion: {
                withAnimation(.easeIn(duration: dissolveOut).delay(logoHold)) {
                    logoProgress = 0                // hold, then logo dissolves out
                } completion: {
                    withAnimation(.easeOut(duration: pageIn)) {
                        pageProgress = 1            // grey page assembles from black
                    } completion: {
                        onFinished()                // uncover the gallery on the finished page
                    }
                }
            }
        }
    }
}
