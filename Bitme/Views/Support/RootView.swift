import SwiftUI

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
            GalleryView(onHome: { screen = .landing })
        }
    }
}
