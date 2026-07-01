# DrawBit — Time-lapse / Process Replay (design spec)

**Date:** 2026-07-01
**Status:** approved-in-brainstorm (founder said "go"; taste calls delegated — see § Decisions)
**Supersedes:** the time-lapse notes in `docs/superpowers/handoffs/2026-06-28-*` and `2026-06-29-*`.

## Goal

Every drawing quietly records its own making, and the export sheet can turn that
recording into a short, shareable **MP4 time-lapse** — "watch it paint itself."
This is the standout delight/virality play from the pre-launch audit: each clip
advertises the app. It must feel like the rest of DrawBit: calm, crisp, zero
friction (no "start recording" button to remember).

## Decisions (settled in brainstorm)

Four forks the founder chose:

1. **Experience:** export + preview in the existing share sheet. No dedicated
   in-editor playback screen. The share sheet's preview player shows the clip
   before you share.
2. **Capture:** snapshot the canvas **after each committed action**, then tidy to
   an even, capped clip at build time. Not a timer; not raw-per-stroke playback.
3. **Persistence:** the recording is **saved with the drawing** (survives close /
   reopen, accumulates across sessions).
4. **Format:** a real **MP4 video** (new AVFoundation exporter), not GIF/APNG.

Taste calls delegated to Claude (all reversible, each a single constant — the
founder can flip any on review):

- **Matte** (video has no transparency, so see-through pixels need a solid
  backdrop): **dark `RGBA(26,26,26,255)`** ≈ the app's `Color(white: 0.10)`. The
  clip then looks exactly like drawing in DrawBit and colors pop. Constant:
  `MP4Exporter.defaultMatte`.
- **Export tile label:** **`FILM`** (short, fits the pixel-font grid; reads as
  video). Constant: `ShareSheet.ExportFormat.film.label`.
- **Pacing:** sample to **≤120** snapshots, **24 fps**, hold the final art
  **1.2 s** → a snappy ~5 s clip. Constants: `Timelapse.targetClipFrames`,
  `Timelapse.clipFPS`, `MP4Exporter` hold parameter.
- **Recording is always on**, no per-piece toggle (YAGNI). Stored zlib-compressed
  (lossless — crisp), capped so the footprint stays ~1–2 MB.

## Architecture & components

Respects the one-way layer dependencies (`UI → State → Persistence →
Rendering/Drawing → Models`). New parts, by layer:

| Component | Layer | Purpose |
|---|---|---|
| `Timelapse` (namespace) | Drawing (pure) | Home for the shared constants (`maxStoredKeyframes`, `targetClipFrames`, `clipFPS`) + `sample([blob], to:)` even-downsample helper used by preview & export. |
| `TimelapseRecording` | Drawing (pure) | The growing list of compressed keyframes + append/dedupe/thinning rules (thinning reads `Timelapse.maxStoredKeyframes`). No UI/SwiftData. |
| `KeyframeCodec` | Drawing (pure) | `compress(rgba) → blob` / `decompress(blob) → rgba?` via zlib (lossless). |
| `TimelapseCodec` | Drawing (pure) | Encode `[blob] ↔ Data` container for storage (mirrors `FrameCodec`'s binary style). |
| capture hook | State (`EditorState`) | `recordKeyframe()` composites the active frame, compresses, appends. Called from the existing commit methods. |
| `MP4Exporter` | Rendering (pure*) | `[rgba] + size + scale + fps + matte + hold → .mp4` via AVFoundation. |
| `Piece.timelapseData` | Models | New optional `Data` (external storage). Additive → lightweight migration. |
| `PieceRepository.saveTimelapse` | Persistence | The only SwiftData seam for the new column. |
| export wiring | UI (`ShareSheet`, `ExportPreview`, `ExportSizeBudget`) | `FILM` format tile, preview of the recording, budget case. |

\* `MP4Exporter` adds **AVFoundation / CoreVideo / CoreMedia** to the Rendering
layer's allowed imports. Still pure (no UIKit/SwiftUI/SwiftData) and unit-testable
by writing a temp movie and re-reading it with `AVAsset`. `CLAUDE.md`'s
"pure-logic imports" note gets amended to list these for `MP4Exporter` only.

## Capture model (the recorder)

**`TimelapseRecording`** (value type):

- Holds `private(set) var frames: [Data]` — each a **zlib-compressed composited
  RGBA canvas** (alpha 0/255, native resolution).
- `mutating func append(_ blob: Data)`:
  - **Dedupe:** if `blob == frames.last`, do nothing (a step that didn't change
    the picture adds no frame; identical canvas → identical compressed bytes).
  - **Append**, then **thin if full:** when `frames.count > maxStoredKeyframes`
    (240), keep every other frame (`stride(from: 0, by: 2)`), halving the list.
    Each halving doubles the time each surviving frame represents, so coverage
    stays even across the *whole* session. Net: a small drawing keeps every step
    (full fidelity); an epic one coarsens gracefully instead of exploding.
  - Memory: 240 × ~5 KB avg ≈ ~1.2 MB; worst-case busy 256² frames ≈ a few MB.

**Capture points** live in `EditorState`, at the end of the three existing commit
methods so every call site records for free (DRY — no hunting view call sites):

- `commitStroke()` — pencil/eraser/fill/line/color-swap, and marquee
  commit/duplicate/delete (which route through `commitStroke`).
- `commitStructuralChange()` — layer add/delete/reorder/visibility/rename.
- `commitSequenceChange()` — frame add/delete/reorder.

Each calls `recordKeyframe()`:

```
private func recordKeyframe() {
    let buffer = Compositor.composite(frame, size: size)   // active frame, "what you saw"
    if let blob = KeyframeCodec.compress(buffer.data) {
        timelapse.append(blob)
    }
}
```

**Undo/redo:** *not* recorded — the replay always moves forward. `undo()`/`redo()`
change the canvas but don't append. To guarantee the clip ends on the real final
art (in case the user's last action was an undo), `recordFinalKeyframeIfNeeded()`
appends the current composite on close/share if it differs from `frames.last`.

**Multi-frame animation pieces:** v1 records the **active frame's** composite as it
evolves — perfect for the common single-frame drawing; for a multi-frame animation
it captures whichever frame is being worked on (a fuller multi-frame process replay
is out of scope). Documented as a known simplification.

## Storage & persistence

**`KeyframeCodec`** (zlib, lossless):

```
static func compress(_ rgba: Data) -> Data?      // (rgba as NSData).compressed(using: .zlib)
static func decompress(_ blob: Data) -> Data?    // inverse; nil on corrupt input
```

**`TimelapseCodec`** — container, big-endian, mirrors `FrameCodec`:

```
4  bytes  ASCII "DBTL" magic
1  byte   version (1)
4  bytes  frame count (UInt32)
per frame:
  4 bytes  blob byte length (UInt32)
  N bytes  zlib-compressed RGBA blob
```

`encode(_ frames: [Data]) -> Data`, `decode(_ Data) -> [Data]?` (nil on bad
magic/truncation — treated as "no recording," never a crash).

**`Piece.timelapseData: Data?`** — new `@Attribute(.externalStorage)`, default
`nil`. Additive optional column → **inferred lightweight migration** (identical to
how `referenceImageData` was added). **Do NOT** add a second live `VersionedSchema`
(the duplicate-checksum launch-crash invariant). A pre-field store must open
cleanly — covered by a migration test mirroring `ReferenceUpgradeMigrationTests`.

**`PieceRepository`** (the only SwiftData seam):

```
func saveTimelapse(piece: Piece, blob: Data?) throws {
    piece.timelapseData = blob
    piece.updatedAt = Date()
    try context.save()
}
```

Loading needs no repo method — `EditorView.init` reads `piece.timelapseData`
directly (a property access, same as `setReference(imageData:)` reads
`referenceImageData`) and calls `state.loadTimelapse(_:)`.

`duplicate(piece:)` also copies `timelapseData` (like it copies
`referenceImageData`).

**`EditorState`** persistence API:

```
func loadTimelapse(_ blob: Data?)      // TimelapseCodec.decode → recording
func encodedTimelapse() -> Data?       // TimelapseCodec.encode(recording.frames); nil if empty
func recordFinalKeyframeIfNeeded()     // append current composite if != last
var timelapseFrameCount: Int           // recording.frames.count (for UI gating)
```

**When we persist** (avoids a big blob write on every stroke):

- **On close** (`EditorView.onDisappear`): `recordFinalKeyframeIfNeeded()` →
  `saveTimelapse(blob: state.encodedTimelapse())`. Guarded by `!loadFailed`
  (never persist over a corrupt-but-recoverable original).
- **On opening the share sheet:** same finalize + save, so the sheet (which
  re-reads `piece.timelapseData`) sees the current session's steps.

Force-quit mid-session loses only that session's *un-persisted process growth* —
the drawing itself is saved every stroke as today. Acceptable for v1; noted.

## MP4 export

**`MP4Exporter`** (`DrawBit/Rendering/`):

```
static func export(
    keyframes: [Data],        // decompressed RGBA canvases, in order
    size: CanvasSize,
    scale: Int,
    fps: Int,
    matte: RGBA = defaultMatte,
    holdLastSeconds: Double = 1.2,
    to url: URL
) throws
```

- **Pipeline:** `AVAssetWriter` (`.mp4`) + `AVAssetWriterInput`
  (`AVVideoCodecTypeH264`) + `AVAssetWriterInputPixelBufferAdaptor`. For each
  keyframe: fill a `CVPixelBuffer`-backed `CGContext` with the **opaque matte**,
  then `ctx.draw` the keyframe's `CGImage` (built via `bufferToCGImage`, sRGB,
  premultipliedLast) with `interpolationQuality = .none` +
  `setShouldAntialias(false)` — nearest-neighbor crisp scaling. Append at
  presentation time `i / fps`. Duplicate the final frame for `holdLastSeconds`
  worth of frames so the finished art lingers.
- **Output dimensions:** `size.width*scale × size.height*scale`, each **rounded up
  to even** (H.264 requires even dimensions). Any pad is matte-filled on the
  right/bottom. Nearest-neighbor means each source pixel is an exact `scale×scale`
  block.
- **Color/invariants:** sRGB color space (never deviceRGB); nearest-neighbor;
  matte is fully opaque so the video has no alpha. Consistent with every other
  export path.
- **Cancellation:** `try Task.checkCancellation()` between frames (matches
  GIF/APNG exporters).
- **Guards:** `keyframes` non-empty, `scale ≥ 1`, `fps ≥ 1`; throws on writer
  failure. Writes directly to `url` (video naturally goes to a file; the share
  sheet already shares a temp URL).

## Export-sheet UX

- **New format:** add `case film` to `ShareSheet.ExportFormat`
  (`label "FILM"`, `fileExtension "mp4"`, `budgetKind .film`). It becomes the 5th
  tile in the FORMAT grid (grid `columns` 4 → 5). Conceptually it exports the
  *process* rather than the current frames, but users read "I want the film of
  it" naturally; keeping it in the same grid avoids extra UI for a cheap win.
- **Loading:** on appear, alongside `loadFramesIfNeeded`, decode the recording:
  `Timelapse.sample(TimelapseCodec.decode(piece.timelapseData) ?? [], to: 120)`
  → decompress → hold as `filmRGBA: [Data]` (sampled, ready for preview/export).
- **Preview:** when `.film` selected, `ExportPreview` plays `filmRGBA` looped at
  `clipFPS`. Each RGBA canvas is wrapped as a one-layer `Frame` so the existing
  `FrameThumbnailRenderer` + looped `TimelineView` path renders it unchanged;
  `.film` joins `.gif/.apng` in `isAnimated`; badge reads `FILM · X.Xs`.
- **Size / budget:** the scale ladder still applies. Add `case film` to
  `ExportSizeBudget.Format`; MP4 is efficient, so budget is bounded by
  `maxContextEdge` only (no per-frame RGBA accumulation cap like GIF/APNG — the
  writer streams frame-by-frame).
- **Too-few-steps state:** if `filmRGBA.count < 2` (no motion), the FILM tile is
  **disabled** with a `KEEP DRAWING` sublabel (mirrors the existing `TOO BIG`
  treatment on scale tiles). A brand-new draw with a couple strokes still films.
- **Export:** `.film` branch in `share()` calls
  `MP4Exporter.export(keyframes: filmRGBA, size:, scale:, fps: clipFPS, to: url)`
  then shares the `.mp4` via the existing `UIActivityViewController` path.

## Edge cases & error handling

- **No recording / empty:** `decode` → `[]`; FILM tile disabled; nothing crashes.
- **Corrupt `timelapseData`:** `TimelapseCodec.decode` returns `nil` → treated as
  no recording (FILM disabled). The drawing itself is unaffected.
- **`loadFailed` piece:** all timelapse saves are gated by the same `!loadFailed`
  guard as `saveCurrentFrame` — a corrupt piece never gets a timelapse written
  over it, and its editor is the error view anyway.
- **Odd canvas dimensions:** even-padding in `MP4Exporter` (matte fill) keeps
  H.264 happy without shifting the art.
- **Over-budget scale:** the FILM tile obeys the same disable-tile /
  snap-scale-down machinery as other formats via `ExportSizeBudget`.
- **Dark-on-dark art:** documented consequence of the dark matte — a
  near-black sprite on the near-black matte reads as "empty." The matte is one
  constant to change if the founder prefers white/neutral on review.

## Testing plan

Unit (pure, fast) — mirror the source tree:

- `TimelapseRecordingTests`: append adds a frame; identical blob deduped; count
  never exceeds `Timelapse.maxStoredKeyframes`; thinning keeps first & last and
  halves evenly.
- `TimelapseSampleTests`: `Timelapse.sample(_, to:)` returns ≤ target with even
  spacing and preserves the first & last frames; passthrough when already ≤ target.
- `KeyframeCodecTests`: compress→decompress round-trips an RGBA buffer exactly
  (lossless); decompress(garbage) → nil.
- `TimelapseCodecTests`: encode→decode preserves the blob list; empty list;
  bad-magic/truncated → nil.
- `MP4ExporterTests`: N keyframes → a non-empty `.mp4` at `url`; `AVAsset`
  duration ≈ `(N-1)/fps + hold` (tolerance); video track natural size == even
  output dims; a transparent-corner pixel of frame 0 decodes to the matte;
  `scale<1`/`fps<1`/empty guards; cancellation throws.
- `EditorState` capture: `commitStroke` grows the recording; a no-op stroke is
  deduped; `undo` does not append; `recordFinalKeyframeIfNeeded` appends only
  when the canvas differs; `encodedTimelapse`/`loadTimelapse` round-trip.
- `PieceRepositoryTests`: `saveTimelapse` then reload sees the blob;
  `duplicate` copies it (in-memory container).
- `TimelapseUpgradeMigrationTests`: a pre-`timelapseData` store opens cleanly
  (mirror `ReferenceUpgradeMigrationTests`).
- `ExportSizeBudgetTests`: `.film` bounded by `maxContextEdge`, not the animated
  byte cap.

UI (light — keep the suite fast/stable):

- `FILM` tile appears in the FORMAT grid; disabled with `KEEP DRAWING` on a
  fresh (unrecorded) draw, enabled after drawing. (Export fires a system share
  sheet — not asserted; logic is covered by unit tests. No new `.repeatForever`
  animation; nothing to gate under `UITestSupport`.)

## Non-goals (v1)

- No in-editor playback/scrub screen (export-preview only).
- No GIF/APNG time-lapse (MP4 only, by choice).
- No audio track under the video (DrawBit FM over the clip is a tempting follow-up).
- No multi-frame "animate every frame's process" replay.
- No per-piece record on/off toggle or global setting (add later only if storage
  telemetry says users want it).

## Invariants touched / CLAUDE.md updates

- Amend the **pure-logic imports** rule: `MP4Exporter` may import AVFoundation /
  CoreVideo / CoreMedia (still no UIKit/SwiftUI/SwiftData; still unit-tested).
- Reaffirm the **single-live-schema** rule: `timelapseData` is additive/optional
  and rides lightweight migration — no `DrawBitSchemaV2`.
- The reference-photo rule is untouched: the recording snapshots the **composited
  layers only** (`Compositor.composite`), never the display-only reference photo,
  so the tracing backdrop still never enters an export.
- Regenerate `DrawBit.xcodeproj` after adding the new `.swift` files; clear
  DerivedData after the regen that first adds a new **app-target** file (per the
  handoff gotcha) before running the test target.
