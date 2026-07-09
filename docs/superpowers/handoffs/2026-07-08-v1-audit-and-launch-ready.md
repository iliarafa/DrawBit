# Handoff — July 8 · v1.0 audited & cleared to submit

Covers everything since `2026-07-06-july6.md`. `main` = `origin/main`, tip **`12f44e1`** (this handoff +
the test-cleanup ride on top), pushed and in sync. **494 tests green** (449 unit + 45 UI, 0 failures)
on a clean-from-scratch build on `iPad Pro 13-inch (M5)`; device **Release compile** (`generic/platform=iOS`)
succeeds. **The headline: DrawBit v1.0 was audited this session and cleared for App Store submission —
zero blockers.**

## Shipped this session (origin/main, oldest → newest)

Polish first (closing the July 6 queue):
- **FPS zero-pad** (`8f49a33`) — single-digit speeds render `04 FPS`/`08 FPS` (`%2d`→`%02d`, `FramesStrip`),
  so cycling stays symmetric under the gauge. Founder picked zero-pad over the plain " 4 FPS".
- **LOCK dark-chip legibility** (`de4f1c5`) — a locked layer's red `LOCK` sat on a dark chip so it stays
  vivid against the cyan **selected-row** wash (`LayerRow`); constant 52pt slot + `lineLimit(1)` so the
  label never re-wraps/shifts. Chosen from 4 real on-device variants. **Gotcha caught by the real capture:
  the preview mock used a wider slot, hiding a "LOC"/"K" wrap in the true 44pt control** — capture the
  *shipped* row, not a mock.
- **Empty-gallery hint** (`42f8be0`) — one calm line `Tap + to DRAW` under the New tile when there are no
  draws; clears once one exists (`GalleryView.emptyHint`). Founder trimmed the first "YOUR GALLERY IS EMPTY"
  line and chose the wording.
- **Copy-PNG** (`d74fdf0`) — a quiet "COPY PNG" secondary action under EXPORT copies the active frame to
  `UIPasteboard` (`public.png`) at the selected size (`ShareSheet.copyPNG`), reusing `PNGExporter`.
- **Save-error indicator** (`bee2a15`) — non-blocking "COULDN'T SAVE" pill when an autosave throws, cleared
  on the next success. `EditorView.attemptSave` wraps frame/reference/time-lapse saves and sets session-only
  `EditorState.saveDidFail`; a `-UITest-failSaves` arg forces the throw. Founder repositioned it to sit
  centered under the `32 × 32` dimension in the middle of the top-bar→canvas gap (`.padding(.top, 110)`).

Then the **v1.0 pre-App-Store audit** (the session's main event):
- Ran a **clean full build + entire suite + device-Release compile** (ground truth) **alongside** a
  7-dimension parallel code audit (crash/correctness · load-bearing invariants · SwiftData/migration/data-safety ·
  App Store compliance · exporters/OOM · UI/a11y · privacy/lifecycle), **every finding adversarially
  re-checked** against real code, then a release-manager synthesis. Verdict: **GO — zero blockers.** All
  invariants intact, crash-safe, privacy-clean ("Data Not Collected" supportable), config ready.

Fixes that came out of the audit:
- **Eyedropper phantom-undo** (`cc7d364`) — the one confirmed major. A color pick flowed through the normal
  stroke-commit path, pushing a `.layerPixels(before==after)` undo entry + re-saving on every pick, so the
  first Undo after draw-then-pick did nothing. `EditorState.commitStroke` now **returns `Bool`** and skips
  the push + keyframe when the layer is unchanged; `commitStrokeAndSave` skips the save when nothing
  committed. Fixes the whole no-op class (same-color taps, empty fills). TDD'd (RED reproduced the exact
  "one Undo leaves the pixel red").
- **Release config** (`21a7838`) — `ITSAppUsesNonExemptEncryption = false` (no crypto/networking; stops
  App Store Connect flagging every build "Missing Compliance") + README `iPadOS 17+`→`18+` to match the
  deliberate 18.0 target.

Then all six **fast-follow minors** (audit-flagged):
- **ADD disabled during playback** (`f805c2f`) — `|| state.isPlaying` on the FramesStrip ADD predicate.
- **New Draw failure surfaced** (`c479028`) — replaced the empty catch with a "Couldn't create the draw"
  alert (`-UITest-failCreate` hook for the test).
- **CLEAR confirm + background-save** (`7412f45`) — CLEAR routes through a "CLEAR LAYER?" confirm for a
  non-empty active layer (a floating marquee counts as content; blank clears instantly; lock respected);
  a `scenePhase(.background)` handler flushes frame + time-lapse (which lives in-memory until saved) since
  `.onDisappear` doesn't fire on a background+OS-kill.
- **FM animation + audio session** (`12f44e1`) — `onChange(of: radio.isPlaying)` kicks the ON-AIR
  blink/waveform when Play is pressed on-screen; `pause(deactivateSession:)` releases the audio session
  **only on a user pause** so interrupted apps auto-resume — system-induced pauses (interruption began,
  headphones unplugged) keep it, and `stop()` (terminal give-up) still releases.
- **Test-scaffolding cleanup** (this commit) — removed a committed dead `shotDir` (a prior session's
  scratchpad path) + its `saveShot` calls from `ToolBarBrushSizeUITests`.

## Reusable gotchas / lessons (carry these)

- **Green-light on evidence, not vibes.** The audit paired a *clean* full build + suite + device-Release
  compile (empirical) with the multi-agent code audit; every claimed blocker was grounded in file:line and
  cross-checked. **A dimension agent can die on the StructuredOutput retry cap** (the data-migration-safety
  agent did) — hand-verify that dimension yourself so a dead agent doesn't leave a go/no-go coverage hole.
- **The full UI suite flakes under machine load.** A run that took ~10,500s (23× normal, because heavy
  background work was competing) failed `testShareSheetShowsPreviewAndControls` with **"Timed out while
  synthesizing event"** — pure simulator saturation; it passes in 12s isolated. Confirm any full-suite
  failure by an isolated re-run before believing it, and don't run the full UI suite concurrently with a
  workflow/other builds.
- **PhotosPicker needs NO `NSPhotoLibraryUsageDescription`** — it runs out-of-process; the string's absence
  is correct, not a rejection risk. `NSPhotoLibraryAddUsageDescription` (save-to-Photos) is present.
- **`ITSAppUsesNonExemptEncryption` lives in `project.yml`** (which *generates* `DrawBit/Info.plist`) — you
  must **regen** (`rm -rf DrawBit.xcodeproj && xcodegen generate`) to bake a plist key into the build.
- **No-op stroke guard:** `commitStroke` compares the active layer's current pixels to the pre-stroke
  snapshot and skips the undo push + keyframe when equal (`before == after`) — the correct model for any
  read-only/no-change "stroke". Verified it does **not** disturb the marquee: the marquee snapshots the
  *whole* layer at `beginMarqueeDefine`, so real move/transform/delete stays `before != after`.
- **`RadioController.pause()` is also the interruption/route-change handler** — so deactivate the audio
  session only on a *user* pause (`pause(deactivateSession:)`), never on system-induced pauses. `stop()` is
  only reached when the *entire station* fails to decode (a genuine terminal stop), so releasing there is fine.
- **Run an adversarial review before committing a batch on a launch codebase.** A 3-lens review workflow
  over the minors diff surfaced two real edges the first cut missed (CLEAR skipped its confirm when the whole
  drawing was lifted into a floating selection; the audio-session release fired on *any* pause). Both fixed.

## Still next (queue — re-verify against current code before starting)

- **The July 6 queue is drained.** FPS zero-pad ✓; layers nits ✓ (LOCK shipped, the 1px `+` **declined** by
  the founder); cheap-polish batch ✓ (Copy-PNG / empty-hint / save-error shipped — **rename-a-draw and
  dithering/color-ramp DECLINED**); **FILM ships as-is** (audio-bed + multi-frame replay **DROPPED**); all six
  audit fast-follow minors ✓.
- **Only open item: Reference → editable layer** (discuss-first). Commit the traced photo as a real `Layer`
  (foundationed via `ReferenceSampler`). Only if the founder wants editable photo→pixels — it would touch the
  display-only-reference invariant, so design it first.
- **Optional cosmetic** noted by the audit (not fixed): one gallery thumbnail `Image` omits
  `.antialiased(false)`. Trivial if it ever bugs anyone.

## Status

**v1.0 is cleared to submit.** All work is on `origin/main`, tree clean, 494/494 green, device-Release
compiles. The remaining decision is the founder's manual App Store submission.

## Guiding star (unchanged)

Calm, premium, single-player pixel app that feels like a beautiful machine. Iterate on **real simulator
captures**, not text/mockups. Reuse the app's own idioms before inventing UI. Verify file/line refs before
editing — they drift.
