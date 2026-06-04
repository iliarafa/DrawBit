# DrawBit

A native iPad pixel-art studio: draw on fixed-size canvases with layers, build frame-by-frame animations, listen to a built-in ambient-music station while you work, and export PNGs, animated GIF/APNG, or sprite sheets. Fully offline, no accounts.

## Features

- **Four canvas sizes:** 16×16, 32×32, 64×64, 128×128.
- **Six tools:** pencil, eraser, fill bucket, eyedropper, color swap (recolor one color across the active layer), and a rectangular marquee for select / cut / move.
- **Layers:** up to 16 per frame — add, duplicate, delete, reorder (drag), rename, plus per-layer visibility and lock. Composited with straight-alpha.
- **Reference photo (tracing):** attach one photo per piece, shown dimmed and smooth behind the canvas to trace over on a new layer. Display-only — never composited or exported. Adjustable fade, show/hide, and add / replace / remove from the Layers panel.
- **Frame-by-frame animation:** up to 60 frames with a timeline strip — add blank/duplicate frames, reorder, rename, delete, scrub, and play back at 4 / 8 / 12 / 24 / 30 / 60 fps with optional onion-skinning.
- **DrawBit FM:** a built-in looping ambient-music station pinned to the gallery footer (play / pause / next / previous), with background-audio playback so it keeps going across navigation.
- **Color picker + recent colors:** full-spectrum picker with a recent-colors palette (last 23).
- **Gallery-first UI:** thumbnails of your pieces; tap to edit, long-press for Rename / Duplicate / Delete.
- **Procreate-style canvas transform:** two-finger pan + pinch-zoom + rotation (scale clamped to 0.25×–40×, rotation snaps to 0° within ~4°, two-finger double-tap resets).
- **Apple Pencil aware:** when a Pencil is detected, finger input pans/zooms and only the Pencil draws. Without a Pencil, finger draws.
- **Pixel-perfect rendering:** nearest-neighbor interpolation everywhere (editor, thumbnails, export). sRGB end-to-end. No anti-aliasing.
- **Export & share:** PNG, animated GIF, Animated PNG (APNG), or sprite sheet; scale picker (1× / 2× / 4× / 8× / 16×) with size-appropriate defaults; save to Photos or the share sheet.
- **Local storage:** SwiftData, fully offline, no accounts.
- **Up to 50 undo/redo steps** per editing session (frame-sequence structural edits capped at 10).

## Platform

- **iPadOS 17+**, iPad-only (no iPhone layout, no Mac Catalyst).
- Swift 5.10, SwiftUI, SwiftData, CoreGraphics + ImageIO (rendering & export), AVFoundation + MediaPlayer (DrawBit FM), PhotosUI (reference-photo import), UIKit (coalesced touches, gesture recognizers).
- Background-audio mode enabled (`UIBackgroundModes: [audio]`) for the FM station.
- No external dependencies; no Swift Package Manager manifest.

## Repo layout

```
DrawBit/                              # App target — 64 Swift files
  DrawBitApp.swift                    # @main SwiftUI App, ModelContainer
  Models/                           # SwiftData + value types: Piece, AppSettings,
                                    #   CanvasSize, Tool, DrawBitSchema (migration plan)
  Drawing/                          # Pure logic: PixelGrid, Pencil, Eraser, Fill,
                                    #   Eyedropper, ColorSwap, Marquee, BresenhamLine,
                                    #   PixelPerfectStroke, PixelRect, Layer, Frame,
                                    #   FrameSequence, FrameCodec
  Rendering/                        # CoreGraphics/ImageIO: PixelsToCGImage, Compositor,
                                    #   ThumbnailRenderer, Frame/LayerThumbnailRenderer,
                                    #   PNGExporter, GIFExporter, APNGExporter,
                                    #   SpriteSheetExporter, ReferenceImageProcessor
  Audio/                            # DrawBit FM core: AudioTrack, Playlist, BundledTracks
  Gestures/                         # CanvasHostView (UIKit input + transform), PencilAvailability
  Persistence/                      # PieceRepository (wraps ModelContext), StoreRecovery
  State/                            # EditorState (undo/redo, transform), PlaybackController,
                                    #   RadioController
  Views/
    Gallery/                        # GalleryView, PieceThumbnailView, New/Rename/Delete
                                    #   sheets, FMTile + FMScreen + ScrubBar, HelpScreen
    Editor/                         # EditorView, CanvasView, ToolBar, RecentColorsStrip,
                                    #   DrawBitColorPicker, LayersPanel, LayerRow,
                                    #   ReferenceRow, FramesStrip, FrameRow, ShareSheet
    Landing/                        # LandingView (PRESS START)
    Support/                        # RootView, PixelFont
  Resources/
    Fonts/                          # PressStart2P-Regular.ttf
    fm/                             # bundled DrawBit FM tracks (.mp3)

DrawBitTests/                         # 293 unit tests across 53 files
DrawBitUITests/                       # 23 UI tests across 8 files (landing, gallery
                                    #   happy-path, layers panel, animation strip,
                                    #   FM tile + FM screen, help, reference photo)

docs/superpowers/
  specs/2026-04-19-drawbit-design.md          # Full product spec
  plans/2026-04-19-drawbit-implementation.md  # Task-by-task plan

project.yml                         # xcodegen project spec (DrawBit.xcodeproj is generated)
```

## Build and run

The `DrawBit.xcodeproj` is generated by [xcodegen](https://github.com/yonaskolb/XcodeGen) from `project.yml` and is gitignored. Generate it once after cloning (and regenerate after adding, renaming, or moving any source/resource file).

**Prerequisites:** macOS with Xcode 16 or later and Homebrew.

```bash
brew install xcodegen
xcodegen generate
open DrawBit.xcodeproj
```

Then pick an iPad simulator and press ⌘R.

### From the command line

**Simulator (Debug):**
```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  build
```

**Run tests (unit + UI):**
```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test
```

**Device (unsigned compile check):**
```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

If the `iPad Pro 13-inch (M5)` simulator is not installed, list available iPads with:
```bash
xcrun simctl list devices available | grep -i iPad
```
and substitute a name from that list.

### Installing on a real iPad

1. Open `DrawBit.xcodeproj` in Xcode.
2. Select the **DrawBit** target → **Signing & Capabilities** → set a **Team** (a free Apple ID works).
3. Connect your iPad, pick it as the destination, press ⌘R.

The project's bundle identifier is `com.iamilias.drawbit`; change it to something under your own team prefix before running on device.

## Architecture notes

- **Pure-Swift drawing and rendering modules.** Everything in `DrawBit/Drawing/` and `DrawBit/Rendering/` imports only Foundation / CoreGraphics / ImageIO / UniformTypeIdentifiers — no UI or SwiftData — which is why they're covered by fast, deterministic unit tests.
- **`PieceRepository` wraps `ModelContext`.** Views do not touch SwiftData directly; they go through the repository.
- **`EditorState` is in-memory and session-scoped.** Undo/redo snapshots and the view transform live in the state and are cleared when the editor closes; transform is never persisted to the `Piece`.
- **Input is UIKit-hosted.** `CanvasHostView` is a `UIViewRepresentable` around `CanvasInputView`, a `UIView` subclass that reads `UIEvent.coalescedTouches` (up to 240 Hz with Apple Pencil) and interpolates between samples with Bresenham so fast drags don't leave gaps. Two-finger pan/zoom/rotate runs through a single custom `TwoFingerTransformGestureRecognizer`.
- **Canvas transform is view-only.** Rotation/zoom/pan never alter the stored pixel grid; exported PNGs are always axis-aligned.
- **Color pipeline is sRGB all the way.** `pixelsToCGImage` and every export `CGContext` use an explicit `CGColorSpace(name: CGColorSpace.sRGB)` so rendering matches export across iPad models (including P3 displays).
- **Animations are disabled under UI test.** A `-UITest*` launch argument (`UITestSupport.isRunning`) turns off UIKit and SwiftUI animations so the XCUITest suite is deterministic. See `CLAUDE.md` → "Test conventions".
- **The reference photo is a display-only backdrop, not a layer.** It's stored on `Piece` (a size-capped sRGB JPEG) and rendered dimmed behind the canvas in `CanvasView`, but never enters `Frame.layers`, the compositor, or exporters — so a partially transparent photo can show on screen while the layer pipeline stays strictly alpha-0/255.
- **SwiftData uses one live-typed schema with inferred lightweight migration.** Additive `Piece` fields migrate automatically; a second live-typed `VersionedSchema` is intentionally *not* added (it would collide on checksum and crash launch). If the on-disk store can't be opened, `DrawBitApp` doesn't `try!`-crash — `StoreRecovery` moves the store aside (never deletes) and the app starts fresh. See `CLAUDE.md` → "Non-obvious invariants".

## Docs

- **Spec:** [docs/superpowers/specs/2026-04-19-drawbit-design.md](docs/superpowers/specs/2026-04-19-drawbit-design.md) — the product-level design with fidelity guarantees and out-of-scope list.
- **Reference-photo design:** [docs/superpowers/specs/2026-06-03-reference-photo-design.md](docs/superpowers/specs/2026-06-03-reference-photo-design.md) — the tracing-backdrop feature design.
- **Plan:** [docs/superpowers/plans/2026-04-19-drawbit-implementation.md](docs/superpowers/plans/2026-04-19-drawbit-implementation.md) — the TDD task sequence used to build the app.
- **Working with the code:** [CLAUDE.md](CLAUDE.md) — commands, layer boundaries, and non-obvious invariants.

## Status

Feature-complete for v1 (drawing, layers, reference-photo tracing, animation, DrawBit FM, multi-format export). All 293 unit tests and 23 UI tests pass on the iPad Pro 13-inch (M5) simulator, and the app compiles clean for device in Release. Preparing the first App Store build.
