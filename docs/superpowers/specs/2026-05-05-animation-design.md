# DrawBit — Animation (v1)

**Status:** Draft — awaiting user sign-off before implementation planning.
**Date:** 2026-05-05
**Branch:** to be developed on `animation` and only merged when fully verified.
**Predecessor:** [Layers v2 design](./2026-05-02-layers-design.md), shipped 2026-05-04 — this spec builds on its types (`Layer`, `Frame`, `FrameCodec`, `Compositor`).
**Distribution status at time of writing:** App not yet shipped to App Store. Migration concerns are local-only (developer's own pieces on simulators / dev devices).

## Purpose

Add frame-by-frame animation to DrawBit so a Piece can hold a sequence of frames and play them back as a loop. Targets short pixel-art animations: walk cycles, idle bobs, sprite VFX, simple character loops. Animation is the second of two named price-bump features (alongside Layers v2). It moves DrawBit from "pixel sketchpad" to a tool that competes at the lower end of the pixel-art animation market (Aseprite, Procreate animation).

The data-model name `Frame` was chosen during the Layers v2 work with this feature in mind. Today a `Piece` holds one `Frame`; the core change is having it hold a sequence.

## Goals

1. **Animation feature is genuinely useful** — multi-frame pieces, scrub between frames, add/duplicate/delete/reorder/rename frames, play back at a chosen FPS, draw with a previous-frame ghost (onion skinning), export to GIF and animated PNG.
2. **No glitches in the existing app.** Every existing test passes unchanged. A single-frame piece produces byte-identical PNG export to today's code path (the same guarantee Layers v2 made for single-layer pieces). The user-facing app behavior is identical until the user explicitly engages with the timeline.
3. **Architecture invariants are preserved.** All animation logic is pure-logic (in `DrawBit/Drawing/` and `DrawBit/Rendering/`). `PieceRepository` remains the only SwiftData seam. The UI → State → Persistence → Rendering → Drawing dependency direction is preserved. Tools never know about frames.
4. **Shippable in stages.** The work decomposes into six merge-able stages, each leaving the app fully functional. Same cadence as Layers v2.

## Non-goals (explicit, to prevent scope creep)

- **No cel-style per-layer timelines.** Frames are full snapshots; there is no concept of a "cel" that lives on its own track. Layers are global to the Piece (same `[Layer]` shape across every frame); per-frame variation is in the *pixels* of those layers, not in the layer set.
- **No per-frame duration override.** A single FPS applies to the whole animation. Per-frame holds (long pose, quick action, long pose) are a v2 feature.
- **No tweened or interpolated animation.** No transform tracks, no keyframes, no easing curves. Frame-by-frame only.
- **No one-shot playback.** Playback always loops in v1.
- **No "shared layer" mode** (a layer that uses one image across every frame). Every layer is animated; if you want a static background, you copy its pixels into every frame's slot. (A future enhancement turning this into a per-layer mode toggle is documented in follow-ups but not in scope here.)
- **No frame-level effects, transitions, or blend modes between frames.**
- **No sprite-sheet PNG export, no MP4 export.** GIF and APNG only in v1.
- **No onion-skin "next frame" or intensity/tint settings UI.** v1 ships previous-frame ghost only at a fixed intensity.
- **No iPhone layout work.** iPad only, matching the existing app.

## Scope (in scope for v1)

### Frame attributes

A `Frame` already exists from Layers v2 with `layers: [Layer]` and `activeLayerID: UUID`. For animation, each `Frame` additionally carries:

- A stable `id: UUID` — needed for stable references from undo entries, scrub state, and any future per-frame metadata.
- A `name: String` — defaults to `"Frame N"` where N is the next unused integer for that Piece. The name backs auto-numbering for Add/Duplicate only; it is **not** user-editable and is not shown in the strip (per-frame rename was removed 2026-06-22 — frames are positional, identified by their index badge).

Layer metadata (name, visibility, lock) is kept **synchronized across all frames in a Piece** — every frame's `layers` array has the same UUIDs in the same order, with the same `name`/`isVisible`/`isLocked`. Only the per-layer `pixels: Data` differs frame to frame. The frame-sequence API (below) is the only seam that mutates layers, and it always cascades layer metadata changes across every frame.

### Frame-sequence convention

The Piece holds a `frames: [Frame]` array, ordered by playback order: index 0 is the first frame shown, the last index is the last frame before the loop wraps. The timeline strip displays in this order, left to right.

### Defaults & limits

- **New Piece:** one frame named `"Frame 1"`, with one empty layer `"Layer 1"` (matches today's single-frame default).
- **Hard cap:** 60 frames per Piece. Trying to add a 61st is disabled at the UI level (the `+` button greys out) with no error dialog.
- **Minimum:** 1 frame. Deleting the last frame is disabled (the `×` button greys out).
- **Default FPS:** 12 fps (a reasonable midpoint for pixel art).
- **FPS choices:** 4, 8, 12, 24, 30, 60 — discrete picker in the timeline strip.

### Tool semantics on an animated canvas

- **All drawing tools (pencil / eraser / fill / marquee)** operate on the *active layer of the active frame* only. Other frames are untouched. This is the natural extension of the Layers v2 rule.
- **Eyedropper** samples from the *composited image of the active frame*, not from any other frame. Ghosted onion-skin pixels are *not* sampled (the ghost is a display overlay only).
- **Marquee** cuts and floats pixels from the active layer of the active frame only. Switching frames mid-marquee auto-commits the floating selection back into its source frame and layer (see [marquee × frame](#marquee-x-frame-interaction) below).

### Frame-level operations

From the timeline strip:

- **Add** a new frame after the active frame. New frame is a **duplicate of the active frame** (every layer's pixels are copied). The new frame becomes active. Auto-named `"Frame N"` where N is the next unused integer.
- **Duplicate** and **Delete** the active frame via small monochrome glyphs shown **only on the selected frame** (top-right corner — the number badge owns top-left): a duplicate icon (⧉) and a delete **×**. Duplicate is always available; Delete is hidden on the last remaining frame. Both are direct on-frame affordances, **not** a popup menu — a themed long-press popup can't coexist with the `.draggable` reorder gesture (the drag-lift recognizer swallows the long press), so the actions live on the frame instead. Delete confirms via `.confirmationDialog` if the frame has any non-transparent pixels in any layer; auto-confirms if every layer is empty. After deletion, the previous frame becomes active (or the next one, if the deleted frame was the first). Duplicate has the same behavior as Add.
- **Reorder** by drag-and-drop on the frame thumbnails.
- _(Per-frame rename and the per-frame context menu were both removed 2026-06-22.)_
- **Tap any frame** to make it active (auto-commits any floating marquee first).

### Layer-level operations cascade across frames

Every Layers v2 operation (add / duplicate / delete / reorder / rename / visibility toggle / lock toggle) applies to every frame in the sequence:

- **Add layer:** insert a new empty `Layer` (same UUID) at the same index in every frame. Pixel data is empty for every frame.
- **Delete layer:** remove the layer with that UUID from every frame.
- **Duplicate layer:** copy the active layer in every frame. The duplicate's pixels in each frame are a copy of the source layer's pixels in *that frame*.
- **Reorder layer:** apply the same reorder to every frame's `layers` array.
- **Rename / visibility / lock:** mutate that UUID's metadata in every frame, kept identical.

The Layers panel (Layers v2) continues to work exactly as before — its operations now silently cascade to every frame.

### Onion skinning

A toggle in the timeline strip enables/disables onion skinning. When on, the canvas displays the previous frame as a faded ghost beneath the current frame, helping the artist line up motion between frames.

- **Visibility:** previous frame only in v1. Next-frame ghost is a follow-up.
- **Intensity:** fixed at ~30% opacity in v1. No tint, no settings UI.
- **Disabled during playback:** the ghost is purely a draw-time aid; while playing, only the current frame is shown.
- **Disabled when active frame is the first frame:** there is no "previous" frame to ghost.

The ghost is a *display-only overlay* in `CanvasView`, drawn beneath the active frame's composite. It is never written into pixel storage. This preserves the rendering invariant (see below).

### Playback

A play / pause button in the timeline strip starts looping playback at the chosen FPS.

- **While playing:** drawing tools, frame ops, layer ops, onion-skin toggle, and the FPS picker are all disabled. Only play/pause itself and GALLERY dismiss remain active. Tapping the canvas does nothing.
- **Loop:** always loops. There is no one-shot mode in v1.
- **FPS:** picker right next to play/pause. Disabled while playing in v1 because the underlying `Timer` is armed at `start()` time and does not auto-re-arm when `state.fps` changes; the user must pause and resume to apply a new rate. (Earlier spec said "Changing FPS mid-playback updates the rate immediately." — that proved to require a stop/start pattern that didn't match the simpler controller design; deferred as a v1.1 enhancement.)
- **Stop behavior:** tapping pause leaves the active frame at whatever frame was on screen when paused (so the artist can continue drawing on the frame they last saw). The pause point is persisted via `saveCurrentFrame()` so a force-quit doesn't lose it.
- **Floating marquee on play:** auto-committed before the timer arms (mirrors the Stage 4 holistic-review fix). The same auto-commit also runs on SHARE so animated exports include any in-flight marquee instead of dropping it.

### Marquee × frame interaction

A floating marquee selection is committed automatically on any of:
- Tool switch (already today).
- Active-layer change (Layers v2).
- **Active-frame change.** (new)
- **Any frame-sequence mutation** — add, duplicate, delete, reorder, rename. (new)
- Editor dismiss.

Same rationale as Layers v2: the floating selection is a transient extraction from a specific layer in a specific frame. If that frame goes away or stops being active, commit-back is the only sane resolution.

### Active-frame indicator

The active frame's thumbnail in the strip has a blue accent border. The strip itself shows the playback scrub position visually (a vertical line / highlighted thumbnail). There is no on-canvas overlay indicating which frame is active — the strip is the source of truth.

## Rendering invariant

The Layers v2 invariant — every composited buffer has `alpha ∈ {0, 255}` — is preserved.

Per-frame compositing uses the existing `Compositor.composite(_:size:)` unchanged. Each frame produces its own buffer with the alpha-0-or-255 guarantee.

The onion skin breaks the *display* invariant (the canvas now shows partial alpha from the ghost overlay), but it does **not** break the *storage* or *export* invariant — the ghost is never written into a `Frame`'s pixels and is never composited into the GIF/APNG export. It exists only in `CanvasView`'s draw step. The previous-frame ghost is drawn first (with a 30% alpha multiplier applied at draw time, not in stored pixel data), then the active-frame composite is drawn on top.

GIF and APNG exports use the same per-frame `Compositor` output that PNG export does today. Each frame is rendered nearest-neighbor at the chosen scale, with the same `CGColorSpace.sRGB` and `CGImageAlphaInfo.premultipliedLast` invariants as `PNGExporter`. The single-frame non-regression test guarantees byte-identical output to today's PNG path for a one-frame Piece.

## Data model & persistence

### Updated types in `DrawBit/Drawing/`

`Frame` (existing, from Layers v2) gains `id` and `name`:

```swift
struct Frame: Equatable {
    let id: UUID                  // (new) stable id for sequence references
    var name: String              // (new) user-editable, defaults to "Frame N"
    var layers: [Layer]
    var activeLayerID: UUID
}
```

A new pure-logic helper file `DrawBit/Drawing/FrameSequence.swift` exposes the sequence-mutator API:

```swift
enum FrameSequence {
    static func addFrame(after frameID: UUID, in frames: inout [Frame]) -> UUID?
    static func duplicateFrame(_ frameID: UUID, in frames: inout [Frame]) -> UUID?
    static func removeFrame(_ frameID: UUID, in frames: inout [Frame])
    static func move(frameID: UUID, toIndex: Int, in frames: inout [Frame])
    static func setName(frameID: UUID, to name: String, in frames: inout [Frame])

    // Layer ops cascade across the sequence:
    static func addLayer(name: String, in frames: inout [Frame]) -> UUID?
    static func duplicateLayer(_ layerID: UUID, in frames: inout [Frame]) -> UUID?
    static func removeLayer(_ layerID: UUID, in frames: inout [Frame])
    static func moveLayer(_ layerID: UUID, toIndex: Int, in frames: inout [Frame])
    static func setLayerName(_ layerID: UUID, to name: String, in frames: inout [Frame])
    static func setLayerVisible(_ layerID: UUID, _ visible: Bool, in frames: inout [Frame])
    static func setLayerLocked(_ layerID: UUID, _ locked: Bool, in frames: inout [Frame])

    // Reorder math, analog of Frame.modelTargetIndex:
    static func modelTargetIndex(displayedFrom: Int, newOffset: Int, count: Int) -> Int?
}
```

Tools never call `FrameSequence`; they go through `EditorState` which routes pixel mutations to the active layer of the active frame.

### Encoding format (`FrameCodec` V2)

A new top-level container format. The single-frame "DBFR" format (V1) is kept for backwards compat on read.

```
Sequence header:
  4 bytes  ASCII "DBFS"           // sequence magic
  1 byte   sequence format version // currently 1
  2 bytes  frame count (UInt16, big-endian)
  2 bytes  active frame index (UInt16, big-endian)
  2 bytes  fps (UInt16, big-endian)

Per frame:
 16 bytes  frame UUID
  1 byte   name length (UTF-8 bytes, max 32 by UI)
  N bytes  name (UTF-8)
  4 bytes  inner blob length (UInt32, big-endian)
  N bytes  inner blob — the existing FrameCodec V1 "DBFR" blob
```

The per-frame inner blob is the existing V1 Frame format unchanged. This is deliberate — the V1 encoder/decoder for a single Frame stays as a stable building block, and V2 just adds the sequence wrapper.

**FPS lives in the sequence header** because it's a property of the animation as a whole and is also the GIF/APNG export rate. It is not a per-frame value (single FPS only in v1).

### Backwards-compat read path

```swift
enum FrameCodec {
    static func decodeSequence(_ data: Data) throws -> (frames: [Frame], activeFrameIndex: Int, fps: Int)
}
```

`decodeSequence` checks the magic at offset 0:
- `"DBFS"` → decode as V2 sequence directly.
- `"DBFR"` → decode as a single V1 Frame, return `(frames: [oneFrame], activeFrameIndex: 0, fps: 12)`.
- anything else → `DecodeError.badMagic`.

**Two-tier migration: eager + lazy.** On app launch, `PieceRepository.migrateLegacyPiecesIfNeeded()` walks every `Piece` and rewrites V1 / raw blobs to V2 (matching the Layers v2 pattern). As defense in depth, `loadFrames(piece:)` also detects V1 / raw on read and migrates the offending Piece in place before returning. No SwiftData schema change is required (`Piece.frameData: Data` field stays); only the blob content interpretation changes. Existing Pieces seamlessly become single-frame V2 sequences whether the user opens the app cold (eager pass) or imports a Piece via duplicate / file-share later (lazy on-read).

### `Piece` schema (no change)

```swift
@Model final class Piece {
    @Attribute(.unique) var id: UUID
    var name: String?
    var sizeRaw: Int
    @Attribute(.externalStorage) var frameData: Data   // semantics: now a "DBFS" blob
    var thumbnail: Data
    var createdAt: Date
    var updatedAt: Date
}
```

`thumbnail` continues to be the composite of the *first* frame, scaled small — gallery rows show the first frame.

## State changes (`EditorState`)

### Replacing `frame` with a sequence

`EditorState.frame: Frame` becomes:

```swift
var frames: [Frame]
var activeFrameIndex: Int   // valid index into `frames`
var fps: Int

// Convenience (kept for source compatibility with most tool call sites):
var frame: Frame {
    get { frames[activeFrameIndex] }
    set { frames[activeFrameIndex] = newValue }
}
```

The existing `frame` accessor returns a value-type read of the active frame; mutations go through it via the `withActiveLayerPixels` pattern, which now reaches into `frames[activeFrameIndex].layers[activeLayerIndex].pixels`.

### Active-frame change semantics

```swift
func setActiveFrame(index: Int)
```

- Auto-commits any floating marquee in the *current* active frame first (pushes a layer-pixels undo entry as a side effect of `commitMarquee`).
- Cancels any *pending* marquee rect (mid-define). Mirrors `setTool`: floating → commit, pending → cancel.
- Cancels any in-flight stroke (defensive — there shouldn't be one if input is properly gated).
- Updates `activeFrameIndex`.
- Does NOT push an undo entry for the frame switch itself (navigation action, not an edit).

### Onion skinning state

```swift
var isOnionSkinEnabled: Bool   // session-only, NOT persisted to Piece
```

Toggle lives in `EditorState`. Default `false`. The Compositor is *not* aware of onion skin — `CanvasView` reads `isOnionSkinEnabled` and the previous frame directly to render the ghost.

### Playback state

```swift
var isPlaying: Bool   // session-only
```

A separate `PlaybackController` (in `DrawBit/State/`) owns the `Timer` and advances `state.activeFrameIndex` on each tick. While `isPlaying == true`, drawing input, marquee, frame ops, layer ops, and onion-skin toggle are all gated off in `EditorView`.

### Undo storage

The current `UndoEntry` enum gains a third case:

```swift
enum UndoEntry {
    case layerPixels(frameID: UUID, layerID: UUID, before: Data)   // (changed) now identifies the frame too
    case frameStructure(before: Frame)                              // (existing) within-frame structural change
    case sequenceStructure(before: [Frame], beforeActive: Int)      // (new) frame-sequence structural change
}
```

- Drawing strokes push `.layerPixels(frameID:layerID:before:)`. Frame is identified by UUID, not index, so undo survives frame reorders.
- Layer ops (add/delete/reorder/rename/visibility/lock) — these now cascade across frames; they push a `.sequenceStructure` entry capturing the full sequence (since multiple frames are mutated).
- Frame ops (add/duplicate/delete/reorder/rename) push a `.sequenceStructure` entry.
- The existing `.frameStructure` case is no longer used after Stage 1; remove it (or keep as a vestige if cleaner) once sequence-level undo is in.

Memory cost: `.sequenceStructure` snapshots the full `[Frame]`. Worst case at the cap: 60 frames × 16 layers × 256×256 RGBA = 240 MB per snapshot. **This is too large** for a 50-deep undo stack.

Mitigation: `.sequenceStructure` only records what changed — a richer enum:

```swift
case sequenceStructure(beforeFrames: [Frame], beforeActive: Int)  // first-cut, big snapshot
```

is a starting point; if profiling shows memory pressure, switch to a delta-encoded form (e.g., `.layerInsertedInAllFrames(layerID, atIndex)`, `.frameInsertedAt(index, frame)`). This refinement is deferred to Stage 2 implementation but called out here so the implementer doesn't ship a memory bomb.

Undo limit stays at 50.

## Rendering pipeline

### Compositor (mostly unchanged)

`Compositor.composite(_:size:)` continues to take a single `Frame` and produce one buffer. No animation awareness. Per-frame compositing is the same algorithm as today.

### Onion skin (new, in `CanvasView`)

`CanvasView` gains an optional ghost-frame overlay. When `state.isOnionSkinEnabled && !state.isPlaying && state.activeFrameIndex > 0`:

1. Composite the previous frame (`state.frames[activeFrameIndex - 1]`) via `Compositor.composite`.
2. Convert to `CGImage` via `bufferToCGImage`.
3. Draw it into the canvas with `alpha = 0.3`. (The `.alpha` modifier or `CGContext.setAlpha(0.3)` — implementation choice; same nearest-neighbor invariants apply.)
4. Then draw the active-frame composite on top, fully opaque, as today.

The ghost is recomputed per draw pass — there is no caching in v1. At 256×256 with 16 layers, this is ~64 ms worst case once per scrub or stroke commit, which is acceptable. If the editor feels sluggish at large canvas sizes, cache the ghost composite keyed by `(frameID, frame.layers.hashValue)`.

### Per-frame thumbnails

The strip needs whole-frame thumbnails (composite all visible layers, render small). A new helper:

```swift
enum FrameThumbnailRenderer {
    static func render(frame: Frame, size: CanvasSize, targetEdge: Int) -> Data?
}
```

It composites via `Compositor.composite`, then runs the same `bufferToCGImage` + scaled `CGContext` path that `LayerThumbnailRenderer` uses today.

### GIF and APNG export

Two new files in `DrawBit/Rendering/`:

```swift
enum GIFExporter {
    static func export(frames: [Frame], size: CanvasSize, scale: Int, fps: Int) -> Data?
}

enum APNGExporter {
    static func export(frames: [Frame], size: CanvasSize, scale: Int, fps: Int) -> Data?
}
```

Both use ImageIO's multi-image destinations. Each frame is composited via `Compositor.composite`, scaled to `size.dimension * scale` via the same `CGContext` setup as `PNGExporter`, then added to the destination with a per-frame delay of `1.0 / fps` seconds.

- **GIF:** `UTType.gif`, `kCGImagePropertyGIFDictionary` with `kCGImagePropertyGIFLoopCount: 0` (infinite loop). Each frame's `kCGImagePropertyGIFDelayTime` is `1.0 / fps`.
- **APNG:** `UTType.png`, `kCGImagePropertyPNGDictionary` with `kCGImagePropertyAPNGLoopCount: 0`. Each frame's `kCGImagePropertyAPNGDelayTime` is `1.0 / fps`.

Single-frame Pieces export as a single-frame GIF/APNG (effectively a static image in those formats). Users with a single-frame piece will typically use PNG export; GIF/APNG remain available for completeness.

### Single-frame non-regression guarantee

A test fixture loads a Piece with one frame and one fully-visible layer (the post-Layers-v2 state of any pre-animation Piece). It exports a PNG via the v3 path (`Compositor` → `PNGExporter.export(frame:scale:)` with `frames[0]`) and compares it byte-for-byte to a PNG produced by the V2 (Layers v2) export path. They MUST match.

This proves "single-frame pieces look identical post-animation."

## UI

### Top bar

The top bar gains an FPS readout when a Piece has more than one frame. (Pieces with one frame look identical to today.) The readout is a small `12 fps` label between the existing `LAYERS` button and `SHARE`. Tapping it cycles through the FPS choices (4/8/12/24/30/60).

### Bottom timeline strip

A new persistent strip across the bottom of `EditorView`, ~52 pt tall. Always visible (no hide toggle in v1).

Left to right:
- **Play / pause button** (~32 pt circular, accent-blue when paused, red when playing).
- **FPS picker** — small label `12 fps`; tap to cycle.
- **Onion skin toggle** — small icon button, accent-blue when enabled.
- **Frame thumbnail row** — horizontal scroll, each thumbnail ~36×36 pt. Active frame has a 2 pt blue border. Tap a thumbnail to make that frame active.
- **Add button** (`+`) at the right end of the strip.
- **Action buttons** (visible in EDIT mode): duplicate (`⎘`), delete (`×`).
- **EDIT / DONE toggle** — tiny right-side button. EDIT mode swaps long-press-rename for drag-to-reorder, mirroring Layers v2.

Single-frame Pieces still show the strip (with one thumbnail, plus the add and play buttons). The strip's height steals from the canvas; the canvas re-centers to fit. Existing pieces look the same except for the strip beneath them.

### Frame rename

Long-press a thumbnail (when not in EDIT mode) → inline text field appears above the thumbnail, accepts up to 32 UTF-8 bytes, commits on return or tap-outside.

### Frame delete confirmation

Same UX as layer delete (Layers v2): if any layer in the frame has non-transparent pixels, show `.confirmationDialog`; if the frame is entirely empty, fast-path delete with no dialog.

### Playback UX

While playing:
- The play button becomes a pause button.
- Tools, layer panel, onion-skin toggle, frame ops are disabled (greyed out, taps no-op).
- The active-frame highlight in the strip moves automatically with playback.
- Pause leaves the active frame at whatever frame was last shown.

### No on-canvas chrome change beyond onion skin

The canvas itself does not gain new visual indicators except the onion-skin ghost (which is the entire point). No on-canvas frame number, no scrub overlay.

## Out of scope file-tree summary

Files added:
```
DrawBit/Drawing/FrameSequence.swift
DrawBit/Rendering/FrameThumbnailRenderer.swift
DrawBit/Rendering/GIFExporter.swift
DrawBit/Rendering/APNGExporter.swift
DrawBit/State/PlaybackController.swift
DrawBit/Views/Editor/FramesStrip.swift
DrawBit/Views/Editor/FrameRow.swift
```

Files modified:
```
DrawBit/Drawing/Frame.swift              add id and name
DrawBit/Drawing/FrameCodec.swift         add V2 sequence format
DrawBit/Models/Piece.swift               frameData semantics → DBFS sequence
DrawBit/Persistence/PieceRepository.swift  saveFrames/loadFrames
DrawBit/State/EditorState.swift          frames[]+activeFrameIndex+fps; sequence undo
DrawBit/Views/Editor/EditorView.swift    bottom strip placement, persistence callbacks, playback gates, onion-skin overlay
DrawBit/Views/Editor/CanvasView.swift    onion-skin ghost rendering
DrawBit/Views/Editor/ShareSheet.swift    GIF/APNG export options
```

Files unchanged in behavior (pure call-site updates, if any):
```
DrawBit/Drawing/Pencil.swift, Eraser.swift, Fill.swift, Eyedropper.swift, Marquee.swift
DrawBit/Drawing/Layer.swift
DrawBit/Rendering/Compositor.swift, PNGExporter.swift, ThumbnailRenderer.swift, LayerThumbnailRenderer.swift, PixelsToCGImage.swift
DrawBit/Views/Editor/LayersPanel.swift, LayerRow.swift, ToolBar.swift
```

## Staged delivery plan

The implementation plan (separate document) will decompose this into six merge-able stages, each leaving the app fully functional and shippable on its own. Same cadence as Layers v2.

1. **Stage 1 — Plumbing only, zero new behavior.** Add `Frame.id`/`name`, V2 codec (`DBFS`) with V1-fallback read, `Piece.frameData` semantics change, `EditorState.frames`+`activeFrameIndex`+`fps`. Layer-ops cascade through `FrameSequence`. Every Piece always has exactly one frame in this stage. No timeline UI. The single-frame non-regression test is the gate.

2. **Stage 2 — Frame ops API.** `FrameSequence.add/duplicate/remove/move/setName`. `EditorState.setActiveFrame`. Marquee auto-commit on frame change. Sequence-level undo. No timeline UI yet — exercised by unit tests only.

3. **Stage 3 — Bottom-strip timeline UI.** `FramesStrip` + `FrameRow`. Frame thumbnails (`FrameThumbnailRenderer`), tap-to-activate, EDIT/DONE for reorder, inline rename, action bar. Persistence-via-callback pattern. Add/duplicate/delete buttons functional.

4. **Stage 4 — Playback.** `PlaybackController` (Timer-driven). Play/pause and FPS picker in the strip. Tools and frame/layer ops disabled while playing. FPS persisted in V2 codec (already in stage 1).

5. **Stage 5 — Onion skinning.** Toggle in strip. Previous-frame ghost in `CanvasView` at fixed 30% opacity. Disabled during playback and on first frame.

6. **Stage 6 — Export.** `GIFExporter`, `APNGExporter`. Extend `ShareSheet` with new format options. Single-frame export via these formats works as a static one-frame GIF/APNG.

Each stage follows the workflow recipe from the layers handoff: per-task reviews (Sonnet) for verbatim work, separate spec + code reviews for judgment-heavy tasks, holistic Opus review (`superpowers:code-reviewer`) before tagging. Stage tag + `--no-ff` merge + push, in that order.

## Testing strategy

### Unit tests (mirror the source tree)

- `DrawBitTests/Drawing/FrameSequenceTests.swift` — `FrameSequence` mutators preserve invariants; layer-ops cascade across all frames; reorder math (analog of `Frame.modelTargetIndex`); 60-frame cap is a model-level guard, not just UI.
- `DrawBitTests/Drawing/FrameCodecV2Tests.swift` — V2 round-trip for 1-, 4-, 60-frame fixtures; V1→V2 read-fallback (a "DBFR" blob decodes as a one-frame sequence with default FPS); malformed/truncated inputs throw cleanly.
- `DrawBitTests/Persistence/AnimationPieceRepositoryTests.swift` — save/load multi-frame piece via in-memory `ModelContainer`; single-frame round-trip identical to today; `loadFrames` migrates a "DBFR" blob and saves back as "DBFS".
- `DrawBitTests/Rendering/SingleFrameNonRegressionTests.swift` — single-frame Piece exports byte-identical PNG to the Layers v2 export path, for every supported canvas size × export scale.
- `DrawBitTests/Rendering/GIFExporterTests.swift` and `APNGExporterTests.swift` — fixed 4-frame fixture; assert magic bytes (`GIF89a` / `‰PNG`), frame count via ImageIO probe, per-frame delays match `1.0 / fps`.
- `DrawBitTests/State/EditorStateAnimationTests.swift` — `setActiveFrame` auto-commits floating marquee; layer-pixels undo restores only the active layer in the active frame; frame-add undo removes the frame; frame-reorder undo restores order.

### UI tests (`DrawBitUITests`)

- `DrawBitUITests/AnimationFlowUITests.swift`:
  - Open piece → add 3 frames → draw on each → scrub between them → toggle onion skin → play → pause.
  - Persistence: close and reopen the piece (via gallery, the pattern Layers v2's review caught) → assert frame count, content, and active frame survive.
  - Layer ops cascade: add a layer → confirm it appears empty in every frame; draw on it in frame 2 → confirm it's still empty in frames 1 and 3.

### Manual device checklist (gate for merging each stage to main)

- Multi-frame Piece: scrub forwards and backwards. Onion skin lines up visually with the previous frame.
- Play a 12-frame loop at 12 fps. No flicker, no dropped frames at small canvas sizes.
- Export a 4-frame loop to GIF. Open in QuickTime / Safari / Photos. Confirm playback and frame count.
- Export same to APNG. Open in Safari. Confirm playback.
- Delete a frame mid-marquee drag. Cancels cleanly, no crash.
- Force-quit during playback. Reopen. Active frame and FPS persist; playback is paused on reopen.
- Open a pre-animation piece (built with Layers v2 binary). It loads as a one-frame piece. Save back. Reopen. Still one-frame, but now in V2 format.

## Risks and mitigations

1. **Memory pressure from sequence-level undo snapshots.** *Mitigation:* in Stage 2, sketch sequence undo with full snapshots; profile at the cap (60 frames × 16 layers × 256×256 = 240 MB per snapshot). If this is unworkable (it likely is), implement a delta-encoded `UndoEntry` cases (e.g., `.frameInserted(at:frame:)`, `.layerInsertedAcross(layerID:at:)`). The risk is real and the spec calls it out so the implementer doesn't ship a memory bomb.

2. **Storage at the cap (256×256 × 16 layers × 60 frames = 240 MB per Piece).** *Mitigation:* `@Attribute(.externalStorage)` already keeps the blob out of the main store row. If real-world usage produces multi-hundred-megabyte Pieces, follow up with size-aware caps (smaller canvas → more frames allowed) or per-layer content-hash dedup across frames. The cap is generous for typical pixel-art animations (4–24 frames); few users will approach it.

3. **Compositor performance during playback at high FPS and high layer count.** *Mitigation:* at 60 fps × 16 layers × 256×256 = 256 MB/s of `Data` byte-walk, well within iPad memory bandwidth. If frames are dropped, cache composited buffers per frame (keyed by frame UUID + dirty bit) and invalidate on edit. Defer caching until profiling demands it.

4. **Onion-skin redraw cost at 256×256 × 16 layers.** *Mitigation:* recompute on every draw is fine at small canvas sizes. If sluggish at 256×256, cache the ghost composite by `(frameID, layers-hash)`. Only cache invalidates when the user is drawing on the previous frame — rare during normal authoring.

5. **GIF color-palette quality on pixel art.** *Mitigation:* GIF is a 256-color palettized format; pixel art at small sizes typically uses far fewer than 256 colors and converts cleanly. ImageIO chooses a palette automatically. APNG (full color) is the recommended export for art that uses more than 256 colors.

6. **"Looks fine in simulator, broken on device" rendering glitches.** *Mitigation:* (a) the rendering invariant carries over from Layers v2, (b) every existing fidelity test continues to run, (c) Stage 1's single-frame non-regression test forces visual byte-identity, (d) manual on-device check is mandatory before each stage merges.

7. **Marquee × frame-switch races.** *Mitigation:* every frame-mutating operation auto-commits any floating marquee first, mirroring the Layers v2 pattern that already proved itself.

8. **Layers-v2 SwiftData `SchemaMigrationPlan` still outstanding.** *Mitigation:* not blocked by animation. Animation's blob-format change does not require a SwiftData schema change. The two migrations are independent. The Layers v2 migration remains a TestFlight prereq tracked in the layers handoff; this spec inherits that prereq but does not solve it.

## Open questions

None. All decisions captured above.
