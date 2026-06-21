# Share-sheet redesign — Design (2026-06-21)

## Problem

The export/share sheet (`DrawBit/Views/Editor/ShareSheet.swift`) is functional but plain — a
small `.height(360)` sheet with a FORMAT tile row, a SCALE tile row, and nav-bar CANCEL/EXPORT,
with **no preview of the artwork being exported**. Second task queued in the 2026-06-20 handoff
("share box format → the sheet LAYOUT, not the file-format options").

## Goal

Add a **smart preview** and **restyle** the sheet into a calm "vertical hero" layout. Export
formats, scale tiles, and size-budget logic are unchanged — only the look and the new preview.
Same governing constraint as the palette work: legible, on-brand, never busy.

## Decisions

- **Layout = vertical hero:** preview on top, FORMAT + SCALE stacked below, one full-width EXPORT
  button.
- **Smart preview matches the selected format:** PNG → static active frame; GIF/APNG → loop all
  frames at the piece's fps; Sprite → frames in the exporter's grid.
- **Presentation = taller bottom sheet** (~640pt), not full-screen — export is a quick,
  swipe-to-dismiss task and the system share sheet presents over everything anyway.
- Custom dark header (CANCEL · EXPORT) instead of the iOS nav bar, matching `DrawBitColorPicker`.

## Architecture

Pure layout + a new view; the export pipeline is untouched. Reuses existing Rendering code.

### `ExportPreview` (new) — `DrawBit/Views/Editor/ExportPreview.swift`
Square preview on a checkerboard backdrop, nearest-neighbor (`.interpolation(.none)
.antialiased(false)`). Inputs: `frames`, `activeIndex`, `size`, `fps`, `format`, `outputEdge`.

- **Cache:** pre-render every frame once to `[CGImage]` via
  `FrameThumbnailRenderer.renderCGImage(frame:size:targetEdge:)` (~512px), rebuilt only when
  `frames`/`size` change. Reused by all modes.
- PNG → cached image at `activeIndex` (static).
- GIF/APNG → `@State loopIndex` advanced by a `Timer` at `1.0/fps`, **gated on
  `!UITestSupport.isRunning`** (a live timer wedges XCUITest idle); invalidated on disappear and
  for non-animated formats. Under test: static first frame.
- Sprite → cached frames laid out in the exporter's grid, fit to the square.
- Badge (bottom-right): format + one stat — px (`outputEdge`) or `cols×rows` for sprite, loop
  seconds for GIF/APNG.

### Shared grid math — `DrawBit/Rendering/SpriteSheetExporter.swift`
Extract the inline column/row computation into a pure `static func grid(count: Int) ->
(columns: Int, rows: Int)`. The exporter delegates to it and `ExportPreview` reuses it so the
preview always matches real output. Unit-testable.

### `ShareSheet` restyle — `DrawBit/Views/Editor/ShareSheet.swift`
Custom dark layout (pixel font, `Color(white:0.10)`): header (CANCEL · EXPORT) → `ExportPreview`
+ `piece.effectiveName` → FORMAT tiles → SCALE tiles → full-width EXPORT button (`ProgressView`
while exporting). Preload frames once via `PieceRepository.loadFrames(piece:)` in `.task` and
reuse them in `share()`. Keep `ExportFormat`, `scales(for:)`, `defaultScale(for:)`,
`isOverBudget`, the `share()` exporter dispatch, the over-budget graying + snap-down, and all
`ShareSheet.*` accessibility identifiers.

### Wiring — `DrawBit/Views/Editor/EditorView.swift`
`.presentationDetents([.height(640)])` (was 360); keep corner radius 0 + dark background.

## Testing

- Unchanged-green: `ShareSheetScalesTests`, `ExportSizeBudgetTests`, existing
  `SpriteSheetExporter` tests.
- New unit `SpriteSheetLayoutTests`: pin `grid(count:)` for counts 1/2/3/4/9/16 and
  `columns*rows >= count`.
- New light UI test: open editor → SHARE → assert preview, FORMAT/SCALE tiles, big EXPORT button;
  switch format → badge updates. Do NOT tap EXPORT (avoids the system share popover). Generous
  waits, polled reads.

## Invariants honored

- Nearest-neighbor + sRGB in the preview (reuses `FrameThumbnailRenderer`); no partial alpha.
- Preview animation gated on `!UITestSupport.isRunning`.
- Export formats, scale/budget math, and accessibility ids unchanged.
