# Handoff — Intro audio, gallery redesign, custom canvas sizes (2026-06-22)

Post-v1 UI/feature session. **Everything is on `origin/main`** (HEAD `1367cef`); the old
`intro-music` branch was fast-forward-merged in and can be deleted. Build/test/run commands and the
load-bearing invariants live in `CLAUDE.md`.

**Up next (next session): update the in-app Help section** — see the last part of this doc.

## State of the repo
- Branch `main`, in sync with `origin/main`, HEAD `1367cef`.
- Full suite was **green at `e8a75de`** (33 UI + all unit). The final commit `1367cef` is a
  visual-only `Canvas` constant tweak (no test touches the preview) — build-verified, not re-run.
- **Untracked root files** still deliberately left out of git: `alt_logo.PNG`, `dbit.png`, `share.PNG`
  (unused source originals). **Never `git add -A`** — it sweeps them in.
- No tags added this session.

## What shipped (5 commits, oldest → newest)

### `15f5155` — frame controls simplified + gallery menu themed
- Animation frame strip: **removed per-frame Rename** (field, name overlay, `FrameSequence.setName`,
  `EditorView.renameFrame`). Duplicate + Delete are now **on-frame glyphs on the selected frame**
  (`FrameRow.actionBadges`/`badgeButton`): `⧉` duplicate (always), `×` delete (hidden on the last
  frame). The native `.contextMenu` is gone.
- Gallery piece menu was briefly themed (popover → square sheet) here — but it was **fully replaced
  later** (see `bbd25cb`), so ignore that intermediate step.
- Gotcha learned: a themed long-press popover **cannot coexist with `.draggable`** (the drag-lift
  recognizer eats the long press) — that's why frame actions became on-tile glyphs, not a menu.

### `f3f92a2` — intro music + slower launch/gallery beats
- **`IntroAudio` singleton** (`DrawBit/State/IntroAudio.swift`): plays `dbfm7.mp3` **once** on PRESS
  START (real launch path only; `RootView.start()` skips it under UI test). Uses an **`.ambient`**
  session so it **respects the silent switch**. Stops when DrawBit FM starts
  (`RadioController.ensureSessionActive`) and when a piece opens (`EditorView.onAppear`) so the ~17s
  clip never overlaps the radio or bleeds into the canvas.
- **Bundling gotcha:** xcodegen flattens resources to the bundle root, and `BundledTracks.load()`
  scans every root-level `.mp3` for the FM playlist — so `dbfm7.mp3` would have become a phantom
  station. Fixed with `BundledTracks.isStationFile` (numeric-prefix = station; intro excluded).
- Timing: gallery element build slowed (`GalleryView.runIntro` `gap` 0.22 → **0.595**, ~+1.5s) and the
  launch beats slowed ~1.5× (`LaunchSequenceView` `dissolveOut`/`dissolveIn` 0.5→0.75, `logoHold`
  0.4→0.6) to sit with the music. **Perceptual — verify by ear on a real launch.**

### `bbd25cb` — gallery on-tile actions + custom square canvas sizes
- **Gallery pieces:** tap = open (unchanged); **long-press reveals Duplicate + Delete glyphs** on the
  tile (`PieceCell`, mirroring the frame pattern). **Rename dropped entirely** — removed
  `RenamePieceSheet.swift` and the unused `PieceRepository.rename`. (Export filenames now always use
  `piece.effectiveName`'s default — accepted, names weren't shown anywhere.)
- **Custom square sizes:** `CanvasSize` went **enum → struct** with an arbitrary `dimension` clamped to
  **8–256**. Preset names (`s15…s128`) kept as static constants (so ~238 `.sNN` test refs still
  compile); the **odd presets (15/31/63) dropped from the picker** — `presets = [s16,s32,s64,s128]`.
  **No schema migration** (`Piece.sizeRaw` was already an `Int`). `ShareSheet` export scales now
  computed (`k = 128/dimension → k·{1,2,4,8,16}`), reproducing every kept preset exactly.

### `e8a75de` — New Piece sheet redesigned as a unified size dial
- Replaced the preset-row list with a **unified control** (`NewPieceSheet.swift`): live preview square,
  big editable number with `−`/`+` steppers and **tap-to-type**, a custom on-brand **`PixelSlider`**
  (8–256; hand-built, no native `Slider`), preset chips (16/32/64/128) that **create on one tap** (kept
  `NewPiece-<n>` ids → the rest of the suite is unchanged), and one **CREATE** for the dialed size.
- The "presets create on tap, custom dial has its own CREATE" split was a deliberate call to avoid
  rewriting ~15 piece-creating UI tests. If a future pref is "everything routes through one CREATE,"
  that's the follow-up that churns the suite.

### `1367cef` — New Piece preview: real pixels, then grows
- `CanvasPreview` is now a **hybrid**: at low sizes it draws the **actual pixels** (8×8 = 8 countable
  cells) and densifies as N rises; once cells hit a ~3pt floor the grain plateaus
  (`count = min(dimension, side/3)`) while the **square keeps growing** (sqrt-mapped) toward filling the
  frame near 256. `e8a75de` is the clean revert point if this feel is wrong.

## Specs touched / still TODO
- `docs/superpowers/specs/2026-05-05-animation-design.md` updated for the frame-menu change.
- **Not updated:** any spec for the gallery on-tile actions or the custom-size / New Piece dial — worth
  a short spec note if the next session has time.

## Manual-verification debts (perceptual, not test-covered)
Run on the **Simulator with a real launch (no `-UITest` args)** and judge by feel:
- Intro music plays once on START; stops when FM starts / a piece opens; silent ringer = no intro.
- Launch beats + gallery build timing sit well with the ~17s track.
- New Piece: `PixelSlider` drag feel, the keyboard-up layout when tapping the number, and the hybrid
  preview's grain across 8→256.

## NEXT UP — update the in-app Help section

The Help content is **stale** after this session. File: `DrawBit/Views/Gallery/HelpScreen.swift`
(UI tests: `DrawBitUITests/HelpScreenUITests.swift`). Layout = a **2-column grid of 6 icon+title
tiles**; tapping a tile expands it to full-row instruction text (custom pixel-dissolve transition,
Press Start 2P titles / `Font.pixelBody` body). Design notes in
`docs/superpowers/handoffs/2026-06-18-help-page-redesign.md`.

Current topics + bodies (so you can edit in place / decide whether to add a topic):
- **TOOLS** — "Pencil, eraser, fill, swap, pick, laso … Mirror toggles symmetry, reflecting every
  stroke across the vertical centre." (Mirror still true; consider noting **odd sizes have a true
  centre pixel** now that custom sizes exist.)
- **CANVAS** — "Pinch to zoom, two-finger drag to pan or rotate. Pixels never move …" *Silent on
  creating a piece / picking a size.*
- **LAYERS** — add/hide/lock + drag to reorder.
- **ANIMATION** — frames strip, onion skin, FPS, Play. **Stale:** says nothing about
  **duplicate/delete a frame** (now the on-frame `⧉` / `×` glyphs on the selected frame), and per-frame
  **rename no longer exists**.
- **EXPORT** — PNG/GIF/APNG/Sprite + scale.
- **DRAWBIT FM** — radio tile bottom-right.

**Stale gaps to address (what changed this session):**
1. **New Piece / sizes** — there's now a size **dial**: type a number, `−/+`, slider, or tap a preset
   chip; **any square 8–256** is allowed (not just presets). No help mentions sizing at all.
2. **Gallery pieces** — tap to open, **long-press a tile** to reveal **Duplicate / Delete** glyphs.
   **Rename was removed.**
3. **Animation frames** — **Duplicate / Delete** are the on-frame glyphs on the selected frame;
   **rename removed**.
4. (Optional) **Intro music** is new but probably doesn't need a help entry.

Decide whether to fold these into existing tiles (e.g. expand CANVAS to cover "new piece + sizes", add
gallery gestures somewhere) or add a new tile (the grid is currently 6 = 3 rows of 2; a 7th breaks the
even grid — either go to 8 or rework the layout). Match the existing tile/transition pattern and keep
`Help.section.*` accessibility ids stable for `HelpScreenUITests`.

## Pointers
- Process: brainstorm → spec (`docs/superpowers/specs/`) → plan → TDD → handoff. Governing UI
  constraint remains **legibility / "never a bottleneck of choices."**
- Regenerate the Xcode project after adding/moving `.swift` files:
  `rm -rf DrawBit.xcodeproj && xcodegen generate` (`.xcodeproj` is gitignored).
- Related memory: [[project_drawbit_fm]], [[project_palettes]], [[project_share_sheet]],
  [[project_animation_strip_redesign]], [[project_pricing]] (custom sizes / audio are price-bump
  territory).
