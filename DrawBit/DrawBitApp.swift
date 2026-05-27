import SwiftUI
import SwiftData
import UIKit

@main
struct DrawBitApp: App {
    // App-lifetime DrawBit FM station. Owned here (above the Landing/Gallery/Editor
    // switch) so playback survives navigation and the background; injected into the
    // environment so the gallery's `FMTile` and the pushed `FMScreen` can both drive it.
    @State private var radio = RadioController()

    init() {
        // Under XCUITest, kill UIKit-backed animations (navigation push/pop, sheet
        // and popover presentation, the text edit menu, keyboard show/hide). This
        // lets the app reach "idle" promptly after every event and prevents XCUITest
        // from tapping an element mid-transition — the dominant cause of full-suite
        // flakiness. SwiftUI `.animation(_:value:)` modifiers run on SwiftUI's own
        // timeline and are gated separately at each call site. See `UITestSupport`.
        if UITestSupport.isRunning {
            UIView.setAnimationsEnabled(false)
        }
    }

    var sharedModelContainer: ModelContainer = {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-UITest-reset")
        let schema = Schema(versionedSchema: DrawBitSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        // SchemaMigrationPlan is wired even with zero stages today — the moment
        // a schema-changing V2 is added, the container reload becomes safe
        // without an extra ship-day scramble. See `DrawBitSchema.swift`.
        return try! ModelContainer(for: schema,
                                   migrationPlan: DrawBitMigrationPlan.self,
                                   configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(radio)
                .task {
                    let ctx = ModelContext(sharedModelContainer)
                    let repo = PieceRepository(context: ctx)
                    try? repo.migrateLegacyPiecesIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
