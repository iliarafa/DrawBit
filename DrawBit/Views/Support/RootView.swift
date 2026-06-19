import SwiftUI

/// Central detector for "are we running under the XCUITest harness?".
///
/// Every UI test launches with at least `-UITest-reset` (in-memory store), so the
/// presence of any `-UITest*` argument is a reliable, production-safe signal that
/// we're in a UI test. We use it to disable animations: a running animation means
/// XCUITest never sees the app reach "idle" (its automatic post-event sync point),
/// and a mid-transition element can satisfy `waitForExistence` while not yet being
/// stably hittable — both classic sources of full-suite flakiness.
enum UITestSupport {
    static let isRunning: Bool =
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-UITest") }
}

enum RootScreen { case landing, launching, gallery }

struct RootView: View {
    @State private var screen: RootScreen
    /// True only when the gallery is entered via the launch sequence, so it plays
    /// its staggered element intro (false on the direct/UI-test path).
    @State private var galleryPlaysIntro = false

    init() {
        let skip = ProcessInfo.processInfo.arguments.contains("-UITest-skipLanding")
        _screen = State(initialValue: skip ? .gallery : .landing)
    }

    var body: some View {
        ZStack {
            // Persistent dark backing so nothing light shows through during the intro.
            Color.black.ignoresSafeArea()

            switch screen {
            case .landing:
                LandingView(onStart: start)
            case .launching:
                // The intro: title out → logo in/out → grey page builds. Its final
                // frame is the gallery's grey page, so the swap to the gallery (same
                // grey bg, elements still hidden) is seamless.
                LaunchSequenceView(onFinished: {
                    galleryPlaysIntro = true
                    screen = .gallery
                })
                .transition(.identity)
            case .gallery:
                GalleryView(playIntro: galleryPlaysIntro)
                    .transition(.identity)
            }
        }
    }

    /// Tapping PRESS START. Under UI test we skip the intro entirely — a running
    /// multi-stage animation would make XCUITest wait, and `LandingScreenTests`
    /// expects the gallery immediately after the tap.
    private func start() {
        screen = UITestSupport.isRunning ? .gallery : .launching
    }
}
