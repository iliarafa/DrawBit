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
/// ## Additive changes (new optional / defaulted attribute) — no new version needed
///
/// `DrawBitSchemaV1` lists the *live* model types (`Piece.self`, `AppSettings.self`),
/// not frozen snapshots. That means you CANNOT add a `DrawBitSchemaV2` that also lists
/// the live types: both versions would compute the same checksum from the same live
/// classes and CoreData aborts with "Duplicate version checksums detected" the moment
/// the migration plan is validated (on-disk launch). The reference-photo fields
/// (`Piece.referenceImageData`, `Piece.referenceOpacity`) were added this way: because
/// they are optional / defaulted, SwiftData performs an inferred lightweight migration
/// automatically when it opens an older store against the updated live model — no new
/// `VersionedSchema` and no stage are required.
///
/// ## Reshaping changes that DO need a real V2 in the future
///
/// For a rename, a removed field, or a data transform, you must introduce a genuinely
/// distinct version. Because V1 points at the live types, the prerequisite is to first
/// FREEZE V1: copy the current model definitions into nested snapshot types
/// (`enum DrawBitSchemaV1 { @Model final class Piece { ...old shape... } }`) so V1's
/// checksum is pinned to the old shape, then:
///
/// 1. Declare `enum DrawBitSchemaV2: VersionedSchema { ... }` listing the live types.
///    Bump `versionIdentifier` to `.init(2, 0, 0)`.
/// 2. Use `MigrationStage.lightweight(...)` (rename/new field — annotate with
///    `@Attribute(originalName:)`) or `MigrationStage.custom(...)` (data reshape, via
///    `willMigrate` / `didMigrate`).
/// 3. Append both schemas to `DrawBitMigrationPlan.schemas`, append the stage to
///    `DrawBitMigrationPlan.stages`, and point `DrawBitApp.swift`'s `Schema(...)` at V2.
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
        []  // Additive reference-photo fields migrate via inference; see the doc above.
    }
}
