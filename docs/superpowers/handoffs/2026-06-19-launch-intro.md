# Handoff — launch intro + session fixes (2026-06-19)

All work below is merged to `main` and pushed. Latest commit: `0234754`.

## Pending ideas / things to judge next
- **Tune the intro pacing on-device, at full speed.** Two knobs:
  - Title/logo/grey-page beats: `dissolveOut` / `dissolveIn` / `logoHold` / `pageIn` (all `0.5`/`0.4`) in `DrawBit/Views/Landing/LaunchSequenceView.swift`.
  - The 4-move gallery reveal gap: `gap = 0.22` in `GalleryView.runIntro()`. Lower = snappier, higher = more deliberate.
- **Status bar appears the moment PRESS START is tapped** (landing keeps it hidden; launching/gallery show it). This was deliberate — see Gotchas. If it reads oddly, the alternative is showing the status bar on the landing too (changes the clean landing look) — don't hide it during launching or the gallery content bounces.
- **Loose files still untracked** in repo root: `alt_logo.PNG`, `dbit.png` (the two logo candidates we didn't use — we used the AppIcon), `share.PNG`, and `docs/superpowers/handoffs/2026-06-15-toolbar-symmetry-icons.md`. Left as-is; decide whether to commit/delete.

## What shipped this session (newest first)

### Launch intro — `0234754` (the big one)
Tapping PRESS START plays a staged intro instead of cutting to the gallery:
1. **DRAWBIT title dissolves out** → **app-icon logo dissolves in** (centered on DRAWBIT) and back out → **gallery's grey page assembles from black** (all via the pixel-dissolve).
2. Once the grey page is solid, the gallery's four elements **pop in as discrete "moves"**: GALLERY title → the "i" → the works grid → DRAWBIT FM.

Key files:
- `DrawBit/Views/Support/PixelDissolve.swift` (NEW) — the help page's pixel-dissolve (`PixelDissolve`, `PixelDissolveModifier`, `AnyTransition.openDissolve`) extracted here as **internal** + a `pixelDissolve(progress:)` modifier for driving it in both directions. `HelpScreen.swift` lost its private copies and uses these.
- `DrawBit/Views/Landing/LaunchSequenceView.swift` (NEW) — drives the title/logo/grey-page beats via `withAnimation(_:completion:)` chaining. Title + logo centered full-screen (`.ignoresSafeArea()`); logo is an `.overlay` on the DRAWBIT `Text` so it shares DRAWBIT's center.
- `DrawBit/Assets.xcassets/AppLogo.imageset/` (NEW) — copy of `AppIcon-Dark.png` (an `.appiconset` can't be loaded via `Image("…")`, so it needs its own imageset).
- `DrawBit/Views/Support/RootView.swift` — `enum RootScreen { landing, launching, gallery }`; `start()` gates the intro **off under UI test** (`UITestSupport.isRunning ? .gallery : .launching`); `galleryPlaysIntro` is passed to `GalleryView(playIntro:)` only on the launch path.
- `DrawBit/Views/Gallery/GalleryView.swift` — gained `init(playIntro:)` + four `show…` opacity booleans + `runIntro()` (staggered `DispatchQueue.main.asyncAfter` reveals, guarded once via `didRunIntro`). When `!playIntro` (normal entry / UI test) everything is shown on the first frame.

### Earlier this session (all on `main`)
- **`00f815c`** — themed editor pop-ups: new `DrawBit/Views/Editor/ConfirmDialogSheet.swift` replaces 3 native `.confirmationDialog`s (frame/layer delete, reference remove); frame-rename field restyled to match `LayerRow`; **fixed the sheet slide-in "white trail"** by adding `.presentationBackground(Color(white: 0.10))` to all 8 `.sheet`s.
- **`a7a0e00`** — `fix(undo)`: undo now reverts the **stroke's own frame**, not frame 0. Root cause: `.layerPixels` undo entries were keyed only by layer id, but layer UUIDs are shared across all frames (the cascade), so `firstIndex(by layerID)` always hit frame 0. Now keyed by `frameID`. Regression test in `EditorStateTests`.
- **`d4a3a24`** — help-page tiles made borderless (bg matches page `Color(white: 0.10)`, no outline).
- **`42f172a`** — removed the Comets & Maze DrawBit FM tracks (deleted the two `.mp3`s in `DrawBit/Resources/fm/`; tracks auto-discovered, so no code change). Station now ships 8 tracks.

## Verification
- Build: `xcodebuild -project DrawBit.xcodeproj -scheme DrawBit -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build`
- Tests green: 294 unit (`-only-testing:DrawBitTests`), plus `DrawBitUITests/LandingScreenTests` and `DrawBitUITests/HelpScreenUITests`.
- The intro is animation — judge it on the simulator. Capturing the 4-move reveal is easiest with **Debug ▸ Slow Animations** ON (note: the gallery moves are real-time `asyncAfter`, NOT Core-Animation, so slow-mo does **not** slow them — only the title/logo/grey-page beats).

## Gotchas
- **New `.swift` files / new imageset require a project regen:** `rm -rf DrawBit.xcodeproj && xcodegen generate` (`.xcodeproj` is gitignored).
- **Do NOT run debug builds on the physical iPad ("Penny").** It's on **iPadOS 27 developer beta 1**, newer than the installed Xcode — launching a debug build crashes in `libxpc` (`_xpc_init_pid_domain`, unrecognized-selector) *before* `main()`. This is a toolchain-vs-OS mismatch, not an app bug. Use the **simulator**, or install the paired Xcode 27 beta.
- **UI-test gating is load-bearing:** the intro must be skipped under `UITestSupport.isRunning`, and `GalleryView` must render complete when `!playIntro`, or `LandingScreenTests`/`HelpScreenUITests` can't find `NewButton`/`Help.button`.
- **Status-bar consistency prevents the gallery "bounce":** landing hides the status bar; launching + gallery show it. The intro content centers full-screen (`.ignoresSafeArea()`) so the status bar appearing at tap doesn't shift DRAWBIT.
- **All custom sheets** now rely on `.presentationBackground(Color(white: 0.10))` to avoid the white-platter trail — keep that on any new sheet.
