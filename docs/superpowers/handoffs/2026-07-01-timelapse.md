# Handoff — 2026-07-01 (time-lapse / process replay — FILM export shipped)

Built on branch **`timelapse`** (off `main` tip `9a25118`). **Not yet merged / not pushed** —
waiting on the founder to review on wake (they said "go go go, wake me up when you are done").
14 commits: 2 docs (spec, plan) + 11 feature + 1 docs(CLAUDE.md). Working tree clean apart from
the three pre-existing untracked marketing PNGs at repo root.

**Verified green:** 443 unit + 36 UI = **479 tests, 0 failures**; simulator build + device
Release compile-check (`CODE_SIGNING_ALLOWED=NO`, `generic/platform=iOS`) both **BUILD SUCCEEDED**
(confirms AVFoundation links for device).

## What shipped

Every drawing now records its own making, and the export sheet turns it into a shareable **MP4
time-lapse**. No "start recording" button — it's automatic and calm.

- **Recording:** `EditorState.recordKeyframe()` fires at the three commit points
  (`commitStroke` / `commitStructuralChange` / `commitSequenceChange`) and stores a
  zlib-compressed `Compositor.composite` of the active frame (layers only — **never** the
  reference photo). Deduped + evenly halved to a cap (`TimelapseRecording`,
  `Timelapse.maxStoredKeyframes = 240`) → ~1–2 MB. Undo/redo don't record; `EditorView`
  finalizes with one more `recordKeyframe()` on close/share so the clip ends on the real canvas.
- **Persistence:** additive optional `Piece.timelapseData` column (external storage), encoded by
  `TimelapseCodec` ("DBTL"). Rides inferred lightweight migration — **no V2 schema**
  (`TimelapseUpgradeMigrationTests` proves a pre-field store upgrades clean). `duplicate` copies it.
  Saved on editor close and just before the share sheet opens (so the sheet sees this session).
- **Export:** `Rendering/MP4Exporter.swift` — H.264 via AVAssetWriter, sRGB + nearest-neighbor,
  opaque matte (MP4 has no alpha), final frame held. New **`FILM`** tile in the share sheet's
  FORMAT grid (now 5 wide); the preview plays the recorded process; disabled with **KEEP DRAWING**
  until ≥2 steps recorded.

## Taste calls I made (founder was asleep — all reversible, one constant each)

- **Matte = dark `RGBA(26,26,26,255)`** (≈ the app's `Color(white:0.10)`) → the clip looks like
  drawing in DrawBit. Flip in `MP4Exporter.defaultMatte`. *If you'd rather a white/neutral matte for
  light sprites, that's the one line.*
- **Label = `FILM`.** Change in `ShareSheet.ExportFormat.film.label` (+ the a11y id in
  `ShareSheetFilmUITests` if you rename the case).
- **Pacing:** ≤120 sampled frames, 24 fps, 1.2 s hold ≈ ~5 s clip. `Timelapse.targetClipFrames` /
  `Timelapse.clipFPS`, and the `holdLastSeconds` default on `MP4Exporter.export`.
- **Recording always on, no toggle** (YAGNI). If storage ever matters, add a global setting later.

## Known simplifications (documented, deliberate)

- **Multi-frame animations:** v1 records the *active frame's* canvas as it evolves — perfect for
  the common single-frame draw; for a multi-frame piece it captures whichever frame you're on. A
  fuller multi-frame process replay is out of scope.
- **Force-quit** mid-session loses only that session's *un-persisted process growth* (we persist on
  close + on share, not per stroke). The drawing itself is saved every stroke as before.
- **Dark-on-dark:** a near-black sprite on the near-black matte reads as "empty" in the clip —
  inherent to the matte choice, one constant away from changing.

## Verify it by hand (I couldn't run the live app / see the MP4)

Everything is unit- + UI-tested (including an end-to-end UI test: draw → record → FILM enables),
and `MP4ExporterTests` asserts a real `.mp4` decodes with the right size/duration/matte. But **I
never watched an actual exported clip play**. Worth a 60-second manual pass: open a draw, scribble,
SHARE → FILM → watch the preview loop, EXPORT, and confirm the saved `.mp4` looks right (crisp
pixels, dark matte, ends on the finished art) in Photos.

## Docs

- Spec: `docs/superpowers/specs/2026-07-01-timelapse-design.md`
- Plan: `docs/superpowers/plans/2026-07-01-timelapse-implementation.md`
- CLAUDE.md updated: MP4Exporter AVFoundation exception to the pure-logic rule + a time-lapse
  invariant bullet (composite-only, never the reference photo; additive column, no V2 schema).

## Next

- **Merge** once the founder is happy (branch `timelapse` → `main`). Then delete the branch.
- Possible follow-ups (not built): a DrawBit-FM audio bed under the clip; the "import reference as
  an editable layer" foundationed earlier; the cheap-polish batch (rename a draw, dithering,
  Copy-PNG, empty-gallery hint) from `project_audit_followups`.
