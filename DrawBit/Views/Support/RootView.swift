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

enum RootScreen { case landing, gallery }

struct RootView: View {
    @State private var screen: RootScreen

    init() {
        let skip = ProcessInfo.processInfo.arguments.contains("-UITest-skipLanding")
        _screen = State(initialValue: skip ? .gallery : .landing)
    }

    var body: some View {
        switch screen {
        case .landing:
            LandingView(onStart: { screen = .gallery })
        case .gallery:
            GalleryView()
        }
    }
}
