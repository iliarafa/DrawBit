# Handoff — Custom color palettes (2026-06-21)

Merged to `main` (no-ff). Feature branch `custom-palettes`, tag `custom-palettes`.
Spec: `docs/superpowers/specs/2026-06-21-custom-palettes-design.md`.

## What shipped

The color picker's GRID tab went from "one hardcoded DB32 grid + an always-on HISTORY
strip" to a calm **palette browser**: one selector + one grid, with full custom-palette
support. The governing constraint (user's words) was *legibility and intuitiveness — never a
bottleneck of visuals/choices*, which drove every layout call below.

### Built-in palettes
- New `BuiltInPalettes` catalog (`DrawBit/Models/BuiltInPalettes.swift`): **DB32, PICO-8,
  SWEETIE 16, GAME BOY** — read-only, stable hardcoded ids so selection survives relaunch.
- DB32's hex moved out of the picker into this catalog → single source of truth. A test
  (`BuiltInPalettesTests`) pins DB32 to the exact legacy colors and validates every hex.

### Custom palettes (global, full management)
- `ColorPalette` value type (`DrawBit/Models/ColorPalette.swift`) + an `[ColorPalette]`
  extension holding all mutation logic (add/delete/rename palette, add/remove color with
  case-insensitive dedupe, `PALETTE N` auto-naming).
- `AppSettings.customPalettes: [ColorPalette] = []` — additive defaulted field; **inferred
  lightweight migration**, no new VersionedSchema. `CustomPalettesMigrationTests` proves an
  old store upgrades to `customPalettes == []` (and confirms SwiftData lightweight-migrates an
  array-of-Codable property — that was the de-risking unknown).
- `AppSettings`'s palette methods now **delegate** to the `[ColorPalette]` extension so the
  picker (which mutates a live `@Binding<[ColorPalette]>`) and persistence share one impl.

### Picker UX — `DrawBit/Views/Editor/DrawBitColorPicker.swift` (layout "B")
- **Default view = two things only:** a selector (palette name + chevron) and the grid.
- **RECENT** is a synthesized read-only palette (from `recentHex`) at the top of the selector
  list — the old always-on HISTORY strip is gone.
- **Inline themed chooser** (NOT a system popover/Menu — those can't be themed; this matches
  the animation-strip custom-popover lesson): tapping the selector replaces the grid area with
  a list of palettes (each with a mini color-strip preview) + a "NEW PALETTE" row.
- **Custom palettes** get one inline affordance — a trailing dashed **"+" tile** to save the
  current color — plus a **pencil** that opens a focused **edit panel** (rename field,
  tap-to-remove swatches, ADD CURRENT, FROM PIECE, DELETE PALETTE). Built-ins/RECENT show none.
- **FROM PIECE** seeds from `PaletteExtractor.colors(in:size:)` (new pure Rendering helper:
  composite the active frame → distinct opaque hexes, first-seen order, capped).

### Wiring — `DrawBit/Views/Editor/EditorView.swift`
- `@State customPalettes` loaded in `.onAppear` from `AppSettings`, passed as a `@Binding` plus
  a `pieceColors` closure; persisted back through `PieceRepository` on `.onChange` (same seam
  as recent colors). Picker stays SwiftData-free.

## Verification
- Full suite green: **314 unit + 25 UI** (was 293 + 24). New: `ColorPaletteTests`,
  `BuiltInPalettesTests`, `AppSettingsPaletteTests`, `PaletteExtractorTests`,
  `CustomPalettesMigrationTests`, and `ColorPaletteUITests` (create → add → switch → delete).
- The effect is visual — worth an eyeball on the Simulator (open a piece → COLOR → GRID).

## Gotchas captured
1. **Spacer-padded SwiftUI Buttons need an explicit `.contentShape(Rectangle())`.** The
   "NEW PALETTE" chooser row had a `Spacer()` and an unfilled (stroke-only) background, so its
   hittable content sat on the left while XCUITest taps the frame center (the empty Spacer) —
   the tap fell through and selected a palette row instead. `.contentShape(Rectangle())` on the
   row label fixed it. Applies to any full-width row button with a Spacer.
2. **SwiftData lightweight-migrates `[ColorPalette]` (array of Codable structs)** as an additive
   defaulted field — proven by `CustomPalettesMigrationTests`, the canary for that assumption.
3. **Built-in palette colors are uppercase, no `#`** (`ColorPalette.colors` convention).
   `RGBA(hex:)` tolerates either, but keep stored hex normalized via
   `ColorPalette.normalizeHex`.

## Possible next steps / ideas
- The OTHER queued task from 2026-06-20 is still open: **share-box format** (redesign the share
  *sheet's* visual layout). Entry point `showingShareSheet` in `EditorView`.
- Judge palettes on real hardware; consider reordering/import of palettes if users ask.
- Loose root files still untracked (`alt_logo.PNG`, `dbit.png`, `share.PNG`) — carried over.
