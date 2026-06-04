# Reference Photo (Tracing) — Design

**Date:** 2026-06-03
**Status:** Approved for planning

## Summary

Let a user attach a single photo to a piece and trace over it. The photo is shown
**dimmed and smooth behind the pixel grid**, tracks the canvas zoom/pan/rotate, and
is never written to pixels nor included in any export. It saves with the piece so a
trace can span multiple sessions.

The reference is a **display-only backdrop**, not a `Layer`. This keeps every existing
invariant intact:

- Layers store straight RGBA with alpha exactly 0 or 255 ("every pixel fully solid or
  fully clear"). A dimmed photo needs partial transparency, which the layer/compositor
  path forbids — so the reference lives outside that path entirely.
- `Compositor` and all exporters walk `Frame.layers` only. Because the reference is not
  a layer, exports exclude it for free.

This mirrors the existing **onion-skin** feature, which already renders a dimmed image
behind the canvas that follows the view transform and ignores touches.

## User-facing behavior

- A pinned **"Reference" row** sits at the bottom of the Layers panel, below all real
  layers (it renders behind them). The row contains:
  - a thumbnail of the photo (or an "Add photo" affordance when empty),
  - a show/hide eye toggle,
  - a **fade slider** (0–100%, default ≈35%),
  - **Add / Replace / Remove** actions. Add/Replace opens the system photo picker
    (`PhotosPicker`, photo library). Remove confirms before clearing.
- On the canvas, the photo renders at the very back of the `ZStack`, dimmed to the fade
  amount, drawn **smooth** (high-quality interpolation — it is a photo, not pixel art),
  aspect-fit (contain) and centered in the square canvas. It follows
  `state.scale` / `state.rotation` / `state.translation` and is not hit-testable.
- A non-square photo shows empty margins inside the square. v1 has no independent
  photo pan/zoom; the user aligns by transforming the whole canvas.
- Hidden during playback, same as onion skin.

## Architecture

### Data model

`Piece` gains two optional fields (a lightweight, additive schema change):

```swift
@Attribute(.externalStorage) var referenceImageData: Data?   // size-capped JPEG
var referenceOpacity: Double                                 // 0...1, default 0.35
```

- `referenceImageData` is the imported photo re-encoded as JPEG and **downscaled to a
  max edge of ~1024px** before storage. 1024px is plenty of detail behind a ≤128px
  canvas and keeps external-storage blobs small. Downscaling/encoding is a pure helper
  (see Rendering below).
- `referenceOpacity` persists the fade so the piece reopens as left. A sensible default
  (0.35) is used when no value was stored.

### Schema migration

Follow the scaffolding already documented in `DrawBitSchema.swift`:

1. Declare `DrawBitSchemaV2: VersionedSchema` (version `2,0,0`) listing the same models.
2. Add a `MigrationStage.lightweight(fromVersion: V1, toVersion: V2)` to
   `DrawBitMigrationPlan` (new optional attributes → lightweight is sufficient).
3. Append V2 to `schemas`, append the stage to `stages`, and point the `Schema(...)`
   construction in `DrawBitApp.swift` at the latest version.

Existing pieces migrate with `referenceImageData == nil` (no reference) and the default
opacity.

### State (`EditorState`)

The reference is session-mutable and persisted, so `EditorState` holds the working copy:

```swift
var referenceImage: UIImage?     // decoded once on load for rendering
var referenceOpacity: Double     // mirrors Piece, edited live by the slider
var isReferenceVisible: Bool      // show/hide toggle (session-only display state)
```

- Loaded from `Piece` when the editor opens; written back on save (alongside the
  existing frame-sequence save path in `EditorView`).
- `isReferenceVisible` is display-only (like onion-skin enable) and need not persist;
  default visible when a reference exists.
- Reference add/replace/remove and opacity changes are **not** on the undo stack — they
  behave like a setting, not a drawing edit. (Consistent with onion-skin toggle, and
  avoids tangling image blobs into the undo memory budget.)

### Rendering

- **New pure helper** `ReferenceImageProcessor` (Rendering layer; imports only
  Foundation/CoreGraphics/ImageIO — **no UIKit**, per the pure-logic rule): takes raw
  imported image `Data` and returns a downscaled JPEG `Data` (max edge ~1024px) using
  the ImageIO thumbnail path (`CGImageSourceCreateThumbnailAtIndex` to decode+downscale,
  `CGImageDestination` to re-encode JPEG). Unit-tested for max-edge clamping and that
  output decodes. The `UIImage` for display is created in the State/View layer from the
  stored `Data` (e.g. `UIImage(data:)`), not inside this helper.
- **Canvas**: in `CanvasView.body`, add an `Image(uiImage:)` as the first (backmost)
  element of the `ZStack`, gated on `state.isReferenceVisible`, a non-nil
  `state.referenceImage`, and `!state.isPlaying`. It uses `.interpolation(.high)`
  (smooth), `.opacity(state.referenceOpacity)`, aspect-fit within the `edge`-sized
  square, and the same `.scaleEffect / .rotationEffect / .offset / .allowsHitTesting(false)`
  chain the onion-skin and pixel images already use. No caching needed (it's a single
  static `UIImage`, not a per-pass composite).

### Persistence (`PieceRepository`)

Extend the existing save path so reference fields round-trip. The repository remains the
only SwiftData seam:

- Add a method (or extend the existing save) to write `referenceImageData` /
  `referenceOpacity` onto the `Piece`.
- On load, decode `referenceImageData` to a `UIImage` for `EditorState`.

### UI (`LayersPanel` / new `ReferenceRow`)

- A **new `ReferenceRow` view** rendered as a pinned footer in the Layers panel, visually
  distinct from the draggable layer list (it is not part of `frame.layers`, not
  reorderable, not deletable as a layer).
- Controls wire directly to `EditorState` + a save callback:
  - eye → toggles `isReferenceVisible`,
  - slider → sets `referenceOpacity` live; persists on release,
  - Add/Replace → `PhotosPicker`; on pick, run `ReferenceImageProcessor`, set
    `state.referenceImage` + data, persist,
  - Remove → confirmation dialog, then clear image + data, persist.
- Follow the panel's existing pixel-font / monochrome styling and the UI-test animation
  gating (`UITestSupport.isRunning`) used elsewhere in the panel.

## Testing

Per repo conventions (unit tests mirror the source tree; UI tests use the in-memory
store and `waitForExistence(timeout: 15)`):

- **`ReferenceImageProcessorTests`** (unit): large image downscaled to ≤1024px max edge;
  small image left at/under cap; output decodes back to an image; aspect ratio preserved.
- **`PieceRepositoryTests`** additions (unit, in-memory container): reference data +
  opacity round-trip through save/load; a piece with no reference loads as `nil` + default
  opacity (covers the migration default).
- **UI test** (one, animation-safe): open Layers panel → Reference row present; toggling
  the eye and moving the slider don't crash and update state. Photo-picker interaction is
  system UI and is **out of scope** for automated UI tests — log/note this rather than
  flake on it.

## Out of scope (v1)

- Inclusion in any export (PNG/GIF/APNG/sprite sheet).
- More than one reference photo per piece.
- Independent photo pan/zoom/rotate relative to the grid.
- Per-frame references.
- Partial opacity on real drawing layers.
- Importing from Files / camera capture (photo library only).

## Invariants preserved

- Layer pixel alpha stays exactly 0 or 255; the reference never touches `Layer`/`PixelGrid`.
- `Compositor` and exporters are untouched — they only ever see `frame.layers`.
- Canvas transform stays view-only; the reference, like onion-skin, is rendered through
  the transform but never baked into pixels.
- `PieceRepository` remains the sole SwiftData seam.
