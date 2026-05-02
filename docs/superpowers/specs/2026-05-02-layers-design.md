# DrawBit — Layers (v2)

**Status:** Draft — awaiting user sign-off before implementation planning.
**Date:** 2026-05-02
**Branch:** to be developed on `layers` and only merged when fully verified.
**Distribution status at time of writing:** App not yet shipped to App Store. Migration concerns are local-only (developer's own pieces on simulators / dev devices).

## Purpose

Add multi-layer support to DrawBit so pixel-art pieces can be composed from stacked, independently-edited grids. Targets the common pixel-art workflow of separating a sketch / line work / fill / lighting onto distinct layers.

## Goals

1. **Layers feature is genuinely useful** — multiple stacked layers, switch active layer, hide/show, reorder, duplicate, lock, rename, delete.
2. **No glitches in the existing app.** Every existing test passes unchanged. A single-layer piece produces a byte-identical PNG export to today's code path. The user-facing app behavior is identical until the user explicitly engages with the new panel.
3. **Architecture invariants are preserved.** All layer logic is pure-logic (in `DrawBit/Drawing/` and `DrawBit/Rendering/`). `PieceRepository` remains the only SwiftData seam. The UI → State → Persistence → Rendering → Drawing dependency direction is preserved.
4. **Shippable in stages.** The work is decomposed so that each merge to main leaves a fully-functional app. No long-lived branch.

## Non-goals (explicit, to prevent scope creep)

- **No per-layer opacity slider.** Every layer is 100% opaque. This is the deliberate scope cut that preserves the existing "alpha is 0 or 255" rendering invariant — see [Rendering invariant](#rendering-invariant) below.
- **No blend modes.** Layers composite with a simple "topmost non-transparent pixel wins" rule.
- **No layer groups / folders / nested layers.**
- **No layer effects, masks, or adjustment layers.**
- **No animation / frames / shared layers across frames.** Animation is a separate, future project. The data model is intentionally *not* future-proofed for it; when animation lands it gets its own design.
- **No layered file import / export** (PSD, Aseprite, etc.). PNG export remains a single flat image.
- **No iPhone layout work.** Layout is iPad only, matching the existing app.

## Scope (in scope for v2)

### Layer attributes

Each layer carries:
- A stable `UUID` (used for active-layer reference, undo entries, and any future animation work).
- A user-editable `name` (defaults to `"Layer N"` where N is the next unused integer for that piece).
- The pixel data (raw RGBA bytes, same format as today's `PixelGrid`).
- `isVisible` (bool, default `true`).
- `isLocked` (bool, default `false`).

There is **no** opacity field, **no** blend-mode field, **no** position/transform field, **no** lock-position-vs-lock-pixels distinction.

### Stack order convention

The layer array is stored bottom-up: index 0 is the bottommost layer (drawn first), the last index is topmost (drawn last). The UI panel inverts this for display so the topmost layer sits at the top of the visible list — matching Photoshop / Procreate / Aseprite.

### Defaults & limits

- **New piece:** one empty layer named `"Layer 1"`, set as active.
- **Hard cap:** 16 layers per piece. Trying to add a 17th is disabled at the UI level (the `+` button greys out) with no error dialog.
- **Minimum:** 1 layer. Deleting the last layer is disabled at the UI level (the `×` button greys out).

### Tool semantics on a layered canvas

- **Pencil / Eraser / Fill / Marquee** all operate on the *active layer* only. Other layers are untouched.
- **Eyedropper** samples from the *composited image* (what the user sees), not from the active layer alone. Sampling a transparent area of the composite remains a no-op (matches today).
- **Fill bucket** flood-fills within the active layer, ignoring boundaries that exist only on other layers. Determined by the active layer's own colors.
- **Marquee** cuts and floats pixels from the active layer only. Other layers stay put behind the floating selection.

### Layer-level operations

From the layers panel:
- **Add** an empty layer above the active one. Auto-named `"Layer N"`.
- **Duplicate** the active layer. New layer is placed directly above the original. Auto-named `"<original> copy"`.
- **Delete** the active layer (with `.confirmationDialog` if it has any non-transparent pixels; auto-confirm if it's empty). After deletion, the layer below becomes active (or the layer above, if the deleted one was the bottom).
- **Reorder** by long-press-and-drag on the row.
- **Rename** by long-press on the layer's name (inline text field).
- **Toggle visibility** by tapping the eye icon.
- **Toggle lock** by tapping the padlock icon.
- **Tap any row** to make that layer active.

### Lock semantics

A locked layer:
- **Cannot** be drawn on, erased, filled, marquee-cut, deleted, or reordered.
- **Can** still have its visibility toggled, be renamed, be duplicated (the duplicate inherits the lock state).

If the user attempts a drawing operation on a locked layer, the operation is silently a no-op and the layer's row in the panel pulses red briefly to indicate why.

### Active-layer indicator

The active layer's row in the panel has a blue tint background. There is no on-canvas overlay indicating which layer is active — the panel is the source of truth.

## Rendering invariant

This is the load-bearing decision behind dropping opacity from scope.

Today, every pixel in a `PixelGrid` is either fully visible (`alpha = 255`) or fully invisible (`alpha = 0`). The rendering pipeline relies on this:

> *(from CLAUDE.md)* `CGImage` is built with `.premultipliedLast`, which is identical to straight alpha as long as alpha is only 0 or 255 — so the eraser must write `alpha = 0` exactly … and drawing tools must never produce partial alpha.

With layer opacity, a 50%-opacity layer would produce composited pixels with `alpha = 128`, breaking this invariant and forcing a more careful look at premultiplication, color-space gamma, and possibly the `CGBitmapInfo` flags throughout the pipeline. By keeping every layer at 100% opacity:

- The composite of N visible layers produces pixels with `alpha = 0` or `alpha = 255` only.
- The existing `pixelsToCGImage`, `ThumbnailRenderer`, and `PNGExporter` continue to be correct, byte-for-byte, without any change to their core rendering logic.
- The single-layer non-regression test (PNG export of a one-layer piece must equal v1's PNG output) is structurally guaranteed, not just empirically tested.

## Data model & persistence

### New types in `DrawBit/Drawing/`

```swift
struct Layer: Equatable {
    let id: UUID
    var name: String
    var pixels: Data          // raw RGBA bytes, same format/size as today's PixelGrid.data
    var isVisible: Bool
    var isLocked: Bool
}

struct Frame: Equatable {
    var layers: [Layer]       // bottom-up: index 0 is the bottommost layer
    var activeLayerID: UUID   // must reference a layer in `layers`; invariant enforced by mutator API
}
```

`Frame` exposes a small mutator API (e.g., `addLayer(_:above:)`, `removeLayer(id:)`, `move(id:to:)`, `setActive(id:)`, `withActiveLayerPixels(_:)`) which preserves the `activeLayerID` invariant. Tools never reach into `frame.layers` directly; they go through `Frame`.

### Encoding format (`FrameCodec`)

Frames are persisted as a versioned binary blob — pure-logic, in `DrawBit/Drawing/FrameCodec.swift`. Versioned so the format can evolve without ambiguity.

```
Header:
  4 bytes  ASCII "DBFR"            // magic — used to detect v1 vs v2 data
  1 byte   format version          // currently 1 (this is the layered format's version 1)
  2 bytes  layer count (UInt16, big-endian)
 16 bytes  active layer UUID

Per-layer:
 16 bytes  layer UUID
  1 byte   flags (bit 0 = visible, bit 1 = locked, bits 2-7 reserved zero)
  1 byte   name length in UTF-8 bytes (panel UI limits user input to 32 UTF-8 bytes)
  N bytes  name (UTF-8)
  4 bytes  pixel byte count (UInt32, big-endian)
  N bytes  raw RGBA pixel data
```

JSON / `Codable` is deliberately not used because pixel data is already raw bytes; `Codable` would Base64-encode it and roughly double on-disk size.

### `Piece` schema change

The existing `pixels: Data` field is replaced by `frameData: Data`, with `@Attribute(.externalStorage)` so SwiftData spills the blob to a separate file rather than the main store row.

```swift
@Model final class Piece {
    @Attribute(.unique) var id: UUID
    var name: String?
    var sizeRaw: Int
    @Attribute(.externalStorage) var frameData: Data   // was `pixels: Data`
    var thumbnail: Data
    var createdAt: Date
    var updatedAt: Date
}
```

This is a SwiftData lightweight migration (rename of one stored property). No `schemaVersion` field is needed because of the migration approach below.

### Migration

One-shot eager migration on first launch of v2, plus a per-read defense-in-depth check.

**Primary path — eager pass on app boot.** `PieceRepository.migrateLegacyPiecesIfNeeded()` runs once on app start. It scans every `Piece` and checks if `frameData` begins with the `"DBFR"` magic. If not, it treats `frameData` as raw v1 RGBA bytes, wraps it in a `Frame` containing one layer named `"Layer 1"` (with a fresh UUID), encodes it via `FrameCodec`, and writes it back. Pieces that already have the magic are skipped.

**Defense-in-depth — per-read check.** `PieceRepository.loadFrame(piece:)` also checks the magic prefix when loading a piece. If absent, it migrates that single piece in place (same wrap-as-one-layer logic) and writes the result back before returning. This handles any piece the eager pass missed (e.g., a piece written by an older binary while a newer binary is running, or any future scenario where rows arrive after launch).

Justification for not adding a `schemaVersion` field: the magic-prefix check is just as reliable, costs nothing meaningful per-read (one byte comparison), and avoids a SwiftData schema change beyond the rename. Once migration has run, every piece is in the v2 format and both paths become no-ops forever.

The app has not been distributed at the time of writing, so this migration only affects the developer's own dev pieces. There is no production rollback path required.

## Rendering pipeline

### New: `Compositor` in `DrawBit/Rendering/`

```swift
struct CompositedBuffer {
    let data: Data            // RGBA bytes, alpha 0 or 255 (invariant)
    let size: CanvasSize
}

enum Compositor {
    static func composite(_ frame: Frame, size: CanvasSize) -> CompositedBuffer
}
```

Algorithm: walk `frame.layers` bottom-up. For each pixel position, scan layers from top down (last to first), pick the first pixel with `alpha == 255`. If none, the output pixel is `(0, 0, 0, 0)`. Layers with `isVisible == false` are skipped entirely.

Because every layer's pixels are guaranteed `alpha ∈ {0, 255}` and there is no opacity multiplier, the output buffer's pixels also satisfy `alpha ∈ {0, 255}`. The rendering invariant is preserved.

### Adapted existing functions

- `pixelsToCGImage(_ grid: PixelGrid)` → `bufferToCGImage(_ buffer: CompositedBuffer)`. Implementation is otherwise unchanged: `CGColorSpace.sRGB`, `CGImageAlphaInfo.premultipliedLast`, `shouldInterpolate: false`. Renamed because its input is now a composited buffer rather than a single grid.
- `PNGExporter.export(grid: scale:)` → `export(frame: scale:)`. Composites internally, then runs the existing scale-up `CGContext` code unchanged.
- `ThumbnailRenderer.render(grid: targetEdge:)` → `render(frame: targetEdge:)`. Composites internally.

A small per-layer thumbnail helper is also added for the layers panel:

```swift
enum LayerThumbnailRenderer {
    static func render(layer: Layer, size: CanvasSize, targetEdge: Int) -> Data?
}
```

This renders a single layer's pixels (treating transparent areas as transparent — the panel UI shows checkerboard behind it).

### Single-layer non-regression guarantee

A test fixture loads a piece with one fully-visible layer at the four canvas sizes (16, 32, 64, 128) using a known set of pixels. It exports a PNG via the v2 path (`Compositor` → `PNGExporter.export(frame:scale:)`) and compares it byte-for-byte to a PNG produced by the v1 code path (kept around for the duration of this work as a reference implementation in tests, then removed once all stages have shipped). They MUST match.

This is the test that proves "single-layer pieces look identical in v2."

## State changes (`EditorState`)

### Replacing `grid` with a `Frame`

`EditorState.grid: PixelGrid` is replaced by `EditorState.frame: Frame`. A computed convenience property `EditorState.activeLayerPixelGrid` exposes the active layer's pixels as a `PixelGrid` value (mutated in place via the `Frame` mutator API).

Tool routing in `EditorView.applyDrawPoint` becomes:

- Pencil / Eraser / Fill: mutate `state.frame.activeLayerPixels` (with lock check first).
- Eyedropper: sample from `Compositor.composite(state.frame, size:)`.
- Marquee: extract from / commit into the active layer only.

### Lock enforcement

A single guard at the top of `applyDrawPoint` (and in marquee define):

```
if state.activeLayerIsLocked && tool is mutating { return; trigger lock-pulse }
```

Tools themselves remain pure-logic and do not know about locks.

### Undo storage

The current `[Data]` of grid snapshots becomes a `[UndoEntry]` of:

```swift
enum UndoEntry {
    case layerPixels(layerID: UUID, before: Data)   // drawing on a layer (common)
    case frameStructure(before: Frame)              // structural change (rare)
}
```

- Drawing strokes (pencil/eraser/fill/marquee on active layer) push a `.layerPixels` entry. Memory cost: same as today's per-stroke snapshot.
- Structural changes (add / delete / reorder / rename / visibility-toggle / lock-toggle) push a `.frameStructure` entry. Memory cost: bounded by `cap × bytes-per-layer` (max ~1 MB at 16 layers × 64 KB per layer at 128×128).

Undo limit stays at 50.

### Marquee × layers interaction

A floating marquee selection is committed automatically on any of:
- Tool switch (already today).
- Active-layer change.
- Reorder, hide, lock, delete, or rename of *any* layer.
- Editor dismiss.

This avoids the ambiguity of "what does the floating selection mean if its source layer goes away?"

## UI

### Top bar gains a layers toggle

A new `LAYERS` button is added to the top bar, alongside `GALLERY`, the size label, and `SHARE`. The label is rendered as the all-caps text `LAYERS` to match the existing top-bar labels (`GALLERY`, `SHARE`) — no icon. Tapping it toggles the layers panel. The button has an active state (filled background) when the panel is open.

### Layers panel

Toggleable overlay sliding in from the right, taking ~38% of width on iPad (matching the wireframe approved during brainstorming). The canvas behind is dimmed slightly (~15% black overlay) but remains visible so the user keeps spatial context. Tap the canvas (anywhere outside the panel) or tap `LAYERS` again to dismiss.

Each layer row contains, left to right:
- A 32×32 thumbnail of just that layer's pixels, with checkerboard background visible through transparent areas.
- The layer's name.
- A small `eye` icon (visibility toggle).
- A small `padlock` icon (lock toggle).
- A `≡` drag handle (reorder).

The active layer's row is highlighted with the app's blue accent color. Tap a row to make it active.

Action bar at the bottom of the panel:
- `+` Add empty layer above active. Disabled if at the 16-layer cap.
- `⎘` Duplicate active layer. Disabled if at the 16-layer cap.
- `×` Delete active layer. Disabled if only one layer remains.

Long-press the layer's name to rename inline. Long-press the row to start drag-to-reorder (uses SwiftUI's standard list reordering).

### No on-canvas chrome change

The canvas itself does not gain any new visual indicators. The panel is the only visual surface for layer state.

## Out of scope file-tree summary

Files added:
```
DrawBit/Drawing/Layer.swift
DrawBit/Drawing/Frame.swift
DrawBit/Drawing/FrameCodec.swift
DrawBit/Rendering/Compositor.swift
DrawBit/Rendering/LayerThumbnailRenderer.swift
DrawBit/Views/Editor/LayersPanel.swift
DrawBit/Views/Editor/LayerRow.swift
```

Files renamed / signature-changed:
```
DrawBit/Models/Piece.swift                  pixels → frameData
DrawBit/Persistence/PieceRepository.swift   load/save Frame; one-shot migration
DrawBit/State/EditorState.swift             grid → frame; UndoEntry enum
DrawBit/Rendering/PixelsToCGImage.swift     pixelsToCGImage → bufferToCGImage
DrawBit/Rendering/PNGExporter.swift         grid: → frame:
DrawBit/Rendering/ThumbnailRenderer.swift   grid: → frame:
DrawBit/Views/Editor/EditorView.swift       layers panel toggle, tool routing
```

Files unchanged in behavior (pure call-site updates):
```
DrawBit/Drawing/Pencil.swift
DrawBit/Drawing/Eraser.swift
DrawBit/Drawing/Fill.swift
DrawBit/Drawing/Eyedropper.swift
DrawBit/Drawing/Marquee.swift
```

## Staged delivery plan

The implementation plan (separate document) will decompose the work into four merge-able stages, each of which leaves the app fully functional and shippable on its own:

1. **Stage 1 — Plumbing only, zero new behavior.** Introduce `Layer`, `Frame`, `FrameCodec`, `Compositor`, `bufferToCGImage`. Adapt `PieceRepository`, `PNGExporter`, `ThumbnailRenderer`, `EditorState`, `EditorView` to use the new types, but every piece always has exactly one layer. No layers panel UI. The non-regression test is the gate for this stage.

2. **Stage 2 — Read-only layers panel.** Add the toggleable overlay panel. It shows the (single) layer with name, eye, padlock, drag handle. No add / delete / reorder yet. Renaming works. The panel proves itself UI-wise before being asked to do anything destructive.

3. **Stage 3 — Add / delete / duplicate / reorder.** Now the panel does what it looks like. Drawing routes to the active layer. Marquee × layer interactions implemented. Hard cap of 16 enforced.

4. **Stage 4 — Visibility toggle and lock.** Eye and padlock become functional. Lock-pulse animation. Hidden layers don't composite.

Each stage has its own tests and is merged to `main` only when those tests pass and a manual device check confirms the app still behaves correctly.

## Testing strategy

### Unit tests (mirror the source tree)

- `DrawBitTests/Drawing/FrameTests.swift` — `Frame` mutators preserve `activeLayerID` invariant; reorder, add, delete, set-active behave correctly.
- `DrawBitTests/Drawing/FrameCodecTests.swift` — round-trip for known frames; "DBFR" magic correctly identifies v2; v1 detection (no magic) returns the right signal.
- `DrawBitTests/Rendering/CompositorTests.swift`:
  - Single visible layer == that layer's bytes.
  - Two layers, top fully opaque covering area X: top wins inside X, bottom wins outside.
  - Hidden layer skipped.
  - Empty piece (all transparent layers) → all-transparent output.
  - **Non-regression:** known fixture pixels through `Compositor` + `PNGExporter` produces byte-identical PNG to v1's `PNGExporter.export(grid:)` for every supported canvas size.
- `DrawBitTests/Persistence/MigrationTests.swift` — fixtures of v1 piece data on disk migrate cleanly into v2 frames; idempotent (running migration a second time is a no-op); v1-detection by magic prefix.
- `DrawBitTests/State/EditorStateLayersTests.swift` — undo of a draw stroke restores only the active layer; undo of a layer-add removes the layer; undo of a reorder restores the order; lock prevents drawing.

### UI tests (`DrawBitUITests`)

One happy-path test per stage. By Stage 4:
- New piece → open layers panel → add a layer → draw on it → hide it (canvas updates) → show it → undo (canvas updates) → close panel → return to gallery → re-open piece → layers persisted.

### Manual device checklist (gate for merging each stage to main)

- Draw a piece on multiple layers. Export to Photos. Visual sanity match.
- Toggle visibility rapidly while drawing. No partial commits. No flicker.
- Delete a layer in the middle of a marquee drag. Cancels cleanly, no crash.
- Reorder layers, then undo. State matches expectation.
- Force-quit mid-stroke. Reopen. App state is consistent (current stroke lost; everything previously committed intact — same as today).

## Risks and mitigations

1. **SwiftData rename migration goes wrong.** *Mitigation:* the rename `pixels → frameData` is a one-line attribute change. SwiftData will auto-migrate. As insurance, the lazy magic-prefix detection in `loadFrame(piece:)` falls back to "treat as v1 raw blob" if anything looks off — meaning a botched rename still produces correct output, it just runs the bootstrap again.

2. **Layered undo memory growth.** *Mitigation:* tagged-enum undo stores only the active layer's pixels for drawing (the common case). Structural changes are rare and small (max 1 MB at the 128×128 / 16-layer worst case, well within iPad memory).

3. **Compositor performance at high layer counts.** *Mitigation:* at the hard cap of 16 layers × 128×128 (the largest canvas) = 16,384 × 16 = 262,144 pixel-look-ups per composite, which is trivially fast. Compositor uses straightforward `Data` byte access; no allocation per pixel. Can be cached between strokes if profiling shows hot spots.

4. **"Looks fine in simulator, broken on device" rendering glitches.** *Mitigation:* (a) the rendering invariant is preserved by the no-opacity scope cut, (b) every existing fidelity test continues to run, (c) Stage 1's non-regression test forces visual byte-identity for single-layer pieces, (d) manual on-device check is mandatory before each stage merges.

5. **Marquee × layer change races.** *Mitigation:* every layer-mutating operation auto-commits any floating marquee first, mirroring the existing `setTool` pattern.

## Open questions

None. All decisions captured above.
