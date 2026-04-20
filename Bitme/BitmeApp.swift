import SwiftUI
import SwiftData

@main
struct BitmeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(
            for: [Piece.self, AppSettings.self],
            inMemory: ProcessInfo.processInfo.arguments.contains("-UITest-reset")
        )
    }
}
