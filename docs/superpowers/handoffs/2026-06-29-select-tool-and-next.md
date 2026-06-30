# Handoff — Select tool shipped + what's next (2026-06-29)

## Just shipped — the Select tool (`c75ed1a`)
The old "Laso" rectangular marquee is now a real **Select** tool. `main` is green (full unit + UI
suite). What changed, by layer:

- **Rename:** `Tool.swift` "Laso" → "Select" (the enum case stays `.marquee` internally).
- **`DrawBit/Drawing/SelectionTransform.swift` (new, pure, TDD):** `flipHorizontal` / `flipVertical`
  / `rotate90`. `rotate90(_:around:)` is **fit-or-refuse** — it returns `nil` (caller no-ops) when
  the rotated selection can't fit the canvas, so it never clips/loses pixels. Only non-square
  canvases can trigger the refusal; a square canvas always fits. Tests in
  `DrawBitTests/Drawing/SelectionTransformTests.swift`.
- **`EditorState` (5 new methods in the marquee section):** `flipSelectionHorizontal/Vertical`,
  `rotateSelection() -> Bool`, `duplicateSelection`, `deleteSelection`. Flip/rotate mutate only the
  floating selection (no layer write; they ride the eventual `commitMarquee`'s single undo step).
  Duplicate stamps a copy at the current offset and **keeps floating**; delete bakes the
  already-cut hole. Each layer-writing action is one undo step. Tests appended to
  `DrawBitTests/State/EditorStateSelectionTests.swift`.
- **`DrawBit/Views/Editor/SelectionActionBar.swift` (new):** bottom-center bar — FLIP H · FLIP V ·
  ROTATE · COPY · | · DELETE. Mounted in `CanvasView` (next to `resetViewChip`), wired in
  `EditorView` with the line-tool detent feedback (`SelectionFeedback.shared.fire()`, fired on
  rotate only when it succeeds) and `saveCurrentFrame()` for the two layer-writing actions.
  **Design rule:** it inherits the RESET chip's styling verbatim (sharp rectangle, `Color(white:
  0.16)`, 1pt `toolSelected` border, white pixel font, opacity fade) — keep any future
  pop-over-the-canvas affordance in that same family.

### Gotchas worth remembering
- **Marching ants were wedging XCUITest.** The selection's marching-ants overlay uses
  `TimelineView(.animation)`, which never idles — that wedges XCUITest's auto-sync permanently
  (the CLAUDE.md rule). It's now gated to static dashes under `UITestSupport.isRunning`. Any new
  always-animating overlay needs the same gate.
- **Canvas clobbers child a11y identifiers.** `CanvasView` has `.accessibilityIdentifier("Canvas")`,
  which propagates onto the bar's buttons (they report identifier `Canvas`). So the UI test queries
  the bar buttons by **label** (`"ROTATE"`, `"FLIP H"`, `"DELETE"`), not a custom identifier. Do the
  same for any future in-canvas controls.
- **Duplicate keeps the original via user action, not magic:** stamp-at-current-position + keep
  floating. To preserve the original in place, duplicate *before* moving, then drag the copy away.

### Possible polish (not blocking)
- Bar icons are SF Symbols (`rotate.right`, `square.on.square`, …); custom `PixelArtIcon` glyphs
  would match the undo/redo top-bar treatment more tightly.
- Bar is bottom-center, RESET chip is bottom-trailing; they don't collide in practice but could on
  a very narrow window. Revisit only if it shows up.
- A true **free-form lasso / magic wand** was explicitly deferred — it's a whole selection-shape
  system on top of this. Its own item if the user wants it.

## Still next
**Founder decisions (2026-06-29): PNG import and the rectangle tool are DROPPED — do not
re-propose them.** Remaining queue:
- **Brush size — ACTIVE (building now).** 2/3/4px square+round for pencil+eraser; watch the
  pixel-perfect-elbow + mirror interaction.
- **Time-lapse / process replay** — kept in the queue; the standout delight/virality play, biggest
  lift, deserves its own brainstorm. Reuses stroke snapshots + the GIF/APNG exporters.

DrawBit's guiding star (from the founder): a **calm, premium, single-player pixel app that feels
like a beautiful machine.** Judge each item by "does it remove friction from joyful making."
Verify file/line refs before editing — they drift.
