# Landing page and app-wide pixel font

**Date:** 2026-04-20
**Status:** Approved design, ready for implementation plan.

## Summary

Add an arcade-style landing page as the app's root screen, and apply Press Start 2P as the display font across the app's chrome (titles, buttons, labels). Input surfaces (alerts, text fields) keep the system font for legibility.

## Motivation

The app currently opens directly into the piece gallery, with no moment of product identity. A landing page with the "BITME" wordmark establishes character on cold launch and gives returning users a familiar "home" they can get back to from the gallery. The pixel font reinforces the app's domain (pixel art) in the chrome itself.

## Non-goals

- Sound effects, animations beyond a single blinking "PRESS START".
- Pixel-art sprites, scenery, or gradient backgrounds on the landing page.
- Applying the pixel font to alerts, text-field input, or any place where Dynamic Type matters.
- Changing the editor's drawing canvas, rendering, or tools.

## Navigation model

A new `RootView` replaces `GalleryView()` as the `WindowGroup` root. It holds a single piece of state:

```swift
enum Screen { case landing, gallery }
@State private var screen: Screen = .landing
```

- `.landing` renders `LandingView`. Tapping the screen sets `screen = .gallery`.
- `.gallery` renders `GalleryView`, with a new leading home-icon toolbar button that sets `screen = .landing`.

`GalleryView` keeps its own internal `NavigationStack` for `Editor` pushes, rename alerts, and confirmation dialogs — nothing inside it changes behaviorally. No nested `NavigationStack`s are introduced.

**Rejected alternatives:**

- Single root `NavigationStack` with Landing as root and Gallery pushed on top: awkward because Gallery already owns its own stack for Editor, and a nested stack would complicate existing sheet/alert wiring.
- `.fullScreenCover` from Landing to Gallery: the slide-up animation reads as a modal, not a title-screen-to-menu transition.

## Landing page (`LandingView`)

New file `DrawBit/Views/Landing/LandingView.swift`.

- Full-screen black background (`Color.black.ignoresSafeArea()`).
- Status bar hidden.
- "BITME" wordmark, centered, `Font.pixel(72)`, white.
- Below the title, "PRESS START" at `Font.pixel(18)`, white, blinking: opacity alternates 1.0 ↔ 0.0 with `withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true))`.
- Whole screen is a tap target (`.contentShape(Rectangle()).onTapGesture`) — no visible button chrome. Classic "insert coin" pattern.
- `accessibilityIdentifier("LandingStart")` and `accessibilityLabel("Start")` on the tap target for VoiceOver and UI tests.

## Font infrastructure

- Add `DrawBit/Resources/Fonts/PressStart2P-Regular.ttf` (Google Fonts, SIL Open Font License 1.1 — redistributable).
- Register in the generated Info.plist by adding to `project.yml`:
  ```yaml
  INFOPLIST_KEY_UIAppFonts: "PressStart2P-Regular.ttf"
  ```
  xcodegen forwards this into the generated plist as a `UIAppFonts` array.
- New file `DrawBit/Views/Support/PixelFont.swift`:
  ```swift
  extension Font {
      static func pixel(_ size: CGFloat) -> Font {
          .custom("PressStart2P-Regular", size: size)
      }
  }
  ```
- Call sites use `.font(.pixel(size))`. No `UIAppearance` swizzling — SwiftUI's appearance proxy is unreliable, and Press Start 2P's baseline metrics require per-site tuning anyway.
- Sizes are fixed (no Dynamic Type). Press Start 2P is a pixel-grid font; scaling breaks its crispness. Alerts and `TextField` keep the system font and continue to honor Dynamic Type.

## Font-application scope

- **LandingView**: "BITME" at 72pt, "PRESS START" at 18pt.
- **GalleryView**:
  - Replace `.navigationTitle("Pieces")` with a custom inline title "BITME" at `Font.pixel(20)`.
  - Leading toolbar item: `Button { screen = .landing }` with SF Symbol `house.fill`, `accessibilityIdentifier("HomeButton")`.
  - `ContentUnavailableView` replaced by a hand-rolled empty state: "NO PIECES YET" at 16pt + "Tap + New to create your first canvas." at 11pt. (`ContentUnavailableView` doesn't expose its internal `Text`s for font overrides.)
  - `PieceThumbnailView` name label at `Font.pixel(10)`.
- **NewPieceSheet**: section header and size-option labels at `Font.pixel(14)`.
- **EditorView / ToolBar**: any visible text labels (size indicators, zoom readout, export sheet section headers and option rows) at `Font.pixel(11–14)` as appropriate per element. Tool glyphs are SF Symbols and unaffected.
- **Alerts (`rename`, `delete` confirmation), `TextField` in alert**: unchanged — system font.

## Testing

### Unit

- `PixelFontTests.testPixelFontIsRegistered`: asserts `UIFont(name: "PressStart2P-Regular", size: 12)` is non-nil. Catches a missing or misnamed font file before it ships to TestFlight.

### UI

New file `DrawBitUITests/LandingScreenTests.swift`:

- `testStartTapEntersGallery`: launch → tap `LandingStart` → assert `NewButton` exists.
- `testHomeIconReturnsToLanding`: launch → tap `LandingStart` → tap `HomeButton` → assert `LandingStart` exists again.

### Existing tests

- Existing `testCreateDrawReopen` (and other UI tests that assume the app starts on the gallery) must not regress. Add a launch argument `-UITest-skipLanding` recognized in `DrawBitApp` (or `RootView`) that sets the initial `screen` to `.gallery`. Existing tests pass this argument; the two new landing tests do not. This keeps existing tests focused on what they actually test.

## Files touched

New:

- `DrawBit/Views/Landing/LandingView.swift`
- `DrawBit/Views/Support/PixelFont.swift`
- `DrawBit/Views/Support/RootView.swift` (wraps landing/gallery switch)
- `DrawBit/Resources/Fonts/PressStart2P-Regular.ttf`
- `DrawBitTests/Views/PixelFontTests.swift`
- `DrawBitUITests/LandingScreenTests.swift`

Modified:

- `DrawBit/DrawBitApp.swift` — root becomes `RootView()`; reads `-UITest-skipLanding` arg alongside existing `-UITest-reset`.
- `DrawBit/Views/Gallery/GalleryView.swift` — custom nav title, leading home button, replaced empty-state view, pixel-font on thumbnail name.
- `DrawBit/Views/Gallery/NewPieceSheet.swift` — pixel font on labels.
- `DrawBit/Views/Gallery/PieceThumbnailView.swift` — pixel font on name label.
- `DrawBit/Views/Editor/ToolBar.swift` — pixel font on visible text (if any).
- `DrawBit/Views/Editor/EditorView.swift` — pixel font on title/zoom/size readouts.
- Export sheet view — pixel font on headers/labels.
- `project.yml` — add `INFOPLIST_KEY_UIAppFonts`.
- `DrawBitUITests/*Tests.swift` (existing) — launch with `-UITest-skipLanding`.

## Invariants preserved

- Pure-logic layers (`Drawing/`, `Rendering/`) are untouched. No new imports into those folders.
- `PieceRepository` remains the only SwiftData seam.
- `EditorState` is not persisted; the landing/gallery switch is UI state only.
- Exported PNGs and thumbnails are unaffected — canvas rendering does not read chrome fonts.

## Risks

- **Font licensing**: Press Start 2P ships under SIL OFL 1.1. Bundle the `OFL.txt` license next to the `.ttf` and keep its copyright notice intact. No attribution required in-app, but the license file must be redistributed.
- **Font file size**: ~26 KB. Negligible.
- **Rendering at odd sizes**: Press Start 2P is designed for 8px grid alignment; at sizes that aren't multiples of 4 the hinting can look uneven. The sizes above (10, 11, 14, 16, 18, 20, 72) are either in-grid or large enough that the issue disappears.
- **UI test flakiness**: the blinking "PRESS START" is an animation loop. Tests tap `LandingStart` (the full-screen tap target), not the text, so opacity state doesn't matter.
