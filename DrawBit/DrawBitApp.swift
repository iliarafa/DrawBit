import SwiftUI
import SwiftData

@main
struct DrawBitApp: App {
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
                .task {
                    let ctx = ModelContext(sharedModelContainer)
                    let repo = PieceRepository(context: ctx)
                    try? repo.migrateLegacyPiecesIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
