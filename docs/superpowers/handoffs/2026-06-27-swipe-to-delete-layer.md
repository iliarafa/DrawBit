# Handoff — Swipe-left-to-delete a layer (2026-06-27)

## Status of the layers work (DONE, on `main`)
- **Drag-to-reorder** rebuilt as a reliable custom long-press→drag (commit `dbe6759`). The old
  native `.draggable` on the 32pt thumbnail was the reason layers felt "immovable"; the model move
  (`Frame.move`, `Drawing/Frame.swift:86`) and undo/persistence were always fine.
- **"Pickup" feedback** fires at the *arm* moment (long-press completes, before any drag): medium
  impact haptic + a springy scale **pop** (1.03) with brighter bg + accent border. Selection tick on
  each slot crossed; light impact on drop. Index math is pure + unit-tested (`LayerDragMath.swift`,
  `LayerDragMathTests` — 12 tests). 352 unit + 33 UI green, verified on device.
- Files: `DrawBit/Views/Editor/LayerRow.swift`, `LayersPanel.swift`, `LayerDragMath.swift`.

## Next task — swipe-left-to-delete (NOT started)
Swipe a layer row to the left to delete it, **no confirmation popup**. As the finger drags, a
**red fill sweeps the row from left → right** proportional to swipe progress. Swipe far enough and
release → the layer is gone (undo still recovers it).

### Behavior
- Drag the row leftward; `progress = min(1, abs(translation.width) / rowWidth)`.
- Red overlay clipped to `progress * rowWidth`, **anchored to the left edge, growing rightward**
  (the user was explicit: "fills the layer with red… slide from left to right").
- Release **past a high threshold (~0.75–0.85)** → delete immediately, no `ConfirmDialogSheet`.
  Below threshold → spring the red back to 0, row restored.
- On commit: collapse row height to 0, then remove (so the list closes the gap smoothly). Add a
  heavier delete haptic (e.g. `UINotificationFeedbackGenerator`/`.heavy` impact) at commit.
- **Guard `layerCount > 1`** — never allow deleting the only layer (mirror the delete button's
  `delDisabled = state.frame.layers.count <= 1`). Consider a small rubber-band / no-op if it's the
  last layer.

### Reuse the existing delete path (minus the confirm sheet)
In `LayersPanel.swift` the delete button already does the correct sequence — replicate it as a
per-id helper and pass an `onSwipeDelete` closure to `LayerRow`:
```
state.commitFloatingSelectionIfAny()        // critical: see the comment at LayersPanel.swift:89
state.beginStructuralSnapshot()
state.frame.removeLayer(id: <thisRowsLayerID>)
state.commitStructuralChange()              // undo entry → swipe-delete is recoverable
onStructuralChange()
```
Do **not** reuse the `confirmDeleteLayerID`/`ConfirmDialogSheet` path. Because there's an undo
snapshot, "no confirmation" is safe.

### ⚠️ Key risk — gesture composition
The row now carries: tap-to-select (`.onTapGesture`), the **long-press(0.22s)→drag** reorder
(`.gesture(...)`), and lives in a vertical `ScrollView` (`.scrollDisabled(drag != nil)`,
coord space `"layerList"`). The new horizontal swipe must not fight any of them.
- A swipe is *immediate* motion, so it's temporally exclusive from the reorder (which needs a
  0.22s hold first) — that's the main thing that makes this feasible.
- Likely approach: a `DragGesture(minimumDistance: ~15)` (its own gesture), guarded to
  **horizontal-dominant & leftward** (`abs(w) > abs(h) * 1.5 && w < 0`), and **disabled while
  reorder is active** (parent already has `drag != nil`). Beware `.gesture` vs
  `.simultaneousGesture` vs `.highPriorityGesture` ordering — prototype and test:
  1. vertical scroll still works, 2. long-press reorder still works, 3. tap still selects,
  4. the swipe tracks smoothly and only deletes past threshold.
- On-device test is essential (Simulator drag can mislead; haptics are device-only).

### Tests
- Add a pure helper for swipe progress→delete decision (e.g. `shouldDelete(translationWidth:rowWidth:threshold:)`)
  and unit-test it, mirroring `LayerDragMathTests`.
- Keep all new animations gated on `UITestSupport.isRunning` (XCUITest idle). The suite ships no
  swipe UI test by convention; rely on the unit test + on-device check.

### Plan reference
The pre-paused design lives in `~/.claude/plans/quirky-imagining-creek.md` ("Finalize layer drag
work + hand off swipe-to-delete").
