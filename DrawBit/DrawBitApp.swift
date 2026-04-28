import SwiftUI
import SwiftData

@main
struct DrawBitApp: App {
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
