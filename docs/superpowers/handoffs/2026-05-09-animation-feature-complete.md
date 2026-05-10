# DrawBit Animation v1 — Feature Complete

**Date:** 2026-05-09
**Status:** All 6 stages shipped to `main` and pushed to `origin`. The animation feature is done.
**Predecessor docs:**
- Stages 1–3 handoff: [`2026-05-05-animation-stages-1-3-handoff.md`](./2026-05-05-animation-stages-1-3-handoff.md)
- Spec: [`docs/superpowers/specs/2026-05-05-animation-design.md`](../specs/2026-05-05-animation-design.md)
- Plan: [`docs/superpowers/plans/2026-05-05-animation-implementation.md`](../plans/2026-05-05-animation-implementation.md)

This is the single-page summary of everything Animation v1 delivered. The next session can read this to skip the conversation history and pick up wherever the user wants.

## State of the world

- Branch `main` tip: `c7ee977` (merge of `stage-6-animation-export`).
- `origin/main` is in sync — nothing pending push.
- Worktree at `.worktrees/animation/` is on branch `animation` at the same SHA as main. Removable with `git worktree remove .worktrees/animation` from the main repo when convenient.
- Tests at the time of shipping: **228 unit / 8 UI**, all green. Simulator and device-Release compile-checks both green.

## The six stage tags

| Tag                            | Merge into main | Stage focus |
| ------------------------------ | --------------- | ----------- |
| `stage-1-animation-plumbing`   | `bb6b95d`       | `Frame.id`/`name`, V2 codec, `loadFrames`/`saveFrames`, single-frame non-regression |
| `stage-2-animation-frame-ops`  | `588b62a`       | `FrameSequence` mutators (frame + layer cascade), sequence-level undo |
| `stage-3-animation-strip`      | `6b3292c`       | `FramesStrip` UI: thumbnails, add/duplicate/delete, EDIT toggle, rename |
| `stage-4-animation-playback`   | `d24877a`       | `PlaybackController` + play/pause + FPS picker + input gating while playing |
| `stage-5-animation-onion-skin` | `7b4a007`       | Onion-skin toggle + previous-frame ghost overlay in `CanvasView` |
| `stage-6-animation-export`     | `c7ee977`       | `GIFExporter` + `APNGExporter` + ShareSheet format picker |

Each stage was tagged after its own holistic Opus review. Reviews caught real bugs in stages 1, 2, 3, 4, and 6 — see "What the holistic reviews caught" below.

## What ships

User-visible behavior, end-to-end:

### Frames + timeline (Stages 1–3)
- Bottom-of-editor 60-pt timeline strip showing every frame's thumbnail. Always visible.
- Tap a thumbnail to switch active frame; long-press to rename inline.
- EDIT mode reveals duplicate (`plus.square.on.square`) + trash. Hard cap of 60 frames.
- Delete with content shows confirmation; empty frames fast-path-delete.
- Marquee auto-commits before any frame mutation.

### Playback (Stage 4)
- Play/pause button on the left of the strip. Disabled at 1 frame.
- FPS button cycles through `[4, 8, 12, 24, 30, 60]`. Disabled while playing (Timer is armed at start; pause + resume to apply a new rate).
- While playing: drawing tools, marquee, frame ops, layer ops, onion-skin toggle, and FPS are all gated off. Only play/pause and GALLERY dismiss remain live.
- Floating marquee auto-commits and persists before play arms (Stage 4 holistic-review fix).
- Pause persists the current frame so a force-quit doesn't lose it.

### Onion skin (Stage 5)
- Ghost icon (`circle` / `circle.righthalf.filled`) toggles a 30%-opacity preview of the previous frame behind the active frame's composite.
- Disabled at frame 0 (no previous frame). Disabled during playback.
- Display-only — never written to pixel storage. `EditorState.isOnionSkinEnabled` is session-only, not persisted to the Piece.

### Animated export (Stage 6)
- ShareSheet now has a FORMAT picker above the existing SCALE picker:
  - **PNG** — active frame, single image (existing behavior, byte-identical for one-frame pieces).
  - **GIF** — animated, no partial alpha. ImageIO multi-image destination, infinite loop, per-frame delay = `1/fps`. Round-trip-verified to preserve DrawBit's binary 0-or-255 alpha.
  - **Animated PNG** — same shape, true 8-bit alpha. iOS / Safari / Chrome play APNG natively; Photos shows the first frame as a preview.
- SHARE auto-commits any floating marquee and persists before the sheet opens (Stage 6 holistic-review fix).
- Exports run on a detached `Task` so the SHARE button shows `EXPORTING…` rather than blocking the UI.

### Persistence + undo
- Every frame-mutating action saves through `PieceRepository.saveFrames(piece:frames:activeFrameIndex:fps:)`.
- Frame add/duplicate/delete/reorder/rename are all undoable via `.sequenceStructure` snapshots (full snapshot in v1; delta-encoded follow-up flagged below).
- Closing and reopening the editor shows exactly what the user left.

## What got added to the codebase across Stages 4–6

### New files (Stages 4–6)
```
DrawBit/State/PlaybackController.swift               (Stage 4)  @MainActor Timer-driven advancer
DrawBit/Rendering/GIFExporter.swift                  (Stage 6)  ImageIO multi-image GIF encoder
DrawBit/Rendering/APNGExporter.swift                 (Stage 6)  ImageIO multi-image PNG encoder
DrawBitTests/State/PlaybackControllerTests.swift     (Stage 4)  10 tests — incl. marquee auto-commit regression
DrawBitTests/Rendering/GIFExporterTests.swift        (Stage 6)  9 tests — incl. binary-alpha round-trip
DrawBitTests/Rendering/APNGExporterTests.swift       (Stage 6)  9 tests — incl. pixel-byte alpha round-trip
DrawBitUITests/AnimationStripUITests.swift           (extended) testOnionSkinToggleGatedAndNotPersisted (+1)
```

### New API surface (existing files)
- `EditorState.isPlaying: Bool` — Stage 4. Display-only, gates input and chrome.
- `EditorState.isOnionSkinEnabled: Bool` — Stage 5. Display-only, not persisted.
- `EditorView.togglePlay()` — wraps `PlaybackController` lifecycle, calls `commitFloatingMarqueeAndPersist` before arming.
- `EditorView.commitFloatingMarqueeAndPersist()` — Stage 6 refactor of the auto-commit pattern. **Use this before any operation that reads piece state or changes marquee-commit destination.**
- `ShareSheet.ExportFormat` enum: `.png`, `.gif`, `.apng` with `label`, `caption`, and `fileExtension`.
- `FramesStrip(onTogglePlay:)` initializer parameter (Stage 4).

## Patterns established (worth carrying into future features)

These came from the holistic Opus reviews of each stage and proved themselves repeatedly:

1. **Marquee auto-commit before ANY state read or mutation that affects the destination of a marquee commit.** This is the single most-frequently-caught bug across both Layers v2 and Animation reviews. Stage 4 caught it on play; Stage 6 caught it on share. The canonical helper is `EditorView.commitFloatingMarqueeAndPersist()` — call it from any new operation that exports, switches frames non-trivially, or otherwise reads the persisted piece state. The bug shape: a floating marquee is a transient extraction; if anything reads or writes piece state without committing first, the marquee silently lands in the wrong frame or vanishes from the export.

2. **Display-only state is documented at the declaration site.** `isPlaying` and `isOnionSkinEnabled` both have doc comments explaining "not persisted" and where they're cleared. A future reader can tell at a glance which fields belong on the Piece and which don't.

3. **Stream-style filters use stream-style tests.** Wall-clock tests that assert "after sleep N, observed state matches" must defend against modular wraparound. Stage 4's `testTimerWrapsPastEndOfSequence` was rewritten to use 10 frames so wrap-back-to-start is impossible within the sleep budget — the same robust pattern should apply to any future timer-driven test.

4. **Timer.scheduledTimer is `.default` mode only.** Use `Timer(timeInterval:repeats:block:)` + `RunLoop.main.add(t, forMode: .common)` for any timer that should keep firing during scroll-tracking. Stage 4 review I1 caught this — playback used to freeze when the user scrolled the frames strip.

5. **`@MainActor` controller deinit + view-`.onDisappear` cleanup.** A `@MainActor` class that owns a `Timer` must invalidate in `deinit` (the run loop holds the timer strongly otherwise), and the owning view should `.stop()` in `onDisappear` to update visible state immediately. Stage 4 review I2 caught both halves.

6. **Per-stage holistic Opus review IS NON-OPTIONAL.** Every single stage of both Layers v2 and Animation v1 — six stages each — has had the cross-cutting Opus review catch at least one Important issue, and four of the six animation stages (3, 4, 6) had Critical issues that per-task review missed. The cost-benefit is unambiguous: skipping the holistic review ships bugs.

7. **Test deviations from a plan should be either implemented OR explicitly documented.** Stage 5 deviated from the plan (used `Compositor` + `bufferToCGImage` instead of `FrameThumbnailRenderer.render` PNG roundtrip) — the deviation was documented in the commit message and proved to be a clean improvement. Stage 6 deviated on FPS-picker-during-playback and SHARE-marquee-auto-commit — those were captured in the spec update at `2026-05-05-animation-design.md`.

## What the holistic reviews caught

The cross-cutting (Opus) reviewer caught real bugs in **every stage**. Per-task (Sonnet) reviews missed them because they're emergent across multiple commits. Stage 4–6 catches:

- **Stage 4 (Critical):** `togglePlay` did not auto-commit a floating marquee before arming the timer. The floating overlay would visibly drift across frames during playback and silently land in the wrong frame on the next tap. Same root cause as Layers v2 Stage 3's trash-empty-after-marquee-cut. Fixed by adding `state.commitFloatingSelectionIfAny()` to both `EditorView.togglePlay` and `PlaybackController.start` (defense-in-depth).
- **Stage 4 (Important):** `Timer.scheduledTimer` registered in `.default` mode only — playback froze during ScrollView tracking gestures. Switched to `Timer(...)` + `RunLoop.main.add(t, forMode: .common)`.
- **Stage 4 (Important):** `PlaybackController` had no `deinit` invalidating the Timer; the run loop kept the timer alive past editor dismissal. Added `deinit { timer?.invalidate() }` and `playback?.stop()` in `EditorView.onDisappear`.
- **Stage 4 (Important):** `FramesStrip` thumbnail row + ScrollView were not gated during playback; user could scrub or open inline rename mid-playback. Wrapped with `.disabled(state.isPlaying)`.
- **Stage 5 (Important):** No UI test for the onion-skin toggle. Added `testOnionSkinToggleGatedAndNotPersisted` exercising the disabled-at-frame-0 invariant and the not-persisted-across-reopen invariant.
- **Stage 6 (Critical):** SHARE button did not auto-commit a floating marquee before opening the export sheet. Same root cause as Stage 4. Fixed by adding `commitFloatingMarqueeAndPersist()` to the SHARE button action and refactoring the pattern into a reusable helper.
- **Stage 6 (Important):** `testAPNGPreservesAlpha` was a weak assertion (only checked `alphaInfo != .none`). Strengthened to encode a frame with one opaque + one transparent pixel, decode + re-rasterize, assert pixel bytes round-trip exactly.
- **Stage 6 (Minor):** Added analogous GIF transparency round-trip test, cleaned up `ExportFormat.fileExtension` dead-code, replaced ugly `.apng.png` filename with `.apng`.

**Never skip the holistic Opus review before tagging.** It is the difference between "shipped" and "shipped with a glitch the user finds tomorrow."

## Outstanding follow-ups (none blocking)

These were deferred during reviews. None gate the feature from being declared complete:

- **Sequence-undo memory profiling** (Stage 2 plan Task 2.4 step 2). With Stage 4–6 done, the strip can produce a real worst-case 60-frame piece. Profile undo memory; if it spikes, switch `.sequenceStructure` to a delta-encoded enum (`.frameInserted(at:)`, `.layerInsertedAcross(at:layerID:)`). Doc comment in `EditorState.swift` flags this. Currently 12 GB worst-case is theoretical; on M5 iPad it's likely fine, but worth measuring.
- **Onion-skin ghost cache** (Stage 5 holistic review I1). `previousFrameImage()` re-composites every layout pass even though the previous frame can't have changed during a stroke on the active frame. At 256² × 16 visible layers × 60 fps drag this is ~240 MB/s of wasted byte scanning. Fine on M-series, marginal on A12. Cache deferred because the simple `@State` pattern trips SwiftUI's "modifying state during view update" rule; clean fix needs a small helper class.
- **Cancel during animated export** (Stage 6 holistic review I3). `Task.detached` runs to completion regardless of view dismissal; encoding ignores cancellation. For 60-frame 4× APNG this can keep the device warm ~600ms after CANCEL. Add `try Task.checkCancellation()` checkpoints between frames in both exporters.
- **V1 migration on MainActor during share** (Stage 6 review I4). `loadFrames` does a side-effecting V1→V2 migration. Currently called on the main thread before the detached encode — V1 pieces hitch the UI for the migration duration. Move the load inside `Task.detached` or accept the one-time hitch.
- **Accessibility labels on FramesStrip controls** (Stage 5 review M1). Play/pause, FPS, onion-skin, and `+`/trash buttons rely on the SF Symbol name for VoiceOver. Add explicit `.accessibilityLabel` strings. Sweep across the strip rather than per-button.
- **Layers v2 `SchemaMigrationPlan`** still outstanding (inherited from layers handoff). Not blocked by animation. **Required before TestFlight.**
- **iPhone support stub** at `docs/superpowers/plans/2026-04-27-iphone-support.md` — animation v1 is iPad-only.

## Worktree cleanup

Once you're satisfied the feature is shipped:

```bash
cd /Users/iliasrafailidis/development/bitme
git worktree remove .worktrees/animation
git worktree prune
```

The `.worktrees/layers/` worktree from the previous feature is also removable — independent of animation work. The animation tag remains in `origin` regardless of worktree state.

## Test count summary

| Stage start | Unit | UI |
| ----------- | ---- | -- |
| Pre-animation       | 132 | 4 |
| After Stages 1–3    | 177 | 7 |
| After Stages 4–6    | 228 | 8 |

(The +23 unit jump beyond Stages 4–6's own additions reflects the unrelated color-swap + pixel-perfect-stroke commits that landed on `main` between Stages 3 and 4.)

## Source-of-truth docs

- Animation spec: `docs/superpowers/specs/2026-05-05-animation-design.md` (updated for FPS-during-playback and SHARE-marquee notes)
- Animation plan: `docs/superpowers/plans/2026-05-05-animation-implementation.md`
- Stages 1–3 handoff: `docs/superpowers/handoffs/2026-05-05-animation-stages-1-3-handoff.md`
- Layers v2 feature-complete handoff: `docs/superpowers/handoffs/2026-05-04-layers-feature-complete.md` (whose shape this doc mirrors)
- Layers v2 design: `docs/superpowers/specs/2026-05-02-layers-design.md`
- DrawBit base spec: `docs/superpowers/specs/2026-04-19-drawbit-design.md`

## Memory update

Replace the "in-progress animation Stages 1–3" memory entry with one that points at this handoff. Auto-memory should reflect that animation is COMPLETE — Stages 4–6 shipped on `main`, tags `stage-4-animation-playback` / `stage-5-animation-onion-skin` / `stage-6-animation-export` are on `origin`.
