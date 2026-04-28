# App icon: BITME wordmark, light/dark variants

**Date:** 2026-04-20
**Status:** Approved design, ready for implementation plan.

## Summary

Ship an app icon built from the Press Start 2P wordmark "BITME". Two variants bundled via the asset catalog's appearance system: black-on-white for light mode, white-on-black for dark mode. iOS 18 auto-switches based on system appearance.

## Motivation

The app currently has no custom icon — iOS shows the generic placeholder. The landing screen already establishes a BITME wordmark in Press Start 2P; the Springboard icon should match that mark so the brand reads end-to-end.

## Non-goals

- Illustrated marks or sprites (no paintbrush, palette, or scene).
- iOS 18 "tinted" icon variant (can be added later if desired).
- macOS / iMessage / watchOS icons.
- Animated icons or icon-composer 3D layers.

## Artwork

- Canvas: 1024×1024 PNG, no transparency. iOS applies its own squircle mask.
- Wordmark: "BITME" (uppercase), Press Start 2P, single line, centered.
- Sizing: font size picked so the rendered glyph run occupies ~80% of the canvas width, leaving equal left/right margins and a comfortable top/bottom margin inside the iOS icon safe area.
- Light variant: white `#FFFFFF` background, black `#000000` text.
- Dark variant: black `#000000` background, white `#FFFFFF` text.

## Generation

A single Swift script `scripts/generate_app_icon.swift` renders both PNGs. The script is a repo-level build tool — not compiled into the app target.

- Loads `DrawBit/Resources/Fonts/PressStart2P-Regular.ttf` via `CTFontManagerCreateFontDescriptorFromData`.
- Creates a 1024×1024 `CGContext` (sRGB, `.premultipliedLast`).
- Computes the font size so the typeset run for "BITME" at that size measures ~80% of 1024 wide (binary search or direct ratio — Press Start 2P is monospace, so `advance × 5` scales linearly with font size; closed-form is fine).
- Fills the background, draws the text centered vertically and horizontally, no anti-aliasing (`setShouldAntialias(false)`, `setAllowsAntialiasing(false)`, `setShouldSubpixelQuantizeFonts(false)`) to preserve the crisp pixel look.
- Writes PNG via `CGImageDestination`.
- CLI: `swift scripts/generate_app_icon.swift <output-path> [--dark]`. Flag inverts fg/bg.

Script stays in the repo so the wordmark can be regenerated if text, size, or margins ever change. Running `swift` uses the Xcode-bundled toolchain — no new tool dependency.

## Asset catalog and build wiring

New asset catalog `DrawBit/Assets.xcassets/`:

```
DrawBit/Assets.xcassets/
├── Contents.json              # catalog root, default
└── AppIcon.appiconset/
    ├── Contents.json          # icon set manifest
    ├── AppIcon-Light.png
    └── AppIcon-Dark.png
```

`AppIcon.appiconset/Contents.json` uses the single-size (Xcode 14+) form with two appearance variants:

```json
{
  "images": [
    {
      "filename": "AppIcon-Light.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    },
    {
      "appearances": [
        { "appearance": "luminosity", "value": "dark" }
      ],
      "filename": "AppIcon-Dark.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

`project.yml` changes (DrawBit target):

- `settings.base` gains `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` so asset compilation wires the icon properly.
- `info.properties` gains `CFBundleIconName: AppIcon` — iOS uses this to locate the compiled icon.
- Asset catalog is picked up automatically because `sources: [path: DrawBit]` globs it.

## Testing

- **Unit** `DrawBitTests/Views/AppIconTests.swift`:
  - `testAppIconCatalogHasLightVariant`: `UIImage(named: "AppIcon")` resolves non-nil in a `UITraitCollection(userInterfaceStyle: .light)` context.
  - `testAppIconCatalogHasDarkVariant`: same, `.dark`.
- **No UI test** — the icon renders in Springboard, outside any XCUI-addressable surface.
- **Manual check** after building on the simulator: home screen shows the BITME icon; toggling the simulator's Light/Dark appearance flips the variant.

## Files touched

New:

- `scripts/generate_app_icon.swift`
- `DrawBit/Assets.xcassets/Contents.json`
- `DrawBit/Assets.xcassets/AppIcon.appiconset/Contents.json`
- `DrawBit/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png`
- `DrawBit/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png`
- `DrawBitTests/Views/AppIconTests.swift`

Modified:

- `project.yml` — add `ASSETCATALOG_COMPILER_APPICON_NAME` and `CFBundleIconName`.

## Invariants preserved

- Pure-logic layers untouched — icon generation lives in a script outside the app target.
- No dependency added to the app (the Swift script is a dev-time tool invoked manually).
- No existing view, test, or font wiring is modified.

## Risks

- **PNG determinism**: the Swift script's output needs to be byte-stable or committed diffs will churn. Mitigation: PNGs are re-committed only when the script or wordmark actually changes; the script writes a solid-color canvas with CoreGraphics, which is deterministic on the same machine.
- **Catalog variant compatibility**: appearance variants in icon sets require Xcode 14+ / iOS 13+; deployment target is iOS 17, so supported.
- **Background alpha**: iOS rejects app icons with transparency in App Store submission. The script writes a fully opaque background color; no alpha.
