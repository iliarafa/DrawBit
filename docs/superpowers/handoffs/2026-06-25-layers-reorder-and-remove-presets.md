# Handoff — 1 task (2026-06-25)

Previous session shipped **non-square canvases** (all 4 stages), gallery single-source
lighting, the export SIZE relabel, and **removed the New Draw 16/32/64/128 size presets**
(`50b1514`) — all on `main`. The one remaining task below is not started.

## Repo state
- Branch `main`, in sync with `origin/main`, **HEAD `50b1514`** (or later), tree clean.
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

## ✅ (DONE 2026-06-24) NEW DRAW — removed the 16/32/64/128 size presets
Shipped in `50b1514`: removed `presetChips` from `NewPieceSheet`; migrated every UI test from
the `NewPiece-32` chip to `NewPiece-create` (field defaults to 32). `CanvasSize.presets` kept as
a model constant. 33/33 UI tests pass.

---

## Pointers
- Non-square design rationale: `docs/superpowers/specs/2026-06-24-non-square-canvases-design.md`.
  Memory: `project_nonsquare_canvases.md`, `project_gallery_lighting.md`.
- Regenerate the Xcode project after adding/moving `.swift` files: `rm -rf DrawBit.xcodeproj && xcodegen generate`.
