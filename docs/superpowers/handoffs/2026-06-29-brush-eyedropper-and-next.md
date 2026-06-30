# Handoff — end of 2026-06-29 (brush size + eyedropper-reference shipped)

Supersedes `2026-06-29-select-tool-and-next.md`. `main` = `origin/main` = tip `2266917` (pushed,
in sync). Clean working tree **except** three untracked PNGs at the repo root (`alt_logo.PNG`,
`dbit.png`, `share.PNG`) — pre-existing marketing assets, the user's call whether to track them.

## Shipped today (all on origin/main)

- **Brush size** — square nib **1–4** on pencil + eraser, **cycle-on-tap** (tap the already-selected
  tool to step size, wraps 4→1), **scheme-C glyph** (the tool icon *is* the nib: pencil filled square,
  eraser hollow square, grows with size). Per-tool independent, resets to 1 each session. The
  hold-to-straighten line is thick too. Spec/plan: `docs/superpowers/{specs,plans}/2026-06-29-brush-size*`;
  details in memory `project_brush_size`.
- **Eyedropper reads the reference photo** — PICK now samples the display-only tracing reference where
  the layers are blank (returns its true, full-strength color). New `Rendering/ReferenceSampler.swift`
  (renders the reference onto the canvas grid: sRGB, aspect-fit, alpha 0/255) + `EditorState.pickColor(at:)`
  (composite layers, then fall back to `referenceGrid` when visible). Reference stays **display-only**
  (not a layer, not exported). Memory `project_eyedropper_reference`.
- **Roadmap pruned:** the founder **dropped PNG import and the rectangle tool** this session — do NOT
  re-propose them.

## Still next (the queue)

- **Time-lapse / process replay** — the standout delight/virality play and the biggest lift; give it
  its own brainstorm. Reuses the per-stroke snapshots (`EditorState.preStrokeSnapshot` / `.layerPixels`
  undo entries) + the existing `GIFExporter`/`APNGExporter`. Needs a persistence decision (store the
  replay with the `Piece`, or regenerate from history?).
- **Cheap polish batch (S):** rename a draw (`Piece.name` exists, no UI sets it); dithering + a
  color-ramp generator; Copy-PNG to clipboard (no `UIPasteboard` use anywhere yet); empty-gallery hint.
  See memory `project_audit_followups`.
- **Optional, now foundationed:** "import the reference as an editable layer." `ReferenceSampler`
  already produces the exact canvas-grid RGBA buffer a `Layer` would need — committing it as a layer
  (alpha 0/255, `Frame.addLayer` + structural-undo) is the remaining work. Only if the user wants
  editable photo→pixels; the picking bug itself is already fixed.

## Reusable gotchas (carry these)

- **DerivedData:** after `rm -rf DrawBit.xcodeproj && xcodegen generate` adds a **new app-target**
  `.swift` file, also `rm -rf ~/Library/Developer/Xcode/DerivedData/DrawBit-*` or the test target
  fails `cannot find <Type> in scope` against a stale `DrawBit.swiftmodule`. New **test-target** files
  are picked up by regen alone.
- **CGImage orientation:** a top-left `CGImage` (raw `CGDataProvider` buffer or `CGImageSource`-decoded)
  drawn into a `CGContext(data:)` bitmap and read as raw bytes is **already top-down** — do NOT add a
  `translateBy`/`scaleBy(y:-1)` flip (it mirrors vertically). Differs from `UIImage.draw`, which flips.
- **sRGB test fixtures:** build test images from raw sRGB bytes via `CGImage(...provider...)`, not
  `CGColor(red:…)` PNGs — the latter are untagged and drift (red → ~(255,38,0)) through an sRGB context.
  Production references are sRGB-forced by `ReferenceImageProcessor`.
- **PhotosPicker can't be UI-automated** — verify photo-import features with a unit test that feeds a
  real image through `setReference` (cover the logic in State, not the picker UI).
- `DrawBit.xcodeproj` is gitignored (commits never include it). Test sim: `iPad Pro 13-inch (M5)`.

## Guiding star (from the founder)

A **calm, premium, single-player pixel app that feels like a beautiful machine** (built first to make
sprites for the game *All my Falling Stars*). Judge each item by "does it remove friction from joyful
making," not "does it tick a competitor's box." Several "next" items are **discuss-first** — settle the
shape with the user before building. The user prefers plain-language design talk over framework jargon.
Verify file/line refs before editing — they drift.
