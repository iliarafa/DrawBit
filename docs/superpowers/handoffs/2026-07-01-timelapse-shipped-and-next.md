# Handoff — end of 2026-07-01 (time-lapse SHIPPED + what's next)

Supersedes `2026-07-01-timelapse.md` (the feature-build record — still worth reading for the deep
detail). `main` = `origin/main` = tip **`558fa65`** (pushed, in sync). Clean working tree **except**
the three untracked marketing PNGs at repo root (`alt_logo.PNG`, `dbit.png`, `share.PNG`) —
pre-existing, the founder's call whether to track them.

## Shipped this session (on origin/main)

- **Time-lapse / process replay — the FILM export.** Every draw silently records its own making;
  the share sheet exports a real **MP4** "watch it paint itself" clip. Founder watched a live clip —
  "works great." 13 commits, **479 tests green** (443 unit + 36 UI), simulator + device Release
  compile-check both pass.
  - **How it works:** `EditorState.recordKeyframe()` snapshots the composited **active frame only**
    (never the reference photo) at each commit; `TimelapseRecording` dedupes + evenly halves to a
    cap (`Timelapse.maxStoredKeyframes = 240`, ~1–2 MB); persists in the additive optional
    `Piece.timelapseData` column (lightweight migration, **no V2 schema**); exports via new
    `Rendering/MP4Exporter.swift` (AVFoundation H.264, opaque dark matte, nearest-neighbor sRGB,
    held final frame). New **FILM** tile is the 5th in the share FORMAT grid; disabled with
    "KEEP DRAWING" until ≥2 steps recorded.
  - **Taste calls (each one constant, reversible):** matte `RGBA(26,26,26)` = `MP4Exporter.defaultMatte`;
    label `FILM`; ≤120 frames / 24 fps / 1.2 s hold (`Timelapse.targetClipFrames` / `.clipFPS` +
    `MP4Exporter.export`'s `holdLastSeconds`). Recording is always-on, no toggle.
  - Spec: `docs/superpowers/specs/2026-07-01-timelapse-design.md`. Plan:
    `docs/superpowers/plans/2026-07-01-timelapse-implementation.md`. Memory: `project_timelapse`.

## Still next (the queue)

- **Cheap polish batch (S)** — still the highest-value low-effort cluster (from `project_audit_followups`):
  **rename a draw** (`Piece.name` exists, no UI sets it — the founder settled that the user-facing
  noun is "draw"; see `project_terminology_draw`), **dithering + a color-ramp generator** (the craft
  depth that justifies a price bump), **Copy-PNG to clipboard** (no `UIPasteboard` use anywhere yet),
  **empty-gallery hint**.
- **Time-lapse follow-ups (only if the founder wants them):** a **DrawBit-FM audio bed** under the
  exported clip (MP4 can carry audio — `RadioController`/bundled tracks already exist); **multi-frame
  process replay** (v1 records only the active frame — a known, documented simplification);
  optionally a **share-flow-hint** so users discover FILM.
- **Reference → editable layer (optional, foundationed):** `ReferenceSampler` already produces the
  exact canvas-grid RGBA a `Layer` needs; committing it (alpha 0/255, `Frame.addLayer` +
  structural-undo) is the remaining work. Only if the founder wants editable photo→pixels.
- **Deeper / post-traction:** multi-axis symmetry (only a fixed vertical centerline today);
  iCloud/CloudKit backup (delete-app = total loss — but L effort + collides with the single-live-schema
  rule); canvas resize/crop; async save + thumbnail cache before raising the 16-layer / 256px caps;
  **PaletteExtractor non-square bug** (scans `width × width`, drops bottom rows on 9:16 — 2-line fix).
- **Dropped — do NOT re-propose:** PNG import, rectangle tool (both declined by the founder 2026-06-29).

## Reusable gotchas (carry these)

- **New from time-lapse:**
  - `MP4Exporter` is the **one allowed AVFoundation/CoreVideo/CoreMedia import** in the pure Rendering
    layer (documented exception in CLAUDE.md). Everything else in Drawing/Rendering stays
    Foundation/CoreGraphics/ImageIO/UniformTypeIdentifiers only.
  - A top-left `CGImage` drawn into a `CGContext(data:)` → `CVPixelBuffer` is **already top-down —
    NO vertical flip** (would mirror it). Same rule as the eyedropper-reference work.
  - **H.264 needs even dimensions** — round output W/H up to even, matte-fill the pad.
  - `ExportPreview` cached its rendered images by `frames.count`; FILM feeds a **different** frame
    source, so it re-keys the render on `format#count` and no longer early-outs on non-empty images.
    If you add another export source, key it the same way.
- **Carried:**
  - **DerivedData:** after `rm -rf DrawBit.xcodeproj && xcodegen generate` adds a **new app-target**
    `.swift` file, also `rm -rf ~/Library/Developer/Xcode/DerivedData/DrawBit-*` or the test target
    fails `cannot find <Type> in scope`. New **test-target** files are picked up by regen alone.
  - **Single live SwiftData schema** — additive optional/defaulted fields ride inferred lightweight
    migration; never add a second `VersionedSchema` listing the live types (duplicate-checksum launch
    crash). Prove new columns with a pre-field-store migration test.
  - `DrawBit.xcodeproj` is gitignored (commits never include it). Test sim: `iPad Pro 13-inch (M5)`.

## Guiding star (from the founder)

A **calm, premium, single-player pixel app that feels like a beautiful machine** (built first to make
sprites for the game *All my Falling Stars*). Judge each item by "does it remove friction from joyful
making," not "does it tick a competitor's box." Several "next" items are **discuss-first** — settle the
shape with the founder before building. The founder prefers plain-language design talk over framework
jargon. Verify file/line refs before editing — they drift.
