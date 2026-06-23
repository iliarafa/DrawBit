# Handoff — New Draw sheet redesign (2026-06-23)

**Next task: finish polishing the New Draw sheet** (the size picker). It's functionally done and running
on the simulator, but it went through many iterations and the final feel is perceptual — needs a device
eyeball + small tuning. Details at the bottom.

## State of the repo — all committed & pushed
- Branch `main`, in sync with `origin/main`, HEAD `53424f5`. Everything below is shipped.
- This session's commits (on top of last session's `68a684e`):
  - `6d5c2b3` chore: raise deployment target to iOS 18
  - `2ddba54` feat(gallery): redesign New Draw sheet (minimal hero)
  - `c26cb33` feat(export): branded export filename
  - `53424f5` docs: this handoff
- Working tree clean except the usual untracked root images — **leave alone / never `git add -A`**:
  `alt_logo.PNG`, `dbit.png`, `share.PNG`.
- Tests: full suite **green** (320 unit + 33 UI) as of the iOS 18 bump; the later string/label edits
  (CREATE→plain, NEW PIECE→NEW DRAW, `drawbit-…` filename) are build-verified with no test impact.
  `GalleryMenuUITests` (5) cover the sheet's ids and pass.

## 🚨 How the user wants you to work (learned the hard way this session)
This session had a lot of back-and-forth on the sheet. Internalize this:
- **Copy the agreed mockup *religiously*. Do NOT improvise.** When the user approves a visual, match it
  exactly — corners, fonts, alignment, spacing. Deviations (I rounded corners, swapped a slider font,
  centered a title) caused real frustration.
- **No rounded corners.** Square boxes everywhere (steppers, chips, CREATE, CANCEL) — plain
  `Rectangle().stroke(...)`, not `RoundedRectangle`. (The one historical pill was removed.)
- **"This is not the time to make decisions."** Make the change asked; don't add unrequested flourishes.
- Plain-spoken design talk, not framework jargon ([[feedback_explanations]]).
- Governing UI constraint stays **legibility / "never a bottleneck of choices."**

## What the New Draw sheet IS now (design B — "minimal hero")
`NewPieceSheet.swift`, a centred vertical stack, dark `Color(white:0.10)`, Press Start 2P (`.pixel`),
VT323 (`.pixelBody`) for the slider end-labels, `Color.toolSelected` (#0099CC) the only accent, **all
square corners**:
1. **Header** — `NEW DRAW` (left) + `CANCEL` (right), `HStack` with `Spacer()`.
2. **Preview** — 96pt `CanvasPreview`: a pixel-grid square that *grows with the size* and shows real
   pixels at low res, plateauing to a fine grain (`count = min(dimension, side/3pt)`).
3. **Number row** — big `.pixel(34)` editable field (tap-to-type, numberPad) flanked by `−`/`+`
   steppers. The +/− are **drawn as pixel bars** (ZStack of `Rectangle`s), NOT font glyphs — Press Start
   2P's minus glyph sits low and misaligned, so don't revert to text.
4. **Slider** — custom `PixelSlider` (square track/fill/thumb, drag gesture), 8–256, VT323 end labels.
5. **Preset chips** — 16 / 32 / 64 / 128, square, tap = create instantly (ids `NewPiece-<n>`, kept so
   the wider suite's piece-creation stays green); the one matching `dim` lights blue.
6. **CREATE** — plain `CREATE`, full width (id `NewPiece-create`).

**Layout/margins:** content is `.frame(width: 320).padding(20)` (no full-bleed bg, no asymmetric
padding). The sheet uses **`.presentationSizing(.fitted)`** (GalleryView) so it **auto-hugs the content
with an equal ~20pt margin on all four sides** — this is why the iOS bump happened (below).

## Decisions locked this session (don't re-litigate)
- **iOS deployment target bumped 17 → 18** (`project.yml`) so `.presentationSizing(.fitted)` is
  available. Deliberate: app is pre-release, iPad-only, iOS 18 near-universal. Whole-app change.
- **Square custom sizes** stay (prior session): `CanvasSize` is a struct, dimension clamped **8–256**,
  presets 16/32/64/128.
- **No piece names** — thumbnail is the identity; rename was removed; the New Draw sheet has no name
  field (user confirmed). `Piece.effectiveName` still exists only for the share-sheet's displayed title.
- **Export filename** is `drawbit-<dimension>-<scale>x.<ext>` (e.g. `drawbit-64-3x.png`) — branded, no
  user names. `ShareSheet.swift`.
- Chosen layout = **variation "1 / minimal hero"** (calm, slider kept). Variations 2 (size tiles) and 3
  (pixel keypad) were shown and rejected.

## Polishing the New Draw sheet (the next task)
Functionally complete; the remaining work is **perceptual — open it on the simulator and judge**:
- Confirm the fitted sheet reads with an even ~20pt gap on all four sides (the whole reason for the
  iOS 18 bump). If it still feels off, tune the `.padding(20)` / `.frame(width: 320)` in `NewPieceSheet`.
- Proportions: number size (`.pixel(34)`), preview 96pt, stepper 44pt, chip padding, inter-element
  spacing (20) — nudge by eye if the rhythm feels heavy/light. **Don't change the distribution without
  being asked.**
- Slider drag feel + thumb size (14pt); the preview grain across 8→256; the keyboard-up layout when the
  number field is tapped (fitted sheet + keyboard).
- App is already rebuilt and installed on the booted sim (`com.iamilias.drawbit`, iPad Pro 13" M5).
  To refresh after edits: `xcodebuild … build` then `xcrun simctl install booted <DrawBit.app>` +
  `xcrun simctl launch booted com.iamilias.drawbit` (clean up any `build/` dir you create).

## Pointers
- Regenerate the Xcode project after adding/moving `.swift` files or changing `project.yml`:
  `rm -rf DrawBit.xcodeproj && xcodegen generate` (`.xcodeproj` is gitignored).
- Build/test/run commands + invariants: `CLAUDE.md`. The previous session's broader context:
  `docs/superpowers/handoffs/2026-06-22-intro-audio-gallery-redesign.md`.
- Still queued from the last handoff: **update the in-app Help** (stale on sizing/gallery actions/frame
  glyphs) — after the New Draw polish.
