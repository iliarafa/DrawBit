# DrawBit Cleanup Follow-ups — All 13 Closed

**Date:** 2026-05-17
**Status:** All 13 outstanding follow-ups from the layers v2 and animation v1 handoffs are closed on `main` and pushed to `origin`.
**Predecessor docs:**
- [`2026-05-04-layers-feature-complete.md`](./2026-05-04-layers-feature-complete.md) — originated 8 of the 13 follow-ups
- [`2026-05-09-animation-feature-complete.md`](./2026-05-09-animation-feature-complete.md) — originated the other 5

This is the single-page summary of the cleanup pass. The next session can read this to skip the conversation history and pick up wherever you want.

## State of the world

- `main` tip: `b852361` (merge commit `merge: cleanup-followups — close all 13 layers/animation follow-ups`).
- `origin/main` is in sync — nothing pending push.
- All stage tags (`stage-1-plumbing` through `stage-4-visibility-lock` and `stage-1-animation-plumbing` through `stage-6-animation-export`) are still in place on local and remote.
- Tests: **248 unit / 8 UI**, all green. Simulator and device-Release compile-checks both green.
- The `cleanup-followups` branch + the three feature worktrees (`.worktrees/layers/`, `.worktrees/animation/`, `.worktrees/cleanup/`) have been removed.

## The 12 commits

| # | Commit | Subject | Touches |
|---|--------|---------|---------|
| 1 | `732df00` | `refactor(views): drop unused @Bindable; add Frame.maxLayers + cap defense` | 5 view files + Frame |
| 2 | `c7fd231` | `test(rendering): drop v1ExportPNG reference; round-trip + smoke test instead` | SingleLayerNonRegressionTests |
| 3 | `875cedd` | `fix(views): bump eye + lock buttons to 44pt hit targets` | LayerRow |
| 4 | `0b0acf8` | `a11y(animation): explicit labels on FramesStrip controls` | FramesStrip + AnimationStripUITests |
| 5 | `e518f44` | `test(state): regression coverage for undo/redo save path` | New EditorStateUndoPersistenceTests |
| 6 | `7a810ee` | `fix(rendering): cooperative cancellation in GIF + APNG exporters` | exporters + ShareSheet + tests + PieceRepository doc |
| 7 | `a0d5504` | `perf(canvas): memoize onion-skin ghost compositing` | CanvasView |
| 8 | `97d0c54` | `docs(state): document marquee UX edges; defensive lock guard on dismiss` | EditorState + EditorView |
| 9 | `6580f3d` | `perf(state): tighter cap on sequence-structure undo entries` | EditorState + new SequenceUndoMemoryTests |
| 10 | `e0c427c` | `feat(persistence): SchemaMigrationPlan infrastructure (V1 baseline)` | new DrawBitSchema + DrawBitApp + Piece + MigrationTests |
| 11 | `643f710` | `fix(canvas): onion-skin cache invalidates on undo to previous frame` | CanvasView + CanvasHostView + FrameSequence |
| — | `b852361` | merge into main (`--no-ff`) | — |

Commit 11 was the result of the holistic Opus review, which caught one real bug (the onion-skin cache's `Frame.id`-only key returns stale composites after undo on the previous frame) plus two minor cleanups (a missed `@Bindable` in `CanvasHostView` and a duplicated layer-cap constant in `FrameSequence`).

## What each item resolved

Maps to the 13 follow-ups from the predecessor handoffs:

| # | Follow-up | Commit | Notes |
|---|-----------|--------|-------|
| L1 | `@Bindable var state` style nit (layers handoff) | `732df00`, `643f710` | Now `let state: EditorState` on LayersPanel, ToolBar, FramesStrip, CanvasView, CanvasHostView. None used `$state.foo` projections. |
| L2 | Frame-level 16-cap defense | `732df00` | `Frame.maxLayers = 16`. `addLayer` / `duplicateActiveLayer` precondition-trap above the cap. `FrameSequence.layerCap = Frame.maxLayers` (commit 11). |
| L3 | Remove `v1ExportPNG` reference impl | `c7fd231` | Replaced with a real PNG round-trip test (encode → decode → rasterize → byte-compare) + every-size×scale smoke. The `patternedGrid` was tightened to zero RGB on alpha=0 pixels to match what the app actually produces. |
| L4 | Hit target size on eye/lock buttons | `875cedd` | Both buttons now `.frame(width: 44, height: 44).contentShape(Rectangle())`. Row height grows from ~44pt → ~56pt (visible nit, no rework). |
| L5 | Undo/redo persistence unit test | `e518f44` | New `EditorStateUndoPersistenceTests` (2 methods): structural undo + layer-pixel undo, both verify on-disk state matches in-memory after `state.undo()` + `saveFrames`. |
| L6 | `v1ExportPNG` belt-and-suspenders | — | Covered by L3; not a separate item. |
| L7 | Undo of marquee restores floating state | `97d0c54` | **Documented as accepted limitation** in `EditorState.commitMarquee`'s doc comment. The proper fix is a new undo-entry case carrying the full `MarqueeSelection` plus the layer's post-extraction snapshot — an undo-stack refactor with regression risk on shipped marquee behavior. |
| L8 | `commitMarquee` lock edge case | `97d0c54` | **Unreachable today** (verified: only `LayersPanel.onToggleLocked` flips `Layer.isLocked`, and it auto-commits the marquee first via `commitFloatingSelectionIfAny()`). Added a defensive guard in `EditorView.onDisappear` for forward-compat. |
| A1 | Sequence-undo memory profiling | `6580f3d` | Added `EditorState.sequenceStructureUndoLimit = 10` (vs the generic `undoLimit = 50`). Worst-case sequence-undo stack drops from ~3 GiB → ~600 MiB. New `SequenceUndoMemoryTests` (3 methods): pure-math budget assertion + eviction behaviour + layer-pixel-unaffected check. |
| A2 | Onion-skin ghost cache | `a0d5504`, `643f710` | New `OnionSkinCache` class held via `@State`. Compositor walk runs at most once per cache miss. Initial implementation keyed on `Frame.id` only; holistic review caught a stale-image-after-undo bug, fixed by switching to Frame value equality (with `.id` fast-path). |
| A3 | Cancel-during-animated-export | `7a810ee` | `GIFExporter.export` and `APNGExporter.export` are now `throws` and call `try Task.checkCancellation()` at the top of each per-frame loop iteration. ShareSheet wraps in `try?`. **Cancellation has no UI trigger yet** — wiring a CANCEL button (or auto-cancel on dismiss) is the complementary follow-up that activates the checkpoints. |
| A4 | V1 migration off MainActor during share | `7a810ee` | **Documented as recognized non-issue** in `PieceRepository.loadFrames`'s doc comment. `migrateLegacyPiecesIfNeeded()` runs at app launch via `.task` in `DrawBitApp`, so the synchronous-on-main migration path is the V2 fast path in practice. |
| A5 | Accessibility labels on FramesStrip controls | `0b0acf8` | Play/Pause, FPS, Onion-skin, Add, Duplicate, Delete, and EDIT/DONE buttons all have explicit `.accessibilityLabel` (+ hints where useful). Replaces the SF-symbol fallback that would have read "circle.righthalf.filled" etc. to VoiceOver. Also fixed the onion-skin UI test (was reading the SF-symbol name as a state proxy). |
| Bonus | Schema migration plan (L13) | `e0c427c` | New `DrawBit/Models/DrawBitSchema.swift` declares `DrawBitSchemaV1: VersionedSchema` and `DrawBitMigrationPlan: SchemaMigrationPlan`. `DrawBitApp` switches to `Schema(versionedSchema:)` + the migration plan. `Piece.frameData` carries `@Attribute(originalName: "pixels", .externalStorage)` as belt-and-suspenders for any pre-Stage-1 internal-test store. New smoke test in `MigrationTests` covers the plan-backed container open + piece round-trip. |

## New file inventory

```
DrawBit/Models/DrawBitSchema.swift                       (NEW — versioned schema baseline)
DrawBitTests/State/EditorStateUndoPersistenceTests.swift (NEW — 2 tests)
DrawBitTests/State/SequenceUndoMemoryTests.swift         (NEW — 3 tests)
```

Modified: `DrawBit/DrawBitApp.swift`, `DrawBit/Drawing/Frame.swift`, `DrawBit/Drawing/FrameSequence.swift`, `DrawBit/Gestures/CanvasHostView.swift`, `DrawBit/Models/Piece.swift`, `DrawBit/Persistence/PieceRepository.swift`, `DrawBit/Rendering/APNGExporter.swift`, `DrawBit/Rendering/GIFExporter.swift`, `DrawBit/State/EditorState.swift`, `DrawBit/Views/Editor/CanvasView.swift`, `DrawBit/Views/Editor/EditorView.swift`, `DrawBit/Views/Editor/FramesStrip.swift`, `DrawBit/Views/Editor/LayerRow.swift`, `DrawBit/Views/Editor/LayersPanel.swift`, `DrawBit/Views/Editor/ShareSheet.swift`, `DrawBit/Views/Editor/ToolBar.swift`, `DrawBitTests/Persistence/MigrationTests.swift`, `DrawBitTests/Rendering/APNGExporterTests.swift`, `DrawBitTests/Rendering/GIFExporterTests.swift`, `DrawBitTests/Rendering/SingleLayerNonRegressionTests.swift`, `DrawBitUITests/AnimationStripUITests.swift`.

## Patterns + constants now in the codebase

Worth knowing for any future work:

- **`Frame.maxLayers = 16`** in `DrawBit/Drawing/Frame.swift` — single source of truth for the per-frame layer cap. `Frame.addLayer` and `Frame.duplicateActiveLayer` precondition-trap above this. UI gates via `.disabled(state.frame.layers.count >= Frame.maxLayers)`. `FrameSequence.layerCap` aliases it.
- **`EditorState.sequenceStructureUndoLimit = 10`** in `DrawBit/State/EditorState.swift` — caps `.sequenceStructure` entries separately from the generic `undoLimit = 50`. Worst-case memory: ~600 MiB. `EditorState.push` evicts oldest sequence-structure entries past this cap.
- **`OnionSkinCache`** at the top of `DrawBit/Views/Editor/CanvasView.swift` — class held via `@State`. Cache key is the full `Frame` value (Equatable), with `Frame.id` as a fast-path. Invalidated on `.onChange(of: state.activeFrameIndex)` as belt-and-suspenders. Same-stroke body re-evals hit the cache; undo on the previous frame correctly invalidates via value inequality.
- **`DrawBitSchemaV1` + `DrawBitMigrationPlan`** in `DrawBit/Models/DrawBitSchema.swift` — V1 is the only declared version today; stages list is empty. The doc comment on the file explains exactly how to add V2 when needed.
- **`Piece.frameData` has `@Attribute(originalName: "pixels", .externalStorage)`** — defensive against any pre-Stage-1 store (none in the wild, but cheap insurance).
- **`GIFExporter.export(...)` and `APNGExporter.export(...)` are `throws`** — every per-frame iteration calls `try Task.checkCancellation()`. Callers wrap in `try?` or `try` (tests). No CANCEL UI exists yet to actually fire the cancellation; the checkpoints are dormant forward-compat.
- **`commitFloatingSelectionIfAny()`** on `EditorState` — still the canonical first call in every layer/frame-mutation closure. Stage 4+ patterns continue to apply.

## Documented limitations (not bugs, deliberately accepted)

These are flagged in code comments and in the predecessor handoffs. Don't "fix" them without reading the doc comments first — each has a reasoning that may still apply:

- **Undo of a marquee commit collapses lasso+drag+commit into one step** rather than returning to the floating-selection state. `EditorState.commitMarquee` doc comment explains. Fixing properly requires a new `UndoEntry` case carrying the `MarqueeSelection`.
- **`commitMarquee` doesn't check `Layer.isLocked`** — case is unreachable today (the lock toggle auto-commits first), defensive guard exists in `EditorView.onDisappear`.
- **V1→V2 migration runs synchronously on MainActor inside `loadFrames`** — mitigated in practice by `migrateLegacyPiecesIfNeeded()` running at app launch. Lifting to a background task with the `context.save()` re-routed to main is the proper fix if it ever becomes a real hitch.
- **Animated-export cancellation has no UI trigger** — `try Task.checkCancellation()` checkpoints are wired but dormant until a CANCEL button or auto-cancel-on-dismiss is added.

## What's still genuinely outstanding (not from "the 13")

- **iPhone support** — empty plan stub at `docs/superpowers/plans/2026-04-27-iphone-support.md`. DrawBit remains iPad-only.
- **CANCEL button for exports** — the exporter checkpoints are ready; UI wiring is the next step.
- **Actual `DrawBitSchemaV2`** — infrastructure is in; trigger the V2 path when a real schema change ships. The doc comment in `DrawBit/Models/DrawBitSchema.swift` describes exactly how to add it.
- **Layer-row height grew from ~44pt to ~56pt** with the hit-target fix (commit `875cedd`). The list scrolls fine; no rework, just a visual nit.

## Reproducing the holistic-review bug catch (for context)

The Opus review found the onion-skin cache stale-image bug via this user-reachable gesture:

1. User on frame N, has onion skin on, strokes on frame N. Push `.layerPixels` undo entry.
2. User taps frame N+1 in the strip. `.onChange(of: activeFrameIndex)` fires → cache invalidates.
3. Body renders. Cache populates with composite of frame N (post-stroke pixels).
4. User taps Undo. `state.undo()` reverts frame N's layer pixels. `activeFrameIndex` stays at N+1.
5. Body re-renders (Observable). `previousFrameImage()` → `onionCache.image(for: frames[N])`. With the old `Frame.id`-only key, the cache hit returned the **stale** post-stroke composite. **Onion-skin ghost was wrong.**

Fixed in `643f710` by switching to Frame value equality (with `.id` fast-path for cross-frame transitions). Pre-cache (before `a0d5504`) the render was always fresh, so this was a regression introduced by the memoization.

## Source-of-truth docs

- Layers v2 feature handoff: `docs/superpowers/handoffs/2026-05-04-layers-feature-complete.md`
- Layers v2 stage-1 handoff (still relevant for quirks): `docs/superpowers/handoffs/2026-05-02-layers-stage1-handoff.md`
- Animation v1 feature handoff: `docs/superpowers/handoffs/2026-05-09-animation-feature-complete.md`
- Animation v1 stages-1-3 handoff: `docs/superpowers/handoffs/2026-05-05-animation-stages-1-3-handoff.md`
- DrawBit base spec: `docs/superpowers/specs/2026-04-19-drawbit-design.md`
- Layers spec: `docs/superpowers/specs/2026-05-02-layers-design.md`
- Animation spec: `docs/superpowers/specs/2026-05-05-animation-design.md`
- This handoff: the one you're reading.

## Memory entries updated for next session

The auto-memory has been updated:
- `MEMORY.md` — index entry added for this cleanup
- `project_cleanup_followups.md` — full pointer doc (parallels what's here)
- `project_layers_handoff.md` and `project_animation_progress.md` left as-is (still accurate for their domains)

The next session can resume from any of three places:
- **Continue feature work**: tackle iPhone support (the empty plan stub), or wire a CANCEL UI for exports.
- **Resume DrawBit-as-product work**: think about price-bump positioning now that both layers + animation are stable.
- **Pivot somewhere else**: codebase is in a clean, tested, documented state — happy to put it down for a while.
