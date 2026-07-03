# Handoff — 2026-07-03 (palette non-square fix + HELP copy refresh)

Session scope was set by the founder explicitly: **no new features** — fix the known bug, polish,
and bring the HELP page up to date. Also housekeeping: the three untracked marketing PNGs
(`alt_logo.PNG`, `dbit.png`, `share.PNG`) moved out of the repo to `~/Documents/DrawBit-marketing/`
(founder's call; nothing deleted). `git status` is clean now.

## Shipped this session (branch `polish`)

- **`fix(palette)` — PaletteExtractor scans the full canvas on non-square draws.** It looped
  `width × width` via the square-only `.dimension` alias, so on 9:16 portrait canvases
  "grab colors from this draw" silently ignored everything below the top square; landscape merely
  over-scanned (PixelGrid bounds-checks reads). Now loops `width × height`. TDD: portrait
  regression test watched red first; landscape guard added. `PaletteExtractorTests` = 6 tests.
- **`feat(help)` — HELP copy refreshed to current features.** Audit compared all 10 tiles against
  everything shipped since the copy was written (2026-06-23). Six tiles were still accurate
  (GALLERY, COLORS, LAYERS, ANIMATION, DRAWBIT FM, ABOUT). Four were stale and got founder-approved
  rewrites:
  - **TOOLS:** + hold-to-straighten line, + select's flip/rotate/copy/delete, undo/redo "sit up
    top" (was "at the bar's end" — stale since the top-bar move).
  - **CANVAS:** + square/wide/tall ratio choice, + RESET chip, + two-finger-tap undo /
    three-finger-tap redo.
  - **TRACE:** + "The pick tool reads its colors through blank pixels."
  - **EXPORT:** + "FILM: your draw painting itself, start to finish."
  - Verified untruncated on the 13-inch iPad sim via a throwaway XCUITest screenshot (temp test
    removed before commit; all four tiles render their full body, 4–5 lines each).

## Verification

- Full suite run post-change: **445 unit + 36 UI, 0 failures** (both new palette tests included).
  HelpScreenUITests only assert tile *titles*, so no test changes were needed for the copy.

## Reusable notes

- **Screenshot-verify HELP copy changes:** tile bodies are fixed-height (176pt) `Text` with
  `.minimumScaleFactor(0.85)` and no `lineLimit` — overflow truncates with an ellipsis, and no
  test catches it. The cheap check: temp XCUITest that taps the changed tiles + attaches
  `app.screenshot()` with `.keepAlways`, then
  `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>` and eyeball the PNG.
- HELP body copy lives in one place: the `topics` array in
  `DrawBit/Views/Gallery/HelpScreen.swift`. Titles carry the a11y ids; bodies are unasserted.
- `CanvasSize.dimension` is a **square-only back-compat alias for `width`** — grep for `.dimension`
  when touching anything that iterates a grid; the palette bug was exactly this.

## Still next (unchanged queue, founder has NOT green-lit any)

- Cheap polish batch: **rename a draw**, **dithering + color-ramp**, **Copy-PNG**,
  **empty-gallery hint**; save-error indicator (audit item 5).
- FILM follow-ups if wanted: FM audio bed, share-flow hint, multi-frame replay.
- Reference → editable layer (foundationed).
- Dropped, do NOT re-propose: PNG import, rectangle tool.

## Guiding star (unchanged)

Calm, premium, single-player pixel app that feels like a beautiful machine. Founder prefers
plain-language design talk; discuss shape before building anything non-trivial.
