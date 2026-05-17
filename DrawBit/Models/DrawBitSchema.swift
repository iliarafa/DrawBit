import Foundation
import SwiftData

/// Versioned schema declarations for DrawBit's SwiftData store.
///
/// Today there's only one declared version (`DrawBitSchemaV1` = the schema as
/// shipped through layers v2 + animation v1). This file exists primarily as
/// infrastructure: when the next schema change lands (renamed property, new
/// `@Model`, removed field), add a `DrawBitSchemaV2` enum mirroring V1 and
/// add a `MigrationStage` to `DrawBitMigrationPlan.stages` that bridges the
/// two. Without this scaffolding in place from day one, users with an existing
/// store would hit `loadIssueModelContainer` and crash on first launch of the
/// new binary (the failure mode the layers Stage-1 handoff flagged).
///
/// ## Adding a V2 in the future
///
/// 1. Declare `enum DrawBitSchemaV2: VersionedSchema { ... }` listing the new
///    model types. Bump `versionIdentifier` to `.init(2, 0, 0)`.
/// 2. If the changes are simple (renamed property, new optional field), use
///    `MigrationStage.lightweight(fromVersion:toVersion:)`. Annotate the new
///    property with `@Attribute(originalName: "oldName")` so SwiftData can
///    correlate the rename.
/// 3. If data needs to be reshaped, use `MigrationStage.custom(...)` with
///    `willMigrate` / `didMigrate` closures that walk records and transform
///    them in place.
/// 4. Append the new schema to `DrawBitMigrationPlan.schemas`, append the
///    stage to `DrawBitMigrationPlan.stages`, and update the `Schema(...)`
///    construction in `DrawBitApp.swift` to use the latest version.
///
/// ## Defensive measure for any pre-Stage-1 V1 store
///
/// `Piece.frameData` carries `@Attribute(originalName: "pixels", ...)` so that
/// any store originating from before the Stage-1 column rename auto-migrates
/// the column. Public distribution never shipped a `pixels`-column build, so
/// the only stores this would affect are internal-test devices that were
/// never upgraded. Cheap belt-and-suspenders.
enum DrawBitSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Piece.self, AppSettings.self]
    }
}

enum DrawBitMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [DrawBitSchemaV1.self]
    }
    static var stages: [MigrationStage] {
        []  // No migrations yet — V1 is the only declared version.
    }
}
