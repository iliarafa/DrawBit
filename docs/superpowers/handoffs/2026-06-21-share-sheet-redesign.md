# Handoff — Share-sheet redesign (2026-06-21)

Branch `share-sheet-redesign`. Spec:
`docs/superpowers/specs/2026-06-21-share-sheet-redesign-design.md`.

## What shipped

The export sheet went from a plain two-grid panel to a **vertical-hero layout with a smart
artwork preview** — the second queued task from the 2026-06-20 handoff ("share box format → the
sheet LAYOUT"). Export behavior is unchanged; this is pure layout + a new preview.

### New: `ExportPreview` — `DrawBit/Views/Editor/ExportPreview.swift`
A square preview on a checkerboard backdrop that shows exactly what the selected format produces:
- **PNG** → the active frame, static.
- **GIF/APNG** → all frames looped at the piece's fps via a stateless `TimelineView(.periodic)`
  (index derived from wall-clock), **gated on `!UITestSupport.isRunning`** so a live periodic
  timeline never wedges XCUITest idle. Under test / single-frame → static frame 0.
- **Sprite** → frames laid out in the exporter's grid.
- Corner **badge**: format + a stat (`{outputEdge}px`, `{cols}×{rows}` for sprite, `{secs}s` loop
  for GIF/APNG).
- Frames are pre-rendered once to `[CGImage]` (cache) via `FrameThumbnailRenderer.renderCGImage`
  (nearest-neighbor, 512px), reused by all three modes.

### Restyle — `DrawBit/Views/Editor/ShareSheet.swift`
Dropped the `NavigationStack`/toolbar for a custom dark layout matching `DrawBitColorPicker`:
header (CANCEL · EXPORT) → `ExportPreview` + `piece.effectiveName` → FORMAT tiles → SCALE tiles
→ one full-width white **EXPORT** button (`ProgressView` while exporting). Frames are **preloaded
once** in `onAppear` and reused by `share()` (no double decode). All export logic — `ExportFormat`,
`scales(for:)`, `defaultScale(for:)`, `isOverBudget`, the over-budget graying + snap-down, the
`UIActivityViewController` flow, and every `ShareSheet.*` accessibility id — is unchanged.

### Shared grid math — `DrawBit/Rendering/SpriteSheetExporter.swift`
Extracted the inline column/row formula into a pure `static func grid(count:) ->
(columns, rows)`; the exporter delegates to it and `ExportPreview` reuses it so the preview
always matches the written sheet. Pinned by `SpriteSheetLayoutTests`.

### Wiring — `DrawBit/Views/Editor/EditorView.swift`
Detent bumped `.height(360)` → `.height(640)` to fit the hero.

## Verification
- Full suite green: **UI 26** (new `ShareSheetUITests`) + unit (new `SpriteSheetLayoutTests`,
  existing `ShareSheetScalesTests` / `ExportSizeBudgetTests` / `SpriteSheetExporterTests` all
  still pass). Build clean.
- Visual — worth an eyeball: open a multi-frame piece → SHARE; confirm GIF/APNG animate, PNG is
  static, Sprite shows the grid, badge reflects format, scale tiles still gray "TOO BIG".

## Gotchas captured
1. **`.accessibilityIdentifier` on a container with one accessible child MERGES them.** The
   `ExportPreview` ZStack's identifier collapsed the whole preview into a single `StaticText`
   whose *label* is the badge text. The UI test queries `staticTexts["ExportPreview"]` and reads
   its label — there is no separate badge element. If you add more text inside the preview,
   revisit this (the merge may break).
2. **Use a stateless `TimelineView(.periodic)` for the loop, not a manual `Timer`** — no lifecycle
   to manage, and it's trivially gated off under UI test (swap to a static frame). A bare periodic
   timeline still never reaches XCUITest idle, hence the gate.
3. **Don't `git add -A` here** — three unused source PNGs sit untracked in the repo root
   (`alt_logo.PNG`, `dbit.png`, `share.PNG`); stage explicit paths. (See [[project_palettes]] notes
   / `project_stale_branches`.)

## Both queued tasks from 2026-06-20 are now done (palettes + share sheet).
Possible next: judge palettes + the new export preview on real hardware; the loose root PNGs still
want a decision (keep/delete); several stale local branches still need triage.
