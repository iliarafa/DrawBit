# Animation strip redesign

**Date:** 2026-05-25
**Status:** Approved design, pre-implementation
**Scope:** `DrawBit/Views/Editor/FramesStrip.swift`, `DrawBit/Views/Editor/FrameRow.swift`, and the frame-action wiring in `DrawBit/Views/Editor/EditorView.swift`. No model, persistence, or rendering changes.

## Why

The animation strip (the bar of frame thumbnails with playback controls) has accumulated friction and is the only chrome in the app still using the system font and filled-pill buttons instead of the app's pixel-font, icon-over-label toolbar style. This redesign fixes seven issues in one coherent pass.

## The seven problems

1. **Speed is a guessing game.** `12 fps` is plain text with no affordance that it's tappable; it only cycles one direction through `[4, 8, 12, 24, 30, 60]`, so 60 → 12 takes five taps and you can't see the other speeds.
2. **Duplicate is hidden and broken.** The flipbook workflow is "draw a frame, duplicate it, nudge, repeat." Duplicate is buried behind EDIT mode, and worse, `onDuplicateFrame` is wired to `addFrameAfterActive` — it adds a *blank* frame, not a copy.
3. **No way to reorder frames.** `onReorderFrame` / `EditorView.reorderFrame` exist and are undoable, but nothing in the UI invokes them.
4. **The onion-skin toggle is a mystery icon.** A plain/half-filled circle doesn't communicate "show the previous frame."
5. **EDIT is a mode.** Tap EDIT to reveal duplicate/delete, do one thing, tap DONE — modes hide tools and cost taps, including the most-used action (duplicate).
6. **Frame names earn little.** Auto-generated `Frame 1…N` adds a text row under every thumbnail, and rename (long-press) is invisible.
7. **Style doesn't match the toolbar.** The strip uses `.caption2` (system font) and filled pills; the rest of the app uses `.pixel(...)` (PressStart2P), uppercase labels, icon-over-label buttons, and monochrome opacity states.

## Design reference: the toolbar

The redesign matches `ToolBar.swift` exactly. Its visual language:

- **Button = icon over label.** `VStack(spacing: 8)` of an SF Symbol at `.font(.system(size: 20, weight: .regular))` over `Text(title.uppercased()).font(.pixel(8))`, framed `minWidth: 44, minHeight: 44`. No background/pill.
- **Monochrome opacity states:** active/emphasis = `Color.white`; inactive = `Color.white.opacity(0.55)`; disabled = `Color.white.opacity(0.25)`.
- **Group dividers:** `Divider().frame(height: 36).overlay(Color.white.opacity(0.15))`.
- **Item spacing:** `HStack(spacing: 22)`.
- **No blue.** The app accent (blue) is not used in the toolbar; the redesigned strip drops it too (decision below).

## Approved decisions

| Topic | Decision |
|---|---|
| Per-frame actions | **Hybrid** — DUPE + ADD are always-visible buttons; RENAME + DELETE live in a long-press context menu (which also offers DUPE). |
| Speed control | **Tap → menu** of `4/8/12/24/30/60`, current one checked. |
| Frame labels | **Number badge in the thumbnail corner.** Custom names show on the thumbnail only when set; no `Frame N` text row. |
| Onion skin | **Stacked-frames icon + "ONION" label**, white when on. |
| Selection / ON color | **Pure monochrome** — no blue. Active frame = white ring + inverted (white-on-black) number badge; ONION-on = white. |
| Duplicate label | **DUPE** |

## The redesigned bar

Left to right, all in the toolbar's icon-over-label pixel style, with `Divider`s separating the three groups:

```
[▶ PLAY] [⏱ 12 FPS] [▦ ONION]  |  «frame thumbnails»  |  [⧉ DUPE] [+ ADD]
```

### Transport group (left)

- **PLAY / PAUSE** — icon `play.fill` / `pause.fill`, label `PLAY` / `PAUSE`. White; disabled (`opacity 0.25`) when `frames.count <= 1`. (Existing `onTogglePlay`.) Monochrome: no red while playing.
- **FPS** — icon `speedometer`, label = the current value, e.g. `12 FPS`. Tapping opens a SwiftUI `Menu` listing `4/8/12/24/30/60 FPS` with a checkmark on the current value; selecting one sets `state.fps` directly. Because it now looks like a button among buttons, the affordance problem is solved without a chevron. Disabled while `state.isPlaying`.
- **ONION** — icon `square.2.layers.3d` (implementer may substitute the nearest available stacked-frames symbol, e.g. `rectangle.stack`), label `ONION`. White when `state.isOnionSkinEnabled`, else `opacity 0.55`. Disabled (`opacity 0.25`) when `state.activeFrameIndex == 0` or `state.isPlaying`. (Existing toggle behavior preserved.)

### Frames group (middle)

Horizontal `ScrollView` of frame thumbnails (unchanged scroll model), disabled during playback.

Each thumbnail:
- ~46pt square, nearest-neighbor pixel preview (existing `FrameThumbnailRenderer`), `interpolation(.none).antialiased(false)`.
- **Number badge** in the top-left corner showing the 1-based display position, `.pixel(7)`. Inactive: white text on `black.opacity(0.7)`. **Active frame:** the badge inverts to black-on-white and the thumbnail gets a 2pt **white** ring (replacing today's blue ring).
- **Custom name overlay** (bottom strip, `.pixel(6)`, white on `black.opacity(0.6)`) shown **only when the frame's name is not an auto-generated `Frame <n>` name** — i.e. suppress display of any name matching `^Frame \d+$`. This keeps the default case clean while surfacing names the user actually set. (No model change; auto-naming on creation stays as-is, it's just not displayed.)

Interactions per frame:
- **Tap** — select the frame (existing `onActivateFrame` → `setActiveFrameAndPersistIfDirty`).
- **Long-press** — lift the frame to **drag-reorder** within the row, or release in place to show a **context menu**: `DUPE` · `RENAME` · `DELETE` (DELETE in destructive red `#e0452a`, disabled when `frames.count <= 1`). This is the iOS home-screen interaction (long-press → hold for menu, or move to drag).
  - `DUPE` → new `duplicateActiveFrame()` (see wiring).
  - `RENAME` → the existing inline-rename `TextField` flow (reused, just triggered from the menu instead of directly from long-press).
  - `DELETE` → existing `deleteActiveFrameWithConfirmIfNeeded()` (already confirms only when the frame has content; already undoable). No new dialog.

### Actions group (right)

- **DUPE** — icon `plus.square.on.square`, label `DUPE`. Calls `duplicateActiveFrame()`. Disabled at `frames.count >= FrameSequence.frameCap`.
- **ADD** — icon `plus`, label `ADD`. Calls existing `addFrameAfterActive()` (blank frame). Disabled at the cap.
- **EDIT / DONE button is removed entirely**, along with `FramesStrip.isEditMode` and the edit-mode-only duplicate/delete buttons.

## Wiring changes (`EditorView.swift`)

1. **Add a real duplicate.** New method:
   ```swift
   func duplicateActiveFrame() {
       let activeID = state.frames[state.activeFrameIndex].id
       mutateFrameSequence { frames in
           if let newID = FrameSequence.duplicateFrame(activeID, in: &frames),
              let idx = frames.firstIndex(where: { $0.id == newID }) {
               state.activeFrameIndex = idx
           }
       }
   }
   ```
   Wire `onDuplicateFrame: duplicateActiveFrame` (currently `addFrameAfterActive`). This is undoable for free via `mutateFrameSequence`.
2. Wire the context-menu DELETE to `deleteActiveFrameWithConfirmIfNeeded` (the strip needs a delete callback that routes here rather than to the raw `deleteActiveFrame`).
3. `onReorderFrame: reorderFrame` is already wired; the strip just needs to actually call it from the drag interaction. `reorderFrame(from:toOffset:)` takes a displayed-from index and an offset; the drag handler computes these.

## Component boundaries

- **`FramesStrip`** owns the three groups, the dividers, the fps `Menu`, and the scroll container. It loses `isEditMode` and the rename `TextField` ownership if that moves into `FrameRow` — keep rename state where it is today (in `FramesStrip`) to minimize churn; the context menu's RENAME action sets `renamingFrameID` as the old long-press did.
- **`FrameRow`** owns one thumbnail: preview, number badge, optional custom-name overlay, white active ring, the `.contextMenu`, and the drag-reorder source/drop. It exposes the same `onTap` plus callbacks for `onDuplicate`, `onRename`, `onDelete`, and a reorder hook.
- No changes below the view layer. `FrameSequence`, `EditorState`, repository, and renderers are untouched (only *called* differently).

## Drag-to-reorder approach (for the plan)

Recommended: `.draggable` / `.dropDestination` (iOS 16+) on each `FrameRow`, computing the target index from the drop. This coexists with `.contextMenu` (iOS disambiguates a drag from a menu long-press). The plan can also consider a long-press `DragGesture` with manual offset math if drag-and-drop proves fiddly inside the horizontal `ScrollView`. Either way it must call `EditorView.reorderFrame(from:toOffset:)` so the move is undoable and persisted.

## Accessibility

Preserve and update existing identifiers/labels:
- `FramesStrip.playPause`, `FramesStrip.fps`, `FramesStrip.onionSkin`, `FramesStrip.add` stay.
- `FramesStrip.duplicate` and `FramesStrip.delete` move out of edit mode: `duplicate` is now always present; `delete` becomes a context-menu action (give the menu items accessibility labels).
- Remove `FramesStrip.editToggle`.
- `FrameRow.<uuid>` stays; add an accessibility value for the position number and custom name; expose DUPE/RENAME/DELETE as accessibility actions on the row so VoiceOver users don't need the long-press menu.
- All buttons keep the 44pt minimum hit target (inherited from the toolbar's `minWidth/minHeight: 44`).

## Out of scope (YAGNI)

- Per-frame duration / variable timing (speed stays global).
- Timeline scrubbing.
- Onion-skin range options (previous-only is kept; no prev+next, no opacity control).
- Keeping a red "recording" tint on PAUSE (cut for pure monochrome; can revisit if it reads as dead).

## Verification

- Existing unit tests for `FrameSequence` (duplicate/move/remove/setName) already cover the model layer; no new model tests needed.
- Add/extend UI tests: DUPE produces a copy (not a blank), long-press menu shows DUPE/RENAME/DELETE, DELETE on a content frame confirms, reorder changes order and is undoable, fps menu sets a non-adjacent value in one tap.
- Manual: confirm the strip reads as the same visual family as the toolbar (font, casing, icon weight, dividers, monochrome states) at the iPad Pro 13" simulator.
- Build + full test run per `CLAUDE.md` before merge.
