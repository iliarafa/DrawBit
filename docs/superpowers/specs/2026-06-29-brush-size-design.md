# Brush size — design (2026-06-29)

## Goal

Every tool in DrawBit paints exactly one pixel today (`Pencil`/`Eraser` both call
`grid.setPixel` once). On 128/256-px canvases, blocking in and erasing large areas one pixel at a
time is real friction — the founder hit it in their own 256×144 sprite work. This adds a **square
brush size (1–4 px)** to the pencil and eraser so covering ground is fast, without adding visible
chrome to the calm toolbar.

Scope is deliberately tight: **square nibs only**, sizes **1–4**, **pencil + eraser only**.

## User-facing behavior

- The pencil and eraser each carry a size, **1 → 2 → 3 → 4**.
- **Cycle-on-tap:** tapping the *already-selected* tool steps its size and wraps `4 → 1`. Tapping an
  *unselected* tool just selects it (at its remembered size), as today.
- Each step fires the existing detent **click + haptic** (`SelectionFeedback.shared.fire()`), the
  same feel as selecting a tool or hitting a line-angle detent.
- **Sizes are per-tool and independent.** This is forced by cycle-on-tap (tapping the pencil must
  not change the eraser) and is exactly the desired workflow: a fat eraser and a fine pencil held at
  once.
- **Reset to 1 each session.** Brush size lives in the session-scoped `EditorState`; opening a draw
  starts both tools at 1. Not persisted to the `Piece` or to `AppSettings` in v1.

## The icon — "the nib is the icon" (scheme C)

The toolbar glyph **becomes the square it paints**, so the current size is always visible without
opening anything:

- **Pencil** → a **filled** square that grows with its size.
- **Eraser** → a **hollow** (stroked) square that grows with its size. Filled-vs-hollow is what
  distinguishes the two now that both are squares; the `PENCIL` / `ERASER` label underneath keeps
  the identity.
- Selected = teal (`Color.toolSelected`, `#0099CC`); unselected = `white.opacity(0.55)` — unchanged
  from today.
- The glyph's on-screen side is a comfortable visual mapping of size → points (e.g. 1→8pt … 4→22pt),
  not literal pixels, so size 1 still reads as a deliberate small square rather than a speck. The
  44×44 tap target is unchanged.

The classic Pelikan two-tone eraser look was considered and **dropped**: because the nib has to grow
with size, a fixed 2/3–1/3 colour split doesn't scale as a clean square footprint.

## Drawing mechanics

Today every freehand point flows through `applyDrawPoint` ([EditorView.swift:388](DrawBit/Views/Editor/EditorView.swift:388)):
mirror is computed, the pixel-perfect elbow cleaner runs, then one cell is painted (and its mirror),
all inside a single `mutateActiveLayerPixels { … }` closure (= one undo snapshot). The square stamp
slots into that structure with minimal change.

- **New pure type `Brush` (Drawing layer, TDD).**
  `Brush.squareCells(centeredAt: (Int, Int), size: Int) -> [(Int, Int)]` returns the nib's cells.
  Out-of-bounds cells need no special handling — `PixelGrid.setPixel` already guards
  `contains(x:y:)` and drops them.
- **Anchoring rule (explicit, predictable):** an `n × n` block whose top-left is at
  `(x - (n-1)/2, y - (n-1)/2)` using integer division.
  - `n = 1` → `{(x, y)}` (the cursor pixel).
  - `n = 2` → covers `x…x+1`, `y…y+1` (cursor at the upper-left of the 2×2; extends down-right).
  - `n = 3` → covers `x-1…x+1`, `y-1…y+1` (centred on the cursor).
  - `n = 4` → covers `x-1…x+2`, `y-1…y+2` (centred, one extra pixel down-right).
  Plainly: **odd sizes centre on your finger; even sizes extend one extra pixel down and right.**
- **The stamp loop** replaces the single `Pencil.paint` / `Eraser.erase` call: iterate the nib's
  cells and paint each; Bresenham interpolation between coalesced touch points already prevents gaps,
  so thick strokes come for free.
- **Mirror reflects each painted cell**, not the nib's centre: for every cell `(cx, cy)` painted,
  if mirror is on also paint `(width - 1 - cx, cy)`. Per-cell reflection keeps even-sized nibs
  perfectly symmetric. Overlapping writes on the centre column are harmless — same value, one
  snapshot.
- **Pixel-perfect elbow cleaner runs only at size 1.** `revertPixelPerfectElbow` is a 1-px concept;
  above size 1 it is skipped entirely. So the **size-1 path is byte-for-byte unchanged**.
- Brush size is **constant for the duration of a stroke** — it can only change between strokes via a
  toolbar tap, so there is no mid-stroke resize to reason about.

## Straight line honors the brush size

The hold-to-straighten line is a pencil gesture, so it draws at the pencil's current size (a 3-px
pencil snaps a 3-px line). `applyStraightLine` ([EditorView.swift:549](DrawBit/Views/Editor/EditorView.swift:549))
already calls `LineTool.apply(...)`; add a `brushSize:` parameter and stamp `Brush.squareCells` at
each point along the Bresenham path, mirroring each cell with the same rule. `applyStraightLine`
passes `state.pencilSize`. The size-1 line is unchanged.

## State model

In `EditorState` (session-scoped):

- `var pencilSize: Int = 1` and `var eraserSize: Int = 1` (two stored `Int`s — `@Observable`
  re-renders the glyph when they change).
- `let brushSizeRange = 1...4` — a named constant so the cap is easy to raise later.
- `func brushSize(for tool: Tool) -> Int` → `pencilSize` / `eraserSize`, else `1`.
- `func cycleBrushSize(for tool: Tool)` — pencil/eraser only; steps up one and wraps at the range
  bound: `size = size >= brushSizeRange.upperBound ? brushSizeRange.lowerBound : size + 1`. Driving
  the wrap off `brushSizeRange` (not a literal `4`) keeps it correct if the cap is ever raised.

Not written to `Piece` and not to `AppSettings`: consistent with the rule that `EditorState` is
in-memory and session-scoped.

## Code touch points

| Layer | Change |
| --- | --- |
| `DrawBit/Drawing/Brush.swift` (new) | Pure `Brush.squareCells(centeredAt:size:)`. Imports only `Foundation`. |
| `DrawBit/Drawing/LineTool.swift` | Add `brushSize:` param; stamp the nib along the path. |
| `DrawBit/State/EditorState.swift` | `pencilSize`/`eraserSize`, `brushSizeRange`, `brushSize(for:)`, `cycleBrushSize(for:)`. |
| `DrawBit/Views/Editor/EditorView.swift` | `applyDrawPoint` loops the stamp for pencil + eraser; `applyStraightLine` passes `pencilSize`. |
| `DrawBit/Views/Editor/ToolBar.swift` | Tap-the-selected-tool cycles; pencil/eraser render the square glyph instead of an SF Symbol. |
| `DrawBit/Views/Gallery/HelpScreen.swift` | One line in the TOOLS tile so the hidden gesture is discoverable (copy to be approved). |

## Tools unaffected

Fill, eyedropper, colour-swap, and select are untouched — they keep their SF Symbols and their
single-action behavior. Tapping them while selected does nothing new.

## Testing

- `DrawBitTests/Drawing/BrushTests.swift` — `squareCells` for sizes 1–4: correct cell sets and the
  anchoring rule; size 1 is a single cell.
- `EditorState` tests — `cycleBrushSize` wraps `1→2→3→4→1`; pencil and eraser independent;
  non-pencil/eraser tools are a no-op; default is 1.
- State-level integration — a size-3 pencil stroke paints the 3×3 footprint; mirror paints both
  sides symmetrically; the size-1 path still runs the pixel-perfect cleaner.
- `LineToolTests` — a thick line stamps the nib along the path; size-1 line unchanged.
- UI (optional, animations gated per CLAUDE.md) — tapping a selected pencil changes its exposed
  size; query the button by label, not the clobbered `Canvas` identifier.

## Out of scope (v1)

- Round / circle nibs (square only).
- The Pelikan two-tone eraser icon (dropped — the nib must grow).
- Persisting sizes across launches or onto the `Piece`.
- Brush patterns, dither-as-a-brush, pressure.
- Sizing fill / eyedropper / colour-swap / select.
- Sizes beyond 4 (the range is a constant; raising it is a one-line change later).

## Invariants preserved (from CLAUDE.md)

- **Straight alpha, 0/255 only:** the multi-cell stamp still writes only opaque colour (pencil) or
  `RGBA.transparent`, a = 0 (eraser). No partial alpha is ever produced.
- **Pure-logic rule:** `Brush.swift` imports only `Foundation`; no SwiftUI/SwiftData/UIKit.
- **One undo step per stroke:** every stamped and mirrored cell writes inside one
  `mutateActiveLayerPixels` closure.
- **Session-scoped `EditorState`:** brush sizes live there, never on `Piece`.
- **Nearest-neighbor render path is untouched** — this is a data-write change only.
