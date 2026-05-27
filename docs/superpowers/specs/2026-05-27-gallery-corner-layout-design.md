# Gallery Corner Layout

## Context

After promoting DrawBit FM into a dedicated destination (see
`2026-05-25-drawbit-fm-design.md` and the follow-up that placed the FM tile at
grid position 0), the gallery still had a single content area that mixed three
concerns in one grid: the **new-piece action**, the **FM station entry**, and
the **piece thumbnails**. That works, but the FM tile competed with pieces for
top-row attention, and the new-piece tile sat at the *end* of the grid where
new users had to look for it.

This change reshuffles the gallery so the two action surfaces live at
fixed corner positions and the grid is reserved for pieces:

- **Top-left of the grid:** the **new-piece** tile (position 0 of the
  `LazyVGrid`, before the piece `ForEach`).
- **Bottom-left of the screen:** the **DrawBit FM** tile as a **fixed
  overlay** pinned above the safe area — always visible regardless of
  grid scroll position.

Pieces flow naturally from position 1 of the grid onward, sorted by
`updatedAt` descending as today.

## Design

**GalleryView (`DrawBit/Views/Gallery/GalleryView.swift`)** is the only
file that changes:

1. Inside the `LazyVGrid`, the FM tile is removed. `NewPieceTile()` moves
   from the end of the grid to position 0 (before `ForEach(pieces)`).
2. The `VStack` containing the header + scroll view gains an
   `.overlay(alignment: .bottomLeading) { ... }` that hosts the FM tile.
   The overlay applies:
   - A fixed `.frame(width: 120, height: 120)` so the floating tile
     visually matches a grid cell.
   - `.padding(.leading, 20)` (matches the grid's horizontal padding so
     the FM tile aligns with the leftmost grid column).
   - `.padding(.bottom, 24)` (matches the grid's bottom padding so the
     tile sits above the safe area at a familiar offset).
   - `.onTapGesture { showingFM = true }` to push `FMScreen` exactly as
     before.

**FMTile and FMScreen are not modified.** The same `FMTile()` view is
used in the overlay — its `.aspectRatio(1, contentMode: .fit)` plays
nicely with a fixed square `.frame`. Inline play/pause still toggles
playback without navigating; tapping the body still pushes the
destination. The push-navigation wiring (`.navigationDestination(isPresented:
$showingFM)`) is unchanged.

## Trade-off

The FM overlay sits *on top* of the scrolling grid. With small
galleries (today's screenshot: 3 pieces) there is no overlap. With dense
galleries, scrolling will pass piece thumbnails behind the FM tile,
which occludes a roughly 120pt square at the bottom-left of the viewport.
The piece is still tappable above and below the FM tile; only the
visible thumbnail is partially hidden. Acceptable given the design
goal of permanent FM presence; called out so future maintainers know
the choice was deliberate.

## Verification

- All existing FM tests pass unchanged. `FMTileUITests` queries
  `staticTexts["DRAWBIT FM"]` and `buttons["FM.tile.playPause"]` — both
  still present (the tile is the same view, just hosted in an overlay).
  `FMScreenUITests` queries elements on the pushed destination — same
  push wiring.
- Manual smoke: launch the app, confirm the gallery shows the
  new-piece tile (`+`) at the top-left and the FM tile floating at the
  bottom-left. Tap the inline play/pause to confirm it still works in
  place. Tap the tile body to confirm the FM screen still pushes. Open
  a piece from the grid to confirm Editor navigation is untouched.

## Out of scope

- No copy changes on the FM tile.
- No new accessibility behaviour beyond what the existing tile provides.
- No change to the editor or any other view.
