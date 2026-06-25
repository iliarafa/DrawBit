# Non-square canvases (fixed aspect ratios) — design

**Status:** implemented 2026-06-24 (branch `non-square-canvases`).

## Why
DrawBit assumed one square `dimension` everywhere. This adds fixed-ratio non-square
canvases — **1:1, 16:9, 9:16** — to unlock wallpapers, stories, banners, and wide/tall
scenes. The app is pre-launch (no users), so the persistence change carried no production
migration risk.

## Decisions (locked with the user)
- **Fixed ratios only** (1:1 / 16:9 / 9:16) — not arbitrary width×height. Keeps the picker
  simple and pixel counts bounded.
- **Longest edge + ratio.** The New-Piece slider sets the *longest* edge; the ratio derives
  the short edge as an **exact integer ratio** (`CanvasSize.init(ratio:longestEdge:)` snaps
  the long edge down to a clean multiple, e.g. 200 → 192×108).
- **On canvas:** aspect-fit, centered, true proportions — never stretch (pixel-fidelity rule).
- **Gallery thumbnail:** letterbox — full art centered, pure dark bands; gridlines confined
  to the aspect-fit art region.
- **Export SIZE tiles:** one number when square (unchanged), **`W×H`** when non-square; the
  scale ladder and default scale anchor to the **longest edge**.

## Model
`CanvasSize` carries `width`/`height` (was a single `dimension`). `dimension`/`rawValue`
remain as square-only back-compat aliases so square call sites and `NewPiece-N` preset IDs
are untouched; `id` became `"WxH"`. `Piece` keeps `sizeRaw` as width and adds a defaulted
`heightRaw` (`0` ⇒ square ⇒ height = width) — an additive column that rides inferred
lightweight migration, so old square stores still open. `PixelGrid` indexes by width
(row stride) and bounds-checks width & height.

## Pipeline
- **Drawing tools** (`Fill`/`ColorSwap`/`Marquee`/`PixelRect.clipped`) iterate/clip width and
  height independently — they previously bounded by a single dimension and under-covered
  tall grids.
- **Rendering/export** (`bufferToCGImage`, PNG/GIF/APNG/sprite exporters, `ExportSizeBudget`)
  size output by width×height per axis. `ThumbnailRenderer` renders at true aspect (longest
  edge = targetEdge) so the gallery letterboxes against its own background.
- **Canvas/touch** (`CanvasView`, `CanvasHostView`) lay out a base `CGSize` from one square
  `perPixel` (sized off the longest edge) and map touches per-axis with `ix<width, iy<height`.
  Transform stays view-only.

## Verification
328→337 unit tests (non-square model/grid/persistence/exporters/budget, all TDD). On-sim:
create 16:9 → 64×36 canvas draws pixel-perfect with no gaps → gallery letterboxes →
export sheet shows exact 16:9 tiles (128×72 … 2048×1152). Full UI suite green.

## Out of scope
Arbitrary W×H; ratios beyond 16:9/9:16; resizing/cropping/rotating an existing canvas.
