# Handoff — end of 2026-07-05 (LAYERS panel redesign + export SIZE polish)

Covers everything since the `2026-07-03-polish-palette-fix-help-refresh.md` handoff (which still
holds for the palette non-square fix, HELP copy refresh, and HELP landscape fix). `main` =
`origin/main` = tip **`c51df47`**, pushed and in sync. Working tree clean, no loose files at root.
**445 unit + 39 UI tests green** on `iPad Pro 13-inch (M5)`.

## Shipped this session (all on origin/main)

- **Export SIZE tiles subordinate to FORMAT** (`180a4b2`). SIZE row tiles were taller/heavier than
  the FORMAT tiles; now 44pt with a 12pt label so FORMAT reads as the primary choice, SIZE second.

- **LAYERS panel redesign** (`aaaca7d`) — the panel was the last screen still on SF Symbols. Now a
  full custom **pixel-art icon set** (new `extension PixelArtIcon` in `LayersPanel.swift`, 11×11
  `#`/`.` grids), the selected-row highlight moved from a raw `Color.blue` to the app's brand cyan
  (`Color.toolSelected`), the reference section became a distinct **"TRACE" backdrop slab** ("behind
  all layers"), and **swipe-left-on-a-row deletes** a layer (direction/axis-locked so it never
  fights the long-press reorder). Spec + memory: `project_layers_redesign`.

- **Layer row went fully word-based**, over several founder iterations:
  - `37ad807` — visibility eye → **ON/OFF**, lock padlock → **LOCK/OPEN** (interim), TRACE toggle
    matched to ON/OFF.
  - `b435ff5` — rename pencil → **EDIT** text; control order set to **ON/OFF · EDIT · LOCK**; lock
    became **one word, two states** ("LOCK" dark/muted when unlocked, **red `#FF3B30`** =
    `Color.layerLocked` when locked — dropped "OPEN" + its green); the **`+` glyph thinned** from a
    3px-arm plus to a 1px cross (shared by the bottom-bar ADD and the TRACE add-photo button).
    All the eye/lock/pencil pixel patterns were deleted as they became text.

- **Layer-rename (EDIT) flow fixed** (`f34005b`, then `c51df47`). Tapping EDIT swapped the name to a
  `TextField` that never got focus (no cursor/keyboard) and hid EDIT with no way out. Now:
  `@FocusState` + `.onChange(of: isEditingName)` **auto-focuses** the field; a **SAVE** control
  (cyan, `LayerRow-saveName`, replaces EDIT while editing) commits; a shared `commitRename()` also
  fires on Return and on focus-loss (**tap-away saves** instead of abandoning). `c51df47` renamed
  that control DONE → **SAVE** ("SAVE" is the action; "DONE" was just a state).

## Reusable gotchas (carry these)

- **Never query a button by its SF Symbol name in UI tests** (`app.buttons["eye"]`, `["lock.open"]`
  …). A glyph swap erases that identity. Use a stable `.accessibilityIdentifier` + an
  `.accessibilityValue` that flips with state (e.g. `LayerRow-visibility` value "visible"/"hidden").
- **`.submitLabel(.done)` relabels the keyboard's Return key to "Done"**, which breaks any test
  doing `app.keyboards.buttons["Return"].tap()`. Don't use it — `.onSubmit` fires on Return
  regardless of label.
- **Screenshot verification:** an **in-test** `XCTAttachment(screenshot: XCUIScreen.main.screenshot())`
  + `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>` is reliable.
  **External `simctl io booted screenshot` timing is not** — the test tears down before you capture.
  Under a rotated device, `XCUIScreen.main.screenshot()` grabs the raw portrait framebuffer; rotate
  the PNG with `sips -r 270`.
- **"Executed 0 tests" with a matching `-only-testing` filter** = stale DerivedData silently dropped
  an edited test method. `rm -rf ~/Library/Developer/Xcode/DerivedData/DrawBit-*` and rerun. (Now
  documented in CLAUDE.md.)
- **Adding new `PixelArtIcon` patterns as an `extension` in an existing file avoids an xcodegen
  regen** (no new `.swift`).
- **Rotation UI tests must restore portrait in `tearDown`** (from the earlier HELP landscape fix) —
  orientation persists across app launches within a run.

## Still next (queue — re-verify against current code before starting)

- **Cheap polish batch** (see `project_audit_followups` memory): **rename a DRAW** (piece-level —
  distinct from the *layer* rename shipped this session; check whether `Piece.name` has editing UI
  now), **dithering + a color-ramp generator**, **Copy-PNG to clipboard**, **empty-gallery hint**,
  **save-error indicator** (many `try?` swallow disk-full failures).
- **FILM follow-ups** (`project_timelapse`): a DrawBit-FM **audio bed** under the exported clip;
  **multi-frame** process replay (v1 records only the active frame).
- **Reference → editable layer** (foundationed via `ReferenceSampler`): commit the traced photo as a
  real `Layer` (alpha 0/255, structural undo). Only if the founder wants editable photo→pixels.
- **Founder-flagged nits from the layers work** (each a one-line change): the **red LOCK is slightly
  muted on the cyan-selected row** (brighten it, or lift on selection); the **1px `+` is deliberately
  thin** (bump to 2px arms if it reads wispy).
- **Dropped — do NOT re-propose:** PNG import, rectangle tool (both declined 2026-06-29).

## Guiding star (from the founder)

Calm, premium, single-player pixel app that feels like a beautiful machine. This founder **strongly
prefers legible word-labels over icons** for row controls, **iterates fast on live simulator
screenshots** (a `show_widget` mockup did NOT render on their client — show real captures, not
mockups), and prefers plain-language design talk. Judge each item by "does it remove friction from
joyful making." Several "next" items are discuss-first. Verify file/line refs before editing — they
drift.
