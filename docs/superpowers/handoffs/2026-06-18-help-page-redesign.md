# Handoff — HELP page redesign + chrome polish (2026-06-18)

## Pending idea to try next
**Use the page's solid background color as the instruction-box background, in BOTH states (collapsed tile and expanded full-row).**
- Today the tiles use `Color(white: 0.07)` while the page background is `Color(white: 0.10)`
  (see `DrawBit/Views/Gallery/HelpScreen.swift` — `collapsedTile` and `expandedTile`
  `.background(Color(white: 0.07))`, and `body`'s `.background(Color(white: 0.10))`).
- Try setting both tile backgrounds to `Color(white: 0.10)` (match the page) so the boxes
  blend into the background and are defined only by their thin border (and the cyan accent
  border when expanded). Judge on the sim whether the borderless/seamless look reads better
  than the current slightly-darker cards.

## What shipped this session (HELP page + related chrome)
All on `main` except the work in this commit. Key file: `DrawBit/Views/Gallery/HelpScreen.swift`.

- **Layout**: 6 topics as a 2-column `Grid` of compact icon+title tiles (fixed height 176,
  `rowGap` 16), HELP title moved down + vertically centered, hint line, version footer.
- **Interaction**: tap a tile → it spans the full row (`gridCellColumns(2)`) showing only the
  instructions; tap again / another to collapse/switch. Single-selection (`expanded: String?`).
- **Pixel-dissolve transition** (`AnyTransition.openDissolve` + `PixelDissolve` shape +
  `PixelDissolveModifier`): the expanded box assembles from ~14pt pixel blocks on **open**
  (`.easeOut(0.55)`); **close/switch is an instant cut** (asymmetric: `removal: .identity`,
  collapsed tiles use `.transition(.identity)`). Gated off under UI test.
  - NOTE: an offset-overlay approach was tried first but only rendered on the top row
    (SwiftUI offset+transition quirk) — the working version uses the in-Grid `gridCellColumns`
    structure with the transition on the tiles.
- **Body font**: bundled `VT323-Regular.ttf` (OFL) → `Resources/Fonts/`, registered in
  `project.yml` `UIAppFonts`, exposed via `Font.pixelBody(_:)` in `PixelFont.swift`. Used at
  `pixelBody(20)` for the instruction body ONLY; titles/chrome stay Press Start 2P.
- **Icons** (all reuse the editor's real sprites / pixel art for consistency):
  - ANIMATION → `PixelArtIcon.playTriangle` (shared from the editor).
  - DRAWBIT FM → `eighthNotes` pixel sprite (♫). FM tile is bottom-RIGHT of the gallery.
  - CANVAS → `gridLines` pixel sprite (3×3 slightly-uneven crossing lines; replaced the
    keypad-like `square.grid.3x3`).
  - LAYERS → `Image("LayersIcon")` (the editor's layers sprite, via new `HelpIcon.asset`).
  - EXPORT → `ShareGlyph` (the editor's share glyph; made `internal` in `EditorView.swift`
    so HelpScreen can reuse it, via new `HelpIcon.shareGlyph`).
  - Per-icon render sizes in `icon(_:tinted:)` so LAYERS/EXPORT/FM (which carry internal
    margin) match the visual size of TOOLS/CANVAS/ANIMATION.
- **Copy**: TOOLS mentions Mirror (symmetry across the vertical centre); ANIMATION explains
  onion skin + FPS choices (4,8,12,24,30,60); DRAWBIT FM = "original music … bottom-right".
  Instruction text is left-aligned.
- **Unrelated fix folded in earlier**: `ShareSheet.ExportFormat.apng` button label was "MP4"
  but exports an APNG → renamed to "APNG".

## Verification
- Build: `xcodebuild -project DrawBit.xcodeproj -scheme DrawBit -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build`
- `xcodebuild … test -only-testing:DrawBitUITests/HelpScreenUITests` — 3 tests, green. The
  six `Help.section.*` title ids stay on the collapsed tiles' `Text` (queryable as
  `staticTexts`); the dissolve is disabled under UI test.
- Animations aren't observable in static simulator screenshots — judge motion on-device.

## Gotchas
- A new `.swift` or resource file requires `rm -rf DrawBit.xcodeproj && xcodegen generate`
  (the VT323 font addition already did this). `DrawBit.xcodeproj` is gitignored.
- `Font.custom("VT323-Regular", …)` resolved correctly on iOS 26.5; fall back to `"VT323"` if
  it ever renders as the system font.
