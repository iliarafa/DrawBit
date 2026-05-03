# DrawBit Layers v2 — Handoff after Stage 1

**Date:** 2026-05-02
**Status:** Stage 1 merged to `main`. Stages 2–4 pending.

This document is the entry point for the next session. The previous session built Stage 1 of the layers feature using the `superpowers:subagent-driven-development` workflow — implementer + reviewer subagent per task — and the conversation grew long enough to warrant a fresh start.

## Where we are

- `main` is at commit `9ef4335`, tagged `stage-1-plumbing`. 17 commits ahead of where we started.
- The `layers` branch has been fast-forwarded into `main` and the worktree at `.worktrees/layers/` is still in place. To continue work, resume in the worktree (it's already on the `layers` branch and tracks `main`).
- Tests: 121 unit tests + 2 UI tests all passing.
- Build: green for both simulator and `generic/platform=iOS` Release.
- Verified working on user's real iPad (after a one-time app delete to clear the old SwiftData store — see "Quirks" below).

## Source of truth documents

- **Spec:** [`docs/superpowers/specs/2026-05-02-layers-design.md`](../specs/2026-05-02-layers-design.md)
- **Plan:** [`docs/superpowers/plans/2026-05-02-layers-implementation.md`](../plans/2026-05-02-layers-implementation.md)
- **Brainstorm wireframe (still on disk):** `.superpowers/brainstorm/<session-dir>/content/layers-panel-placement.html`

The plan's task descriptions are verbatim — when dispatching implementer subagents, paste the full task text from the plan file. Do NOT make subagents read the plan file (per the subagent-driven-development skill's "Never" list).

## What's done (Stage 1 — plumbing only)

All Stage 1 tasks (1.1–1.15) merged. Specifically:

- Pure-logic value types in `DrawBit/Drawing/`: `Layer`, `Frame`, `FrameCodec` (versioned binary format with `"DBFR"` magic prefix).
- New rendering: `Compositor` (topmost-non-transparent-wins rule), `bufferToCGImage` (replaces `pixelsToCGImage`), `LayerThumbnailRenderer`.
- `PNGExporter.export(frame:size:scale:)` and `ThumbnailRenderer.render(frame:size:targetEdge:)` both take a Frame now.
- `Piece.pixels` was renamed to `Piece.frameData` and uses `@Attribute(.externalStorage)`.
- `PieceRepository` has `loadFrame(piece:)`, `saveFrame(piece:_:)`, and `migrateLegacyPiecesIfNeeded()` (eager + per-read defense-in-depth).
- `EditorState` owns a `Frame`; undo storage is now a tagged enum `UndoEntry.layerPixels(layerID:before:)` for cheap drawing snapshots vs `.frameStructure(before:)` for whole-Frame structural changes.
- `EditorView`, `CanvasView`, `ShareSheet`, `CanvasHostView` all route through the Compositor.
- `DrawBitApp` runs eager migration in a `.task` modifier on app boot.
- The byte-identity non-regression test (`SingleLayerNonRegressionTests`) passes for all 4 sizes × 4 scales — proves a single-layer piece exports byte-identically to the v1 code path. This is the gate test for the entire feature.

User-visible changes after Stage 1: **none.** No layers panel, no LAYERS button. Every existing piece is now internally a single-layer Frame; users see the app as before.

## What remains

Each stage merges to `main` independently after its tests pass and a manual on-device check.

### Stage 2 (Tasks 2.1–2.4) — Read-only layers panel

Adds the toggleable overlay panel, `LAYERS` button in the top bar, and a layer row with thumbnail/name/eye/lock icons. **Read-only:** rename works (long-press), but no add/delete/reorder yet. Action bar shows disabled `+`, duplicate, `×` icons as placeholders.

### Stage 3 (Tasks 3.1–3.4) — Add / delete / duplicate / reorder

The action bar becomes functional. Drawing now routes to the active layer (already plumbed in Stage 1 — Stage 3 just adds the UI to switch active). Marquee × layer auto-commit on layer change. Hard cap of 16 layers enforced.

### Stage 4 (Tasks 4.1–4.3) — Visibility + lock

Eye icon and padlock become functional. Lock guard prevents drawing on locked layers and pulses the row briefly. Hidden layers don't composite.

## Workflow recipe for the next session

1. Read this file and confirm orientation.
2. Read the plan to identify the next task (start at Task 2.1).
3. `cd /Users/iliasrafailidis/development/bitme/.worktrees/layers/`. Confirm on `layers` branch.
4. Use `superpowers:subagent-driven-development` skill to drive implementation:
   - Dispatch implementer subagent with **full task text** from the plan + working directory + test commands.
   - For verbatim plan-prescribed tasks (most of Stages 2–4): one combined spec + code-quality review per task is fine.
   - For judgment-heavy tasks (the action bar wiring, marquee × layer auto-commit, lock guard): separate spec + code-quality reviews.
5. After each stage: run full test suite, do manual device check, tag (e.g., `stage-2-readonly-panel`), fast-forward merge to `main`.

## Quirks discovered in Stage 1 — read these before starting

### 1. SwiftData schema rename does NOT auto-migrate

Renaming `Piece.pixels` → `Piece.frameData` broke the on-device persistence store. SwiftData threw `loadIssueModelContainer` on the user's iPad and crashed at the `try!` in `DrawBitApp.swift:10`. Workaround used: deleted the app from the device to clear the SwiftData files. Worked fine after reinstall.

**Implication for shipping to TestFlight or the App Store:** any existing user with a v1-schema store would hit the same crash. Before shipping any version with a schema change, add a `SchemaMigrationPlan` (versioned schemas: `SchemaV1`, `SchemaV2`, with a migration stage). The app has no users yet, so this is not blocking — but it's a real follow-up before public release.

### 2. `pixelsToCGImage` compatibility shim — do NOT recreate

Task 1.10 temporarily added a `pixelsToCGImage(_ grid: PixelGrid)` shim to `PixelsToCGImage.swift` so the project would build during the multi-task refactor. Task 1.12 removed it. The file should contain only `bufferToCGImage(_:)`. Don't add the shim back.

### 3. xcodebuild scheme runs UI tests by default

The DrawBit scheme generated by xcodegen runs only the UI test bundle when no `-only-testing` is specified. Always pass `-only-testing:DrawBitTests` (or a sub-path) to scope to unit tests. Full unit-test bundle takes ~2 seconds; UI tests take ~20 seconds.

### 4. `Layer.init` defensively copies its `pixels: Data`

Mirrors the `PixelGrid.init(data:size:)` pattern. A sliced `Data` with non-zero `startIndex` is normalized via `Data(pixels)` so downstream `CGDataProvider` reads the right bytes. Test: `LayerTests.testSlicedPixelsDataIsNormalized`.

### 5. `Frame.init` enforces three preconditions

- Non-empty layers
- `activeLayerID` is in `layers`
- All layers have the same `pixels.count`

`FrameCodec.decode` pre-validates the third condition and throws `DecodeError.malformed` instead of letting `Frame.init` precondition-trap on malformed input.

### 6. Stack order: bottom-up in code, top-down in UI

`frame.layers[0]` is the bottommost (drawn first). `layers.last` is on top (drawn last). The UI panel reverses this for display so the topmost layer sits at the top of the visible list.

### 7. No-opacity scope is intentional

Every layer is forced to 100% alpha. The Compositor preserves the "alpha is always 0 or 255" rendering invariant. **Do NOT add per-layer opacity in Stages 2–4** — it was deliberately scoped out to keep the rendering pipeline simple. The user explicitly chose this trade-off after concerns about regressions.

### 8. Marquee × layers interaction needs auto-commit

Stage 3's plan (Task 3.3) requires that any layer-mutating operation (add/delete/reorder/setActive/setName) auto-commits any floating marquee selection first, mirroring the existing `setTool` pattern. This avoids the ambiguity of "what does the floating selection mean if its source layer is gone?".

### 9. Reviews catch real bugs — don't skip them

Code-quality reviews in Stage 1 caught:
- Missing defensive `Data` copy in `Layer.init` (would have silently broken downstream rendering with sliced Data).
- Missing size-consistency precondition in `Frame.init` (silent invariant gap).
- `FrameCodec.decode` could trigger Frame.init's precondition trap on mismatched pixel sizes (denial-of-service on corrupt input).

The reviewer subagent (`superpowers:code-reviewer`) is worth using on every non-trivial task.

## Outstanding follow-ups (not blocking Stage 2)

- The reference v1 export implementation (`v1ExportPNG`) inside `DrawBitTests/Rendering/SingleLayerNonRegressionTests.swift` can be removed once all four stages have shipped, per the spec. Currently kept as belt-and-suspenders.
- Schema migration plan for shipping (see Quirk #1).

## User context — important for the next session

- User explicit concerns: "don't make it glitchy," "I don't want this to break the app." This shaped the entire approach — staged delivery, byte-identity tests, no opacity. **Honor this conservatism in Stages 2–4** — when reviewers flag issues, fix them; when in doubt, scope down rather than scope up.
- User prefers plain-language explanations over Swift/framework jargon during conversation. Save jargon for spec/plan documents. (See feedback memory `feedback_explanations.md`.)
- The app has not been distributed yet. Migration concerns are local-only for now.
- DrawBit ships at $4.99 one-time, no IAP. Layers + animation are the path to a price bump.
