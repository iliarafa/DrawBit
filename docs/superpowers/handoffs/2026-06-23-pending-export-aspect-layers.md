# Handoff — 4 pending tasks (2026-06-23)

This session finished the **Help-page redesign** arc (all shipped to `main`, HEAD `9954a48`).
Below are the **next tasks**, captured for a fresh session. None are started.

## Repo state
- Branch `main`, in sync with `origin/main`, **HEAD `9954a48`**, working tree clean.
- Only `main` exists now (all old feature/worktree branches deleted this session).
- Untracked root images — **leave alone, never `git add -A`**: `alt_logo.PNG`, `dbit.png`, `share.PNG`.
- Build/run/test commands + invariants live in `CLAUDE.md`. Tests green as of last Help work.

## How the user likes to work (learned across the Help sessions)
- **Verify visually on the sim**, not just by building. Drive the Simulator via computer-use;
  to catch a transition mid-flight use **Debug ▸ Slow Animations** (it also slows the launch
  intro, so toggle it off to navigate, on just for the capture). The Simulator often loses
  focus — re-`open_application "Simulator"` and re-tap.
- **Ship cadence:** branch → commit → push → merge to `main` (fast-forward) → delete branch
  (local + remote). One small feature per branch. Always `rm -rf build` (the temp
  `-derivedDataPath build` dir) before committing.
- Plain-spoken design talk, no jargon. Copy approved mockups exactly. **No rounded corners.**
  Don't over-ask or over-engineer; make the change asked.

---

## 1. EXPORT — rename dimension labels to SD / HD / 2K / 4K
- File: `DrawBit/Views/Editor/ShareSheet.swift`. The scale picker is `scaleTile(scale:)` (L208)
  over `Self.scales(for: piece.size)` (L94); `outputEdge = piece.size.dimension * selectedScale`
  (L21). a11y id `ShareSheet.scale.<s>` (L242).
- Today the five scales map to **output edges `[128, 256, 512, 1024, 2048]` px** (the multiplier
  varies by canvas; longest edge is what's shown). Task = show **SD / HD / 2K / 4K** instead of
  the raw size/scale.
- **Decision needed before coding:** there are 5 output sizes but 4 names. Confirm the px→label
  mapping (e.g. 512=SD, 1024=HD, 2048=2K, …?) and whether **4K means adding a new larger output**
  (~3840/4096 px) — the current max is 2048, so "4K" doesn't exist yet. Ask the user.

## 2. NEW DRAW sheet — match its shadow to the gallery tiles' lift
- The gallery tiles use `.galleryTileLift()` — `DrawBit/Views/Gallery/GalleryTileLift.swift`:
  `.shadow(.black.opacity(0.55), radius: 4, y: 2)` + `.shadow(.white.opacity(0.05), radius: 6)`.
- The New Draw sheet is `NewPieceSheet` presented from `GalleryView.swift:96` with
  `.presentationSizing(.fitted).presentationCornerRadius(0)` (L107–108). Its current elevation is
  the **system sheet shadow**, which doesn't match the tiles.
- Task: make the sheet read with the **same lift as the tiles above it**. Likely apply the
  `GalleryTileLift` shadow values to the sheet's content block (`NewPieceSheet`'s outer
  `.frame(width: 320).padding(20)`), and/or a custom presentation background, so the system
  shadow is replaced by the tile-matching one. Tune by eye on the sim.

## 3. Non-square canvases — offer 16:9 and 9:16
- **Biggest task; needs a design pass / brainstorm first.** The whole stack is **square-only**:
  `DrawBit/Models/CanvasSize.swift` is a single `dimension: Int` (8–256), and its doc explicitly
  says "the whole drawing/rendering stack keys off `dimension`." Mirror symmetry uses
  `dimension - 1 - x`. `CLAUDE.md` invariants assume square (PixelGrid, preview, exports).
- Work implied: introduce width×height (or aspect) into `CanvasSize`/`Piece`; verify `PixelGrid`
  (`DrawBit/Drawing/`) already carries a 2-D `size` (check its `size` type) or extend it; update
  the New Draw sheet (`NewPieceSheet` — preview `CanvasPreview`, presets, slider) to offer
  16:9 / 9:16; re-check `Compositor`/exporters/thumbnail render and the mirror math.
- Recommend: start with `superpowers:brainstorming` to scope aspect-ratio support before coding;
  keep square as default. Confirm with user: fixed 16:9/9:16 presets, or free W×H?

## 4. LAYERS — fix press/hold/drag/reorder mechanics & feel
- Files: `DrawBit/Views/Editor/LayerRow.swift` (the row + drag) and
  `DrawBit/Views/Editor/LayersPanel.swift` (drop handling + `performMove`).
- Current approach: `LayerRow` uses SwiftUI `.draggable("\(displayIndex)")` (L29) with
  `.dropDestination` at the cell level in `LayersPanel` (see L151–224, `performMove` L211).
  **Known pain (per code comments):** `LayerRow.swift:52` — "long-press is unreliable next to
  `.draggable`"; reorder is completed by dragging the **32-pt thumbnail** (L91), which is fiddly.
- Task: make press → hold → drag → reorder reliable and good-feeling. Likely means replacing the
  `.draggable`/`.dropDestination` combo with a custom long-press-then-drag gesture (a manual
  reorder with live row offset/insertion, like a proper drag handle), and a larger/clearer grab
  target. **Note:** drag reorder is hard to verify in the Simulator via automation — lean on the
  user testing the feel, plus the existing `LayersPanel` UI tests (poll for row counts, per
  `CLAUDE.md`'s "reads that depend on async rebuilds must poll" note). Watch the animation-gating
  rule (`UITestSupport.isRunning`).

---

## Pointers
- Help-redesign details (icons, hover, dissolve, in-place text, multi-toggle) are on `main` and
  summarized in memory `project_help_redesign.md`.
- Regenerate the Xcode project after adding/moving `.swift` files: `rm -rf DrawBit.xcodeproj && xcodegen generate`.
