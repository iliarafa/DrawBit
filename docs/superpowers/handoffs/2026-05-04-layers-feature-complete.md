# DrawBit Layers v2 — Feature Complete

**Date:** 2026-05-04
**Amended:** 2026-05-17 — small accuracy patches after Animation v1 shipped (main tip, `EditorView` line numbers, "What's next" section). Layers content itself unchanged.
**Status:** All 4 stages shipped to `main` and pushed to `origin`. The layers feature is done.
**Predecessor doc:** [`2026-05-02-layers-stage1-handoff.md`](./2026-05-02-layers-stage1-handoff.md) — covers Stage 1 in depth and the workflow recipe used across all four stages.

This is the single-page summary of everything Layers v2 accomplished. The next session can read this to skip the conversation history and pick up wherever the user wants.

## State of the world

- At layers shipping, `main` tip was `b092702` (merge of `stage-4-visibility-lock`). For current `main` and any post-layers work, see [`2026-05-09-animation-feature-complete.md`](./2026-05-09-animation-feature-complete.md).
- At shipping, `origin/main` was in sync — nothing pending push.
- Worktree at `.worktrees/layers/` is on branch `layers` at `45f59ee`. Can be removed with `git worktree remove .worktrees/layers` from the main repo when convenient.
- Tests at the time of shipping: 132 unit / 4 UI, all green. Simulator and device-Release compile-checks both green.

## The four stage tags

| Tag                         | Tip commit | Merge into main | Commits in stage |
| --------------------------- | ---------- | --------------- | ---------------- |
| `stage-1-plumbing`          | `9ef4335`  | (fast-forward — pre-2026-05-02 work)    | — |
| `stage-2-readonly-panel`    | `fdade86`  | `4a3b90d`       | 6 |
| `stage-3-add-delete-reorder`| `ce9b948`  | `043d28c`       | 10 |
| `stage-4-visibility-lock`   | `45f59ee`  | `b092702`       | 5 |

(Commit counts include the per-stage fixes caught by reviews — Stage 3 had a particularly active review cycle around the reorder-math regression and the marquee × trash interaction.)

## What ships

User-visible behavior, end-to-end:

- **`LAYERS` button** in the editor's top bar opens a 360pt right-side overlay with a list of layer rows.
- **Each row** shows: a 32×32 thumbnail of just that layer's pixels (with a checkerboard alpha background), the layer name, an eye toggle, and a padlock toggle. The active row is tinted blue.
- **Long-press the name** to rename inline. Empty names and unchanged names don't push undo entries.
- **Action bar** at the bottom of the panel: `+` (add layer), duplicate, trash. Hard cap of 16 layers — `+` and duplicate disable at the cap. Trash with empty active layer skips the confirm dialog; with content shows a confirmation. With one layer remaining, trash is disabled.
- **EDIT / DONE toggle** in the panel header. EDIT exposes drag handles so layers can be reordered via drag; DONE returns to normal mode where long-press rename works again. (The two gestures conflict in `UITableView`'s drag recognizer — toggling explicitly avoids the conflict.)
- **Eye toggle** flips `Layer.isVisible`. Hidden layers don't composite. The Compositor was already aware of `isVisible` from Stage 1; Stage 4 just wired the UI.
- **Padlock toggle** flips `Layer.isLocked`. Locked layers can't be drawn on with pencil, eraser, fill, marquee-define, or Clear. Attempts trigger a 400ms red-border pulse on the row so the user gets visual feedback that the input was heard.
- **Marquee auto-commit** before any layer-list mutation (add, duplicate, delete, reorder, setActive, rename, visibility-toggle, lock-toggle). A floating selection on layer A is folded back into A before the structural change happens. Prevents the floating selection from being orphaned by its source layer disappearing or changing.
- **Persistence**: every layer-mutating action saves through `PieceRepository.saveFrame` so disk and memory stay in sync. Undo and redo also save. Closing and reopening the editor shows exactly what the user left.
- **Stack order**: `frame.layers[0]` is the bottommost; `layers.last` is on top. The panel reverses this for display so the topmost layer sits at the top of the visible list.
- **Single-layer pieces still export byte-identically** to the v1 (pre-Stage-1) code path. Verified by `SingleLayerNonRegressionTests` for all four canvas sizes × four export scales.

## What got added to the codebase

New files (since the start of the layers branch):

- `DrawBit/Views/Editor/LayerRow.swift` — the row view (thumbnail / name / eye / lock).
- `DrawBit/Views/Editor/LayersPanel.swift` — the overlay panel (header, list, action bar, confirmation dialog).
- `DrawBitTests/Drawing/FrameMoveMathTests.swift` — 11 test methods covering the reorder-index math.
- `DrawBitUITests/LayersPanelUITests.swift` — 4 UI test methods (`testOpenPanelAndRenameLayer`, `testAddDrawDeleteFlow`, `testAddDrawDeletePersistsAcrossSessionBoundary`, `testVisibilityAndLockTogglesPersist`).
- `docs/superpowers/handoffs/2026-05-02-layers-stage1-handoff.md` — Stage 1 handoff (predecessor to this doc).

New API surface (existing files):

- `Frame.addLayer(name:)`, `Frame.duplicateActiveLayer(nameSuffix:)`, `Frame.removeLayer(id:)`, `Frame.move(id:toIndex:)`, `Frame.setActive(id:)`, `Frame.setName(id:to:)`, `Frame.setVisible(id:to:)`, `Frame.setLocked(id:to:)` — all `mutating func` on `Frame`.
- `Frame.modelTargetIndex(displayedFrom:newOffset:count:)` — pure `static` helper for the `.onMove` index translation. Lives in the Drawing layer (no SwiftUI), unit-tested.
- `EditorState.commitFloatingSelectionIfAny()` — guarded helper that calls `commitMarquee()` only if a selection is floating.
- `EditorState.lockPulseLayerID: UUID?` — ephemeral session-only field for pulse feedback. Never persisted.
- `EditorView.triggerLockPulse(layerID:)` — sets `lockPulseLayerID`, schedules a 400ms async clear with a same-id check.
- `LayersPanel`'s init: takes `state`, `isPresented`, `onRenameLayer`, `onStructuralChange`, `onDismiss`. The two callbacks let `EditorView` own the persistence seam.
- `ToolBar`'s init: takes `state`, `onUndo`, `onRedo`, `onClear`. Same pattern — `EditorView` does the save after `state.undo()` / `state.redo()`.

Lock guard sites in `EditorView` (each calls `triggerLockPulse(...)` then returns):

- `applyDrawPoint`
- `applyMarqueePoint` (first-touch only — in-progress define/drag and tap-inside-existing-float bypass the guard)
- `handleTap`
- `clearCanvas`

`handleStrokeEnd` has a separate lock-aware branch that calls `state.cancelStroke()` instead of committing a no-op snapshot when the stroke ended on a locked layer.

(Line numbers omitted — `EditorView.swift` has grown with Animation v1; grep for `triggerLockPulse` to find current call sites.)

## Patterns established (worth carrying into other features)

These came from Stage 2 / 3 review cycles and proved themselves repeatedly across all four stages:

1. **Persistence via callback.** Views never call `PieceRepository` directly. They emit intent through callbacks (`onStructuralChange`, `onUndo`, `onRedo`, `onRenameLayer`); `EditorView` does the actual `saveCurrentFrame()` after the in-memory mutation. Keeps the SwiftData seam in one place.

2. **Marquee auto-commit before any layer mutation.** `commitFloatingSelectionIfAny()` is the first call in every layer-mutation closure (rename, add, duplicate, delete-empty-fast-path, delete-confirm, move/reorder, setActive, visibility-toggle, lock-toggle). Prevents floating-selection orphaning.

3. **`onDisappear` saves unconditionally.** Don't gate on `state.selection != nil`. The save is idempotent and gating it loses pixels when a tool switch has cleared the selection.

4. **Pure-logic math gets unit tests.** The reorder-index translation is in `Frame.modelTargetIndex(_:_:_:)` — a `static` function on `Frame` that takes `Int`s and returns `Int?`. Eleven test cases cover 2-, 3-, and 4-layer scenarios in both directions, plus the no-op. Don't re-inline math into a SwiftUI view without unit tests.

5. **SwiftUI `.onMove`'s `newOffset` is a PRE-removal insertion point** in the displayed array, per Apple's `Array.move(fromOffsets:toOffset:)` contract. The "post-removal" interpretation cost a round of fixes mid-Stage 3.

6. **EDIT/DONE toggle gates `.onMove(perform:)` AND `.environment(\.editMode, ...)` together.** Without this, the `UITableView` drag recognizer swallows the long-press rename gesture even with edit mode "inactive".

7. **`PieceThumbnailView` has `.accessibilityAddTraits(.isButton)`** so `XCTest` finds it as `app.buttons["PieceThumbnail"]`.

8. **UI tests verify persistence via close-and-reopen-piece round-trips.** Stage 2's review caught a rename-not-persisted bug because the test only checked in-memory state. Every Stage 3+4 UI test now does `Gallery → reopen → reassert`.

9. **Lock UI feedback uses an ephemeral session-only field on `EditorState`** (`lockPulseLayerID`), set + cleared by `EditorView` via an unstructured `Task` that sleeps 400ms. Same-id check at clear time prevents stomping when a second pulse fires.

10. **`triggerLockPulse` is called BEFORE `return` at every guard site.** The guard isn't silent — users see a red border on the row.

## What review caught (worth remembering)

The cross-cutting (Opus) reviewer caught real bugs in **every single stage**. Per-task (Sonnet) reviews missed them because they're emergent across multiple commits. Specific catches by stage:

- **Stage 2:** rename mutated state but never saved — close-and-reopen lost the rename.
- **Stage 3 (final review):** the "simpler" reorder-math formula was wrong because it assumed `newOffset` is post-removal; SwiftUI gives it pre-removal. Silent data corruption on the most common reorder gesture (drag top down by one slot).
- **Stage 3 (per-task):** trash button's `isEmpty` check evaluated pixel buffer BEFORE the marquee auto-commit, so a layer whose content had been entirely lifted into a marquee selection read as empty and got silently deleted along with the just-restored content.
- **Stage 3 (final review):** `onDisappear` only saved when `state.selection != nil`. Tool-switch clears `selection` (after `commitMarquee` writes pixels back), so dismissing immediately after a tool-switch lost the just-committed pixels.
- **Stage 4 (per-task):** lock guard fired in `applyDrawPoint`, but `handleStrokeBegin` had already taken a no-op snapshot. `handleStrokeEnd` would commit it, polluting the undo stack with empty entries.
- **Stage 4 (final review):** `clearCanvas` (toolbar Clear button) bypassed the lock guard. A locked layer could be cleared anyway — incoherent abstraction.

**Never skip the holistic Opus review before tagging.** It's the difference between "shipped" and "shipped with a glitch the user finds tomorrow."

## Outstanding follow-ups (none blocking, all noted in reviews)

These were deliberately deferred. Pick them up whenever; none of them gate the layers feature being usable today.

- **Schema migration plan.** Stage 1's `Piece.pixels → Piece.frameData` rename will crash any existing-store user (Stage 1 quirk #1). Not blocking until DrawBit goes to TestFlight or the App Store. Add a `SchemaMigrationPlan` (versioned schemas `SchemaV1` → `SchemaV2`) before public distribution.
- **Hit target size.** The eye and lock buttons in `LayerRow` are ~14-18pt taps. Apple's HIG recommends 44pt. A small follow-up commit could wrap both buttons in `.frame(width: 44, height: 44)` or add `.contentShape(Rectangle())` for a larger tap area.
- **`@Bindable var state`** on `LayersPanel` and `ToolBar` is unused (no `$state.foo` projections). Could be `let state` since `@Observable` tracks reads automatically. Style nit.
- **Frame-level 16-cap defense.** `Frame.addLayer` and `Frame.duplicateActiveLayer` don't enforce the 16-layer cap. The view's `.disabled(...)` is the only gate. Defense in depth: `guard layers.count < 16 else { return }` in the model.
- **Undo/redo persistence test.** The save-on-undo follow-up landed without a unit test. A `PieceRepositoryTests`-style test that simulates undo on `EditorState` and asserts the saved frame matches would lock in regression coverage.
- **`v1ExportPNG` reference impl** in `DrawBitTests/Rendering/SingleLayerNonRegressionTests.swift` can be removed now that all stages have shipped, per the spec — or kept as belt-and-suspenders.
- **Undo of a marquee commit doesn't restore the floating state.** Selection isn't on the undo stack, and the active layer isn't moved back when the undo target is a different layer. UX polish.
- **`commitMarquee` doesn't respect lock.** If the user has a floating selection extracted from layer A (before lock), then locks A, then dismisses the editor: `onDisappear` calls `commitMarquee()` unconditionally, which writes the pixels back to the now-locked layer. Pixels are preserved (probably the right semantics — they're the user's work) but it's an edge in the lock contract.

## What's next (if the user wants new work)

- **Animation v1** — *shipped 2026-05-09.* Six stages (`stage-1-animation-plumbing` through `stage-6-animation-export`). See [`2026-05-09-animation-feature-complete.md`](./2026-05-09-animation-feature-complete.md) for the full handoff.
- **iPhone support** — there's an empty stub at `docs/superpowers/plans/2026-04-27-iphone-support.md`. DrawBit is currently iPad-only.
- **Schema migration** — prerequisite for any kind of public distribution. See follow-ups above. Verified still outstanding as of 2026-05-17 (no `SchemaMigrationPlan` / `SchemaV1` / `SchemaV2` in source).

## Source-of-truth docs

Layers v2 (this doc's subject):
- Layers spec: `docs/superpowers/specs/2026-05-02-layers-design.md`
- Layers plan: `docs/superpowers/plans/2026-05-02-layers-implementation.md`
- Stage 1 handoff (predecessor to this doc): `docs/superpowers/handoffs/2026-05-02-layers-stage1-handoff.md`

DrawBit base:
- DrawBit spec: `docs/superpowers/specs/2026-04-19-drawbit-design.md`
- DrawBit plan: `docs/superpowers/plans/2026-04-19-drawbit-implementation.md`

Post-layers work (for reference; not covered by this doc):
- Animation v1 spec: `docs/superpowers/specs/2026-05-05-animation-design.md`
- Animation v1 plan: `docs/superpowers/plans/2026-05-05-animation-implementation.md`
- Animation v1 stages 1–3 handoff: `docs/superpowers/handoffs/2026-05-05-animation-stages-1-3-handoff.md`
- Animation v1 feature-complete handoff: `docs/superpowers/handoffs/2026-05-09-animation-feature-complete.md`

## Workflow recipe (carries forward)

For any new multi-stage work on this codebase:

1. Use `superpowers:writing-plans` to draft the plan (verbatim task descriptions in the plan file).
2. Use `superpowers:subagent-driven-development` to execute. Per-task review gating:
   - Verbatim plan-prescribed tasks → combined spec + code-quality review (Sonnet).
   - Judgment-heavy tasks (action-bar wiring, marquee × layer auto-commit, lock guard) → separate spec review then code-quality review.
3. Always run a final cross-cutting review (Opus, `superpowers:code-reviewer`) before tagging — it catches bugs the per-task reviewers miss.
4. Always pass the absolute project path to `xcodebuild` when working from a worktree: `xcodebuild -project /Users/iliasrafailidis/development/bitme/.worktrees/layers/DrawBit.xcodeproj …`. Without the absolute path, the controller's cwd resolves to the main repo's stale `.xcodeproj`.
5. Stage tag + `--no-ff` merge + push, in that order. Update memory.
