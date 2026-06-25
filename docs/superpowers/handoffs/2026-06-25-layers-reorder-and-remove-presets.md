# Handoff — 2 tasks (2026-06-25)

Previous session shipped **non-square canvases** (all 4 stages), gallery single-source
lighting, and the export SIZE relabel — all on `main`. Below are the next two tasks. Neither
is started.

## Repo state
- Branch `main`, in sync with `origin/main`, **HEAD `93ea68b`** (+ this handoff commit), tree clean.
- Only `main` exists (all feature branches deleted).
- Untracked root images — **leave alone, never `git add -A`**: `alt_logo.PNG`, `dbit.png`, `share.PNG`.
- Build/run/test commands + invariants live in `CLAUDE.md`. As of last session: **337 unit + 33 UI tests green.**

## How the user likes to work
- **Verify visually on the sim**, not just by building — drive the Simulator via computer-use.
  Re-`open_application "Simulator"` if it loses focus.
- **Ship cadence:** branch → commit → push → fast-forward merge to `main` → delete branch
  (local + remote). One small change per branch. Always `rm -rf build` before committing — BUT
  **never delete `build/` while a background test run is using `-derivedDataPath build`** (it
  kills the run with a spurious `mkstemp: No such file or directory` / mass failures).
- Plain-spoken design talk, no jargon. Don't over-ask or over-engineer. **No rounded corners** on
  custom chrome. TDD per `CLAUDE.md` (watch the test fail first).

---

## 1. LAYERS — fix press/hold/drag/reorder mechanics & feel
- Files: `DrawBit/Views/Editor/LayerRow.swift` (the row + drag) and
  `DrawBit/Views/Editor/LayersPanel.swift` (drop handling + `performMove`).
- Current approach: `LayerRow` uses SwiftUI `.draggable("\(displayIndex)")` with a cell-level
  `.dropDestination` in `LayersPanel` (`performMove`). **Known pain (per code comments):**
  long-press is unreliable next to `.draggable`; reorder is completed by dragging the ~32-pt
  thumbnail, which is fiddly.
- Task: make press → hold → drag → reorder reliable and good-feeling. Likely replace the
  `.draggable`/`.dropDestination` combo with a **custom long-press-then-drag** gesture (manual
  reorder with live row offset/insertion, a clear/larger grab target).
- **Verify:** drag reorder is hard to automate in the Simulator — lean on the **user testing the
  feel**, plus existing `LayersPanelUITests` (poll for row counts per `CLAUDE.md`'s async-rebuild
  note). Respect the animation-gating rule (`UITestSupport.isRunning`) for any new `.animation`.

## 2. NEW DRAW — remove the 16/32/64/128 preset shortcuts
- The size presets feel redundant now: the user can dial any size with the **slider** or the
  **+/− steppers**, so the preset chip row is clutter.
- File: `DrawBit/Views/Gallery/NewPieceSheet.swift`. Remove the `presetChips` view (the
  `ForEach(CanvasSize.presets) { … }` row) from `body` and delete the `presetChips` computed
  property. Keep the **ratio selector** (1:1 / 16:9 / 9:16), the number field/steppers, the
  slider, and CREATE.
- **⚠️ Breaks UI tests — must migrate them.** Most UI tests create a piece via
  `app.buttons["NewButton"].tap()` then `app.buttons["NewPiece-32"].tap()` (the preset chip's
  a11y id). Removing the chips deletes `NewPiece-32`. The field defaults to "32", so the fix is
  to replace those two taps' second step with **`app.buttons["NewPiece-create"].tap()`** (creates
  the default 32×32) — a near-mechanical find/replace across:
  `ColorPaletteUITests`, `LayersPanelUITests`, `GalleryMenuUITests`, `ReferencePhotoUITests`,
  `ShareSheetUITests`, `AnimationStripUITests`, `HappyPathTests/DrawAndSaveTest` (grep
  `NewPiece-32` to find every site). Run the full UI suite after.
- Optional: also drop `CanvasSize.presets` if nothing else references it (grep first — the ratio
  presets / `s16…s128` constants may still be used by tests).

---

## Pointers
- Non-square design rationale: `docs/superpowers/specs/2026-06-24-non-square-canvases-design.md`.
  Memory: `project_nonsquare_canvases.md`, `project_gallery_lighting.md`.
- Regenerate the Xcode project after adding/moving `.swift` files: `rm -rf DrawBit.xcodeproj && xcodegen generate`.
