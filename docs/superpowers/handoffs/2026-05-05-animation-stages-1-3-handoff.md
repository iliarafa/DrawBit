# DrawBit Animation v1 — Stages 1–3 Handoff

**Date:** 2026-05-05
**Status:** Stages 1, 2, 3 of 6 shipped to `main` and pushed to `origin`. Stages 4–6 + final integration remaining.
**Predecessor docs:**
- Spec: [`docs/superpowers/specs/2026-05-05-animation-design.md`](../specs/2026-05-05-animation-design.md)
- Plan: [`docs/superpowers/plans/2026-05-05-animation-implementation.md`](../plans/2026-05-05-animation-implementation.md)
- Layers v2 handoff (the workflow recipe this builds on): [`2026-05-04-layers-feature-complete.md`](./2026-05-04-layers-feature-complete.md)

This is the mid-feature handoff. The next session can read this to pick up Stage 4.

## State of the world

- `main` tip: `6b3292c` (merge of `stage-3-animation-strip`).
- `origin/main` is in sync — nothing pending push.
- Worktree at `.worktrees/animation/` is on branch `animation` at `1a89ecb`. It can be reused for Stage 4 — keep it; do not remove.
- Tests at the time of this handoff: **177 unit / 7 UI**, all green. Device-Release compile-check green.

The Layers v2 worktree at `.worktrees/layers/` is still around from the prior feature. It can be removed with `git worktree remove .worktrees/layers` whenever convenient — independent of animation work.

## The three stage tags

| Tag                          | Tip commit | Merge into main | Commits in stage (incl. reviews) |
| ---------------------------- | ---------- | --------------- | -------------------------------- |
| `stage-1-animation-plumbing` | `14b587b`  | `bb6b95d`       | 7 (incl. one cleanup)            |
| `stage-2-animation-frame-ops`| `abbc5cc`  | `588b62a`       | 5 (incl. one cleanup)            |
| `stage-3-animation-strip`    | `1a89ecb`  | `6b3292c`       | 7 (incl. one cleanup)            |

Each stage's cleanup commit was triggered by the holistic Opus review and addressed real findings before tagging. **The holistic review continues to earn its keep** — Stage 3 caught a Critical bug (trash-button delete-bypass when content is in a floating marquee — the same shape as the Layers v2 Stage 3 bug that bit during its review).

## What ships

User-visible behavior, end-to-end after Stage 3:

- **The editor has a 60-pt frame strip across the bottom**, between the canvas and the bottom toolbar. Always visible.
- **Single-frame Pieces look identical to today** — the strip shows one thumbnail. The `+` button is always available; duplicate / trash become available in EDIT mode.
- **Tap any frame thumbnail** to switch the active frame. The frame's UUID highlight follows the array even after reorders.
- **Long-press a frame thumbnail** to rename it inline. Empty / unchanged names abandon. Tapping another frame, toggling EDIT, or pressing Return commits.
- **EDIT / DONE toggle** in the strip — EDIT mode reveals duplicate (`plus.square.on.square`) and trash buttons. The toggle also commits any in-flight rename.
- **Add / duplicate / delete frames.** Hard cap of 60. The trash button greys out at 1 frame; `+` and duplicate grey out at 60.
- **Delete with content shows a confirmation dialog**; empty frames fast-path delete.
- **Marquee auto-commit** before any frame mutation — adding, deleting, renaming, switching active frame all fold a floating selection back into its source frame first. The Stage 3 holistic review caught the case where the content check ran *before* the auto-commit, masking an "all content was floating" frame as empty; that's now fixed.
- **Persistence:** every frame-mutating action saves through `PieceRepository.saveFrames(piece:frames:activeFrameIndex:fps:)`. Tapping a frame to switch active also saves *if* the marquee was committed as a side effect. Closing and reopening the editor shows exactly what the user left — round-trip verified by `AnimationStripUITests`.
- **No playback yet.** No play/pause button, no FPS picker. Stage 4.
- **No onion skin yet.** Stage 5.
- **No animated export yet** — PNG export still produces a single static image of the current frame. Stage 6.

## What got added to the codebase across Stages 1–3

### New files

```
DrawBit/Drawing/FrameSequence.swift              (Stage 2)  pure-logic mutators for [Frame] sequences
DrawBit/Rendering/FrameThumbnailRenderer.swift   (Stage 3)  9-line shim over ThumbnailRenderer
DrawBit/Views/Editor/FrameRow.swift              (Stage 3)  single-frame thumbnail row view
DrawBit/Views/Editor/FramesStrip.swift           (Stage 3)  bottom-strip view with action bar + EDIT toggle
DrawBitTests/Drawing/FrameSequenceTests.swift    (Stage 2)  16 tests (8 frame-level + 8 layer-cascade)
DrawBitTests/Drawing/FrameCodecSequenceTests.swift (Stage 1) 7 tests covering V2 round-trip + V1 fallback + fps clamp
DrawBitTests/Models/PieceTests.swift              (extended) V2-blob assertions
DrawBitTests/Rendering/SingleFrameNonRegressionTests.swift (Stage 1) PNG byte-identity gate
DrawBitTests/Rendering/FrameThumbnailRendererTests.swift   (Stage 3)
DrawBitUITests/AnimationStripUITests.swift        (Stage 3)  add → scrub → persistence round-trip
```

### New API surface (existing files)

- `Frame.id: UUID` (let), `Frame.name: String` (var) — Stage 1.
- `FrameCodec.encodeSequence(frames:activeFrameIndex:fps:)`, `FrameCodec.decodeSequence(_:)`, `FrameCodec.hasV2SequenceMagicPrefix(_:)`, `FrameCodec.decodeAnyFrameData(_:fallbackByteCount:)` (consolidating helper) — Stage 1.
- `FrameCodec.defaultFPS: Int = 12`, `FrameCodec.sequenceMagic: [UInt8]`, `FrameCodec.sequenceCurrentVersion: UInt8 = 1` — Stage 1.
- `FrameSequence.frameCap: Int = 60`, `FrameSequence.layerCap: Int = 16` — Stage 2.
- `FrameSequence` frame-level: `addFrameAfter`, `duplicateFrame`, `removeFrame`, `move`, `setName`, `modelTargetIndex` — Stage 2.
- `FrameSequence` layer-cascade: `addLayer`, `duplicateLayer`, `removeLayer`, `moveLayer`, `setLayerName`, `setLayerVisible`, `setLayerLocked` — Stage 2.
- `EditorState.frames: [Frame]`, `EditorState.activeFrameIndex: Int`, `EditorState.fps: Int`, plus a computed `EditorState.frame: Frame { get/set }` for source-compat with all the legacy `state.frame.…` call sites — Stage 1.
- `EditorState.setActiveFrame(index:)`, `EditorState.beginSequenceSnapshot()`, `commitSequenceChange()`, `cancelSequenceChange()`, plus the `.sequenceStructure(beforeFrames:beforeActive:)` `UndoEntry` case — Stage 2.
- `PieceRepository.loadFrames(piece:)`, `PieceRepository.saveFrames(piece:frames:activeFrameIndex:fps:)`. The legacy `loadFrame`/`saveFrame` are kept as thin shims and migrate V1 / raw blobs to V2 on first read — Stage 1.
- `EditorView.addFrameAfterActive()`, `deleteActiveFrame()`, `deleteActiveFrameWithConfirmIfNeeded()`, `renameFrame(id:to:)`, `reorderFrame(from:toOffset:)`, `setActiveFrameAndPersistIfDirty(index:)` — wrappers around `mutateFrameSequence(_:)` plus a custom save-on-tap path — Stage 2 + 3.

## Patterns established (worth carrying into Stages 4–6)

These came from the holistic Opus reviews of Stages 1, 2, 3 and proved themselves in each one:

1. **`mutateFrameSequence(_:)` is the single seam for sequence mutation.** Every `EditorView` callback that touches `state.frames` runs through it: `commitFloatingSelectionIfAny` → `beginSequenceSnapshot` → body → clamp `activeFrameIndex` → `commitSequenceChange` → `saveCurrentFrame`. **Active-index updates must live INSIDE the body closure** (Stage 2 holistic review I1 — they were initially outside, leaving the saved active index stale).

2. **Marquee auto-commit before any state mutation that *reads* layer pixels.** Stage 3's Critical bug (C1) was `activeFrameHasContent` reading `layer.pixels` before the marquee was committed; a frame whose content was entirely floating read as empty and silently fast-path-deleted. **Any new code path that reads pixels for a decision must commit floating selections first.**

3. **Codec consolidation: there is one canonical decoder.** The Stage 1 holistic review found three duplicate three-branch decoders (`PieceRepository.loadFrames`, `PieceRepository.migrateLegacyPiecesIfNeeded`, `EditorView.init`). They were collapsed into `FrameCodec.decodeAnyFrameData(_:fallbackByteCount:)`. New code that decodes pieces should use this helper, not roll its own dispatch.

4. **Migration is "eager + lazy" by design.** `migrateLegacyPiecesIfNeeded()` runs at app launch (eager) and `loadFrames` migrates on read (lazy defense). The spec was updated in Stage 1 to acknowledge this — earlier versions of the spec said "lazy only" which contradicted what shipped.

5. **`Frame` Equatable is identity-based.** Adding `id: UUID` made two freshly-constructed identical-content frames unequal. The `FrameCodecTests.testRoundTripPreservesAllFields` was narrowed (V1 codec doesn't carry `id`/`name`); V2 round-trip preserves all fields. **If you compare frames, compare by content explicitly — `frame.layers == other.layers && frame.activeLayerID == other.activeLayerID` — don't use `==` on `Frame`.**

6. **Sequence-undo memory is the unresolved load-bearing concern.** `.sequenceStructure(beforeFrames: [Frame], beforeActive: Int)` snapshots the full sequence per change. At the cap (60 frames × 16 layers × 256×256) that's 240 MB per snapshot × 50 = 12 GB. The doc comment in `EditorState.swift` flags this. **Stage 4+ should profile undo at large piece sizes once the strip can produce a worst-case sequence**; if memory pressure shows, migrate to a delta-encoded enum (`.frameInserted(at:)`, `.layerInsertedAcross(at:layerID:)`, etc.).

7. **`FrameThumbnailRenderer` is a shim, not a renderer.** Stage 3's first commit duplicated `ThumbnailRenderer`. The cleanup collapsed it to a one-line delegating shim. **Don't duplicate rendering logic — reuse `ThumbnailRenderer` via the shim or directly.**

8. **UI tests must round-trip via Gallery reopen.** `AnimationStripUITests` adds frames, dismisses to gallery, reopens via `PieceThumbnail`, and re-asserts frame count. This is the pattern from Layers v2's stage-3 review (which caught a rename-not-persisted bug because the test only checked in-memory state). **Every UI test for Stages 4–6 should include a close-and-reopen cycle.**

9. **`@accessibilityAddTraits(.isButton)`** on row views so XCTest finds them as `app.buttons["FrameRow.<UUID>"]`. Stage 3's `FrameRow` follows this; Stage 4's play/pause and FPS controls should too.

## What the holistic reviews caught (worth remembering)

The cross-cutting (Opus) reviewer caught real bugs in **every single stage**. Per-task (Sonnet) reviews missed them because they're emergent across multiple commits. Specific catches:

- **Stage 1:** decoder duplicated three times; eager-vs-lazy migration spec contradiction; `decodeSequence` didn't clamp out-of-range FPS on read.
- **Stage 2:** `addFrameAfterActive` and `reorderFrame` updated `activeFrameIndex` AFTER `mutateFrameSequence` returned, leaving the persisted active index stale until the next save.
- **Stage 3 (Critical):** `activeFrameHasContent` ran BEFORE the marquee auto-commit, so a frame whose entire content was floating read as empty and got fast-path-deleted without confirmation. **The exact same bug shape as Layers v2 Stage 3's trash-empty-after-marquee-cut.**
- **Stage 3:** rename TextField had no Cancel path — could be left mounted on a frame that was no longer in focus.
- **Stage 3:** `setActiveFrame` from a frame tap committed the marquee but didn't save — force-quit between tap and next save lost pixels.

**Never skip the holistic Opus review before tagging.** It's the difference between "shipped" and "shipped with a glitch the user finds tomorrow."

## What's next: Stages 4, 5, 6 + final integration

### Stage 4 — Playback (4 tasks)

1. **Task 4.1:** `PlaybackController` (Timer-driven advance of `activeFrameIndex` at the chosen FPS, looping). New file at `DrawBit/State/PlaybackController.swift`. Mark with `@MainActor` to stay on the main thread.
2. **Task 4.2:** Play/pause + FPS picker controls in `FramesStrip` (left side, before the thumbnails). New `EditorState.isPlaying: Bool` field. New `EditorView.togglePlay()` handler.
3. **Task 4.3:** Gate input/ops while playing — `CanvasView.allowsHitTesting(!state.isPlaying)`, disable layer panel ops, disable frame-strip add/duplicate/delete, leave play/pause and FPS picker enabled.
4. **Task 4.4:** Stage 4 sweep + holistic review + tag + merge + push.

Plan section: [`docs/superpowers/plans/2026-05-05-animation-implementation.md`](../plans/2026-05-05-animation-implementation.md) § "Stage 4".

### Stage 5 — Onion skinning (3 tasks)

1. **Task 5.1:** `EditorState.isOnionSkinEnabled: Bool` + toggle button in `FramesStrip` (left side, near play/pause). Disabled at first frame and during playback.
2. **Task 5.2:** `CanvasView` ghost overlay — composites the previous frame at ~30% alpha behind the active-frame composite. Display-only; never enters pixel storage.
3. **Task 5.3:** Stage 5 sweep + holistic review + tag + merge + push.

### Stage 6 — Export (4 tasks)

1. **Task 6.1:** `GIFExporter` via ImageIO multi-image destination, infinite loop, per-frame delay = 1.0/fps.
2. **Task 6.2:** `APNGExporter` (same pattern, `kCGImagePropertyAPNGDelayTime`).
3. **Task 6.3:** Wire GIF + APNG into `ShareSheet`. Single-frame Pieces export as a one-frame GIF/APNG (effectively static).
4. **Task 6.4:** Stage 6 sweep + holistic review + tag + merge + push.

### Final integration (Task 7.x)

- Holistic Opus review per stage tag (already happens between stages — this is just the final cross-cutting review of the whole feature).
- **Update the spec** to reflect any deviations the stages introduced (the eager-migration text was already updated in Stage 1; check for any others).
- **Write the feature-complete handoff** at `docs/superpowers/handoffs/YYYY-MM-DD-animation-feature-complete.md`. Mirror the layers-v2 feature-complete shape.
- **Update memory:** replace the "in-progress animation Stages 1–3" pointer with "animation feature complete + tags."
- **Cleanup the worktree** with `git worktree remove .worktrees/animation` once everything is merged.

## Outstanding follow-ups (none blocking, all noted in reviews)

These were deliberately deferred. None gate Stages 4–6 from starting:

- **Sequence-undo memory profiling** (Stage 2 plan Task 2.4 step 2). Once Stage 3 / 4 lets a user actually create a 60-frame piece, profile undo memory. If it spikes, switch `.sequenceStructure` to a delta-encoded enum. Doc comment in `EditorState.swift` flags this.
- **Cascade invariant defensive precondition.** `FrameSequence.addLayer`/`duplicateLayer`/`removeLayer` read `frames[0].layers.count` for cap/single-layer guards, assuming the cascade invariant holds. A `precondition(frames.allSatisfy { $0.layers.count == frames[0].layers.count })` at the top of each cascade op would defend against a future code path that breaks the invariant.
- **Cascade ops `continue` vs `guard` consistency.** `setLayerName` / `setLayerVisible` / `setLayerLocked` use `continue` for missing layers (silently skip); `addLayer` / `removeLayer` / `moveLayer` use early-return guards. The early-return shape is safer (no partial mutation).
- **`setActiveFrame` non-undoable.** Pre-existing Layers v2 pattern (active-layer switch is also non-undoable). If users complain that a frame switch can't be undone, revisit.
- **Strip eats 60pt of vertical canvas space unconditionally.** On 10.9" iPad in portrait, ~5.5% of vertical. Spec says "iPad only" but doesn't address screen-size sensitivity. If users complain, hide-toggle the strip or auto-hide at 1 frame.
- **`activeFrameHasContent` walks every byte of every layer.** O(layers × edge²) per call. Currently called once on trash tap; fine. Stage 5+ might bind it into a render-driven view (greying trash) — at that point memoize.
- **Confirmation dialog wording** ("Delete Frame?" → "Delete it from the sequence?") doesn't mention undo. Could be tweaked to "Delete this frame? You can undo this." — copy nit.
- **Layers-v2 `SchemaMigrationPlan`** still outstanding (inherited from layers handoff). Not blocked by animation. Required before TestFlight.
- **iPhone support stub** at `docs/superpowers/plans/2026-04-27-iphone-support.md` — animation v1 is iPad-only.

## Picking up Stage 4

Concretely, the next session should:

1. **Re-enter the worktree** at `/Users/iliasrafailidis/development/bitme/.worktrees/animation`. Branch `animation`, tip `1a89ecb`.
2. **Pull main** and rebase the worktree's branch onto the latest main (the merge commit `6b3292c` is on origin/main; the worktree branch already contains its parents):
   ```bash
   cd /Users/iliasrafailidis/development/bitme && git pull --ff-only
   cd .worktrees/animation && git rebase main
   ```
3. **Regenerate the project** in the worktree if you've added or moved Swift files:
   ```bash
   rm -rf DrawBit.xcodeproj && xcodegen generate
   ```
4. **Run baseline tests** to confirm green:
   ```bash
   xcodebuild -project /Users/iliasrafailidis/development/bitme/.worktrees/animation/DrawBit.xcodeproj \
     -scheme DrawBit -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
   ```
   Expected: 177 unit + 7 UI = 184 tests, 0 failures.
5. **Resume the plan** at `docs/superpowers/plans/2026-05-05-animation-implementation.md` § "Stage 4 — Playback". Use the `superpowers:subagent-driven-development` skill — same workflow recipe as Stages 1–3.

## Source-of-truth docs

- Animation spec: `docs/superpowers/specs/2026-05-05-animation-design.md`
- Animation plan: `docs/superpowers/plans/2026-05-05-animation-implementation.md`
- Layers v2 design: `docs/superpowers/specs/2026-05-02-layers-design.md`
- Layers v2 plan: `docs/superpowers/plans/2026-05-02-layers-implementation.md`
- Layers v2 feature-complete handoff: `docs/superpowers/handoffs/2026-05-04-layers-feature-complete.md`
- DrawBit base spec: `docs/superpowers/specs/2026-04-19-drawbit-design.md`

## Workflow recipe (carries forward unchanged)

For any new stage on this codebase:

1. Use `superpowers:writing-plans` to draft the plan (already done — the animation plan covers all 6 stages).
2. Use `superpowers:subagent-driven-development` to execute. Per-task review gating:
   - Mechanical, isolated tasks → combined spec + code-quality review (Sonnet).
   - Multi-file integration tasks → separate spec review then code-quality review.
3. **Always run a final cross-cutting review** (Opus, `superpowers:code-reviewer`) before tagging — it catches bugs the per-task reviewers miss. **Do not skip this.** All three Stage holistic reviews so far have caught Critical or Important issues.
4. Always pass the absolute project path to `xcodebuild` when working from the worktree:
   ```
   xcodebuild -project /Users/iliasrafailidis/development/bitme/.worktrees/animation/DrawBit.xcodeproj …
   ```
   Without it, xcodebuild falls back to the main repo's stale `.xcodeproj`.
5. Stage tag + `--no-ff` merge + push, in that order. Update memory after each stage if relevant.

## Memory update

The auto-memory system should reflect that animation is in progress, not complete. Update the layers-feature-complete pointer accordingly when this handoff lands.
