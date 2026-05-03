import SwiftUI
import SwiftData

@main
struct DrawBitApp: App {
    var sharedModelContainer: ModelContainer = {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-UITest-reset")
        let schema = Schema([Piece.self, AppSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    let ctx = ModelContext(sharedModelContainer)
                    let repo = PieceRepository(context: ctx)
                    try? repo.migrateLegacyPiecesIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
