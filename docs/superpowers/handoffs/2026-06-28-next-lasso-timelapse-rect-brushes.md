# Handoff — next items (2026-06-28)

## Where things stand
`main` is green and in sync (370 unit + 33 UI). Recent shipped work: pencil hold-to-straighten
line + perfect-angle detents (`80615aa`, `4fdfc75`), undo/redo moved to the top bar with
two/three-finger-tap gestures + a contextual RESET chip (`4fdfc75`), a real data-loss fix
(`97f1432`), and **grid fade-on-zoom-out** (`b606f40`). Full prioritized roadmap + positioning
context live in memory (`project_audit_followups`, `project_crisp_grid`).

**Latest fix — grid fade (`b606f40`):** a large canvas at fit used to wash gray because every pixel
boundary is a 1pt line and the lines merged at ~3pt/cell. Now the *interior* grid fades out as the
on-screen cell shrinks (pure `gridLineAlpha` in `CanvasTransform.swift`: hidden ≤4pt, full ≥9pt),
while the canvas *border* is a separate steady stroke so bounds still read. In `CanvasView.gridOverlay`.
Thresholds `lo=4`/`hi=9` are easy to nudge. This came from the founder hitting it in their own
256×144 sprite loop — the truest kind of fix. DrawBit's guiding star (from the founder): a **calm, premium,
single-player pixel app that feels like a beautiful machine**, built first to make sprites for the
game *All my Falling Stars*. Judge each item by "does it remove friction from joyful making,"
not "does it tick a competitor's box." Several items below are **discuss-first** — settle the shape
with the user before building.

---

## 1. Discuss & fix the lasso
**What's wrong (from the audit):** the "Laso" tool is the weakest selection in the category and is
mislabeled. It's a **rectangular** marquee (not a free-form lasso), it can only *slide* a selection,
and it **always cuts** the source (destructive) — so you can never copy/duplicate, flip, or rotate.
The misspelled, mis-described label is also an App Store screenshot liability.

**Current code:** `DrawBit/Drawing/Marquee.swift` (extractAndCut sets source `.transparent` +
commit/translate), `DrawBit/State/EditorState.swift` (`MarqueeSelection` carries only a `dragOffset`),
`applyMarqueePoint` in `DrawBit/Views/Editor/EditorView.swift`, label in `DrawBit/Models/Tool.swift`.

**Discuss first:** what should it become? Options, smallest→largest:
- Fix the **label/typo** ("LASO" → "SELECT"/"MARQUEE") — trivial, do regardless.
- Add **copy/duplicate + flip H/V + rotate 90°** on the current rectangular selection.
  `MarqueeSelection` already holds the lifted pixels as a `PixelGrid`, so flip/rotate/copy are
  ~10-line grid ops — high value, low cost. Likely the sweet spot.
- A true **free-form lasso** (or magic-wand) — the biggest lift; only if the user wants it.
**Effort:** label S; transforms M; free-form lasso L.

---

## 2. Animate a time-lapse of a canvas
**What:** record the drawing process and play it back / export it as a clip (dotpict-style
"process replay"). Flagged in the audit's competitive scan as a **cheap, high-virality win** that
fits DrawBit's share-centric export sheet and "feel" positioning — every drawing becomes a
shareable clip that advertises the app.

**Why it's a natural fit here:** the undo system already snapshots the active layer's pixels at the
start of every stroke (`EditorState.preStrokeSnapshot` → `.layerPixels` undo entries), which is a
ready-made source of "steps." And the render/export path already produces animated output —
`Rendering/GIFExporter.swift` + `APNGExporter.swift` (used by the animation feature) — so the
encoder mostly exists.

**Discuss first:** capture model (per-stroke snapshots vs periodic canvas captures vs the full
frame sequence), how long/lossy a session to keep (memory), playback UI vs export-only, and output
format (GIF/APNG, maybe MOV via the video tooling). Watch: this is the only item that needs a
**persistence** decision (do we store the replay with the `Piece`, or generate on demand from
history?). **Effort:** M–L (biggest of the four; likely its own brainstorm → spec → plan cycle).

---

## 3. Rectangle tool
**What:** outline + filled rectangle. The next shape after the line (audit's #1 gap). Unlike the
line — which we made a *pencil gesture* (hold-to-straighten) so it needed no toolbar slot — a
rectangle wants an **explicit anchor→drag→release** interaction, so it needs a tool/mode.

**Current code / reuse:** `DrawBit/Drawing/PixelRect.swift` is geometry only — there is **no
rectangle-outline or filled-rect pixel rasterizer yet** (write a pure `RectTool` in the Drawing
layer, TDD, mirroring `LineTool`). The live drag-preview can reuse the **restore-from-`preStrokeSnapshot`
then redraw** mechanic the line uses (`EditorState.applyStraightLine` is the template → add
`applyRect(from:to:filled:mirror:)`). Input: an anchor→drag in `CanvasInputView` (the marquee's
define-drag is a precedent), or a QuickShape-style draw-rough-then-hold (deferred earlier — probably
keep it an explicit tool for v1).

**Discuss first (this was started but not settled):** how to expose it on the already-tight toolbar
— one "SHAPE" tool + small popover (line/rect/ellipse + fill toggle) vs a dedicated RECT button.
Note undo/redo just freed two tool-strip slots. Outline-vs-filled = a toggle. **Effort:** M.

---

## 4. Discuss brushes
**What:** today **every tool is locked to a single pixel** (`DrawBit/Drawing/Pencil.swift` /
`Eraser.swift` write exactly one cell; no `brushSize` anywhere; `applyDrawPoint` stamps one point).
On 128/256px canvases, blocking-in and big erases one pixel at a time is real friction. "Brushes"
most concretely means **brush size** (2/3/4px, square + round) shared by pencil + eraser.

**Discuss first:** scope — just size, or also shapes/patterns/dither-as-a-brush? Recommend starting
with **size** (table-stakes, removes the most friction). **Known gotcha (from the audit critique):**
a multi-pixel stamp interacts with two existing per-point systems — the **pixel-perfect elbow filter**
(`EditorState.revertPixelPerfectElbow`, which only makes sense for 1px strokes) and the **mirror**
write — so the stamp must bypass/rethink the pixel-perfect path and mirror each stamped cell. A pure
`Brush.stamp(into:at:size:shape:)` in the Drawing layer (TDD) keeps it testable. UI: a size control
(stepper/slider) — placement TBD now the tool strip has room. **Effort:** S–M.

---

## Suggested sequencing
- **Quick wins first:** the lasso *label fix* + selection *transforms* (#1) and *rectangle* (#3)
  are the most "removes friction from making" and reuse existing mechanics (`LineTool`/snapshot
  pattern, `MarqueeSelection` grid). Brush *size* (#4) is also cheap and instantly felt.
- **Time-lapse (#2)** is the standout *delight/virality* play but the largest — give it its own
  brainstorm. It's the one that most advertises the app, so worth doing well, not fast.
- The three "discuss" items (#1 shape, #3 exposure, #4 scope) each need a short decision with the
  user before coding — don't assume.

All four are in the audit roadmap (`project_audit_followups`). Verify current file/line refs before
editing — they drift.
