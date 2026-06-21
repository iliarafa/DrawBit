# 2026-06-15 — Toolbar polish, symmetry brush, odd canvas sizes

All work below shipped to `main`. Five commits, two pushes, full test suite green between each (293 unit + 24 UI tests).

## 1. Layers drag-to-reorder, no edit mode (`babbce0`)

The Layers panel required tapping **EDIT** before drag-handles appeared. Replaced that with direct drag-by-thumbnail.

- **`LayerRow.swift`** — `.draggable("\(displayIndex)")` on the thumbnail (the visual grip), `.dropDestination(for: String.self)` on the entire row (so the user doesn't have to release precisely on the 32-pt thumbnail). Long-press-to-rename on the layer name was removed because SwiftUI's `.draggable` blocks sibling `.onLongPressGesture` throughout the row tree — replaced with an inline **pencil button** next to eye/lock. Added VoiceOver `Move up` / `Move down` / `Rename` actions for accessibility.
- **`LayersPanel.swift`** — Dropped the `editMode` state and the EDIT/DONE button. **Switched `List` → `ScrollView + LazyVStack`**: `List` cells swallow row-level `.dropDestination` events (pick-up worked but drop never fired), matching the FramesStrip's already-proven `ScrollView` pattern. New `performMove(displayFrom:displayTo:)` converts display indices (reversed layer order) to model indices.
- **`LayersPanelUITests.swift`** — Existing rename test now taps the pencil button; new `testReorderHasNoEditModeGate` guards against the EDIT button being re-added.

### Debugging trail worth remembering

The drop wasn't firing initially because `.dropDestination` was localized to the 32-pt thumbnail (an attempt to avoid the long-press gesture conflict with inline rename). Moving it to the whole row didn't help by itself — the **List itself eats row-level drops**. The fix was the ScrollView+LazyVStack swap.

## 2. Share icon — two-step replacement

### 2a. Un-squish the pixel pattern (`ca580fd`)

The hardcoded 11×11 `shareIcon` pattern in `EditorView.swift` had a 9×6 box (3:2 ratio) that read as visually compressed next to the 9×9 play triangle. Trimmed one row of arrow shaft and shifted the box up → 9×7 box, ~1.29:1.

### 2b. Replace pixel sprite with image asset (`f0a61d7`)

The user supplied a higher-detail `share.png`. Wired in as a proper asset alongside the existing LayersIcon pattern.

- **`DrawBit/Assets.xcassets/ShareIcon.imageset/`** — `share_sprite.png` (864×864), cropped tight to the glyph (no transparent padding). `Contents.json` matches `LayersIcon.imageset`: `template-rendering-intent: template` so the toolbar tint applies.
- **`EditorView.swift`** — SHARE button now uses `Image("ShareIcon")` with `.aspectRatio(contentMode: .fit)` and a **30-pt inner frame** (vs the 22-pt used by LAYERS/ANIMATE). The asset is finer-detail pixel art than the 11×11 pattern icons, so at 22 pt its strokes go sub-point and read as blurry; 30 pt brings strokes back to ~1 pt. LAYERS bumped to 26 pt for proportional consistency. Dead `shareIcon` pixel-pattern constant deleted.

## 3. App icon (`4c14e2c`)

Two source files were dropped in: `dbit.png` (595×600) and then `alt_logo.png` (1024×1024). Final shipped icon is `alt_logo` centered on a black 1024×1024 with ~10% padding on each side (820-pt logo at offset 102). Nearest-neighbor resize preserves pixel-art edges. Light and dark slots share the same artwork.

The intermediate `dbit.png` icon also rendered correctly (padded to square, nearest-neighbor up to 1024×1024) — pattern documented below for future swaps.

## 4. Symmetry mirror brush + odd canvas sizes (`c72f89c`)

The user observed that even-numbered grids (16×16, 32×32) have no true center column — the geometric centerline sits between columns — making symmetric pixel art surprisingly awkward. Two complementary fixes:

### Mirror toggle

- **`EditorState.swift`** — `var isMirrorEnabled: Bool = false` (session-only, not persisted).
- **`ToolBar.swift`** — MIRROR button (SF Symbol `arrow.left.and.right`) next to the tools. Active tint matches the FramesStrip's ONION pattern (full white when on, 0.55 when off). `accessibilityIdentifier("Mirror")`.
- **`EditorView.swift`** — In `applyDrawPoint`, compute `let mx = state.size.dimension - 1 - x` and skip the mirror call when `mx == x` (odd-grid center column). For pencil/eraser/fill, mirror the call inside the **same** `mutateActiveLayerPixels` closure so undo collapses the mirrored pair into one step. For colorSwap, sample the mirror color **before** mutating the grid (otherwise the second sample sees post-swap pixels). Eyedropper and marquee intentionally untouched.

### Odd canvas sizes (15 / 31 / 63)

- **`CanvasSize.swift`** — Added cases `.s15`, `.s31`, `.s63`. Interleaved with even sizes so the picker reads small-to-large: `15, 16, 31, 32, 63, 64, 128`.
- **`NewPieceSheet.swift`** — No change needed (it iterates `CanvasSize.allCases`).
- **`ShareSheet.swift`** — Exhaustive switches on `CanvasSize` updated. Odd sizes share scale tables with their even neighbor (15→16, 31→32, 63→64); output edges land within a few % of the 128/256/512/1024/2048 px target, well inside the platform-resize tolerance that motivated the 1024-px-plus default.
- **`GalleryView.swift`** — `NewPieceSheet` detent bumped from `.medium` (cropped the 7-row list) to `.height(420)` (tight against the 128×128 row, no dead space).
- **`CanvasSizeTests.swift`** — `testAllCasesExist` and `testDimensionMatchesRaw` updated for the new cases. `SingleFrameNonRegressionTests` iterates `allCases` agnostically and just exercises the new sizes for free.

### Why both, not just one

- Mirror works on existing pieces and any future even-grid presets.
- Odd sizes are the right primitive for users who want a true center pixel from the start without needing a mirror.

## 5. Misc / supporting changes

- **`SingleFrameNonRegressionTests`** — already iterated `CanvasSize.allCases` agnostically; passed unchanged for the new sizes.
- **No regressions** — full test suite (293 unit + 24 UI tests) green after each commit.

## Non-obvious gotchas captured this session

1. **SwiftUI `List` swallows row-level `.dropDestination`.** Use `ScrollView + LazyVStack` for drag-and-drop reorder lists (the FramesStrip pattern).
2. **`.draggable` blocks sibling `.onLongPressGesture` throughout the row tree.** Even moving `.draggable` to the thumbnail only doesn't help. The fix: replace any long-press gesture with a tap on a dedicated control (pencil button), or use `.contextMenu` which uses its own gesture mechanism (but draws system chrome that fights the app's aesthetic).
3. **Pixel-art image assets need explicit nearest-neighbor scaling.** Both Python's PIL (`Image.NEAREST`) and SwiftUI's `Image` modifiers (`.interpolation(.none).antialiased(false)`) are required. `sips` defaults to bilinear.
4. **Asset visual size = (fill ratio × inner frame size).** Two assets at the same `.frame(width: 22, height: 22)` can look very differently sized if one is content-tight (~100% fill) and the other has padding baked in (~80% fill). For new sprites, mirror the LayersIcon `Contents.json` pattern: `template-rendering-intent: template`, content cropped tight.
5. **Sheet detents matter more than the content's natural height.** SwiftUI doesn't auto-size sheets to content; an explicit `.height(N)` gets the cleanest result. `Spacer(minLength: 0)` inside the sheet's content will fill any leftover vertical space, creating a dead gap if the detent is too tall.

## Pattern: dropping a new logo asset for the app icon

```python
# Crop to alpha bbox, pad to square (for transparent PNGs) or
# add black padding for solid-bg sources. Always NEAREST.
from PIL import Image
src = Image.open("source.png").convert("RGB")
w, h = src.size
side = max(w, h)
square = Image.new("RGB", (side, side), (0, 0, 0))
square.paste(src, ((side - w) // 2, (side - h) // 2))
icon = square.resize((1024, 1024), Image.NEAREST)
icon.save("DrawBit/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png", "PNG")
icon.save("DrawBit/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png", "PNG")
```

## Files touched

| File | Touched in |
|---|---|
| `DrawBit/Views/Editor/LayerRow.swift` | Layers reorder |
| `DrawBit/Views/Editor/LayersPanel.swift` | Layers reorder |
| `DrawBitUITests/LayersPanelUITests.swift` | Layers reorder |
| `DrawBit/Views/Editor/EditorView.swift` | Share icon (twice), LAYERS resize, mirror dispatch |
| `DrawBit/Assets.xcassets/ShareIcon.imageset/` | New asset |
| `DrawBit/Assets.xcassets/AppIcon.appiconset/` | New icon (×2 iterations) |
| `DrawBit/State/EditorState.swift` | Mirror state |
| `DrawBit/Models/CanvasSize.swift` | Odd sizes |
| `DrawBit/Views/Editor/ToolBar.swift` | MIRROR button |
| `DrawBit/Views/Editor/ShareSheet.swift` | Exhaustive switch updates for odd sizes |
| `DrawBit/Views/Gallery/GalleryView.swift` | NewPiece detent height |
| `DrawBitTests/Models/CanvasSizeTests.swift` | Test updates for odd sizes |

## Commits

1. `babbce0` — feat(layers): drag-to-reorder by thumbnail handle, no edit mode
2. `ca580fd` — fix(toolbar): un-squish the share icon's box
3. `4c14e2c` — chore(icon): swap in alt logo as the app icon
4. `f0a61d7` — feat(toolbar): replace share pixel sprite with image asset, resize icons
5. `c72f89c` — feat(symmetry): mirror brush + odd canvas sizes
