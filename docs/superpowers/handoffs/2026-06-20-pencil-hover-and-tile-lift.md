# Handoff — Apple Pencil hover pop + gallery tile lift (2026-06-20)

Both features below are merged to local `main` but **NOT pushed**. Latest commit: `248bb2f`.
`origin/main` is still at `9b1b059` — `git push` when ready (two merges ahead).

## Pending ideas / things to judge next
- **Push `main` to origin.** Both features are local-only by the user's choice. Nothing is on the remote yet.
- **Judge the hover pop on real hardware.** The *feel* was confirmed via trackpad-pointer hover in the Simulator, but Apple Pencil hover only fires on an M-series iPad Pro with Pencil 2 / Pencil Pro. Two knobs (one place): `scale` (1.15) and `lift` (2) defaults at the top of `DrawBit/Views/Support/HoverPop.swift`. Change once → every editor icon updates.
- **Judge the tile lift on real hardware.** Confirmed gentle on the Simulator. Two knobs in `DrawBit/Views/Gallery/GalleryTileLift.swift`: the dark drop (`black.opacity(0.55), radius 4, y 2`) and the light halo (`white.opacity(0.05), radius 6`). It's deliberately subtle because a literal black shadow has no contrast on the near-black gallery bg.
- **Gallery organization (folders vs. stacks) was explored and dropped.** The user decided not to build it this session. If revisited: groups would be small (a handful), so *stacks* (drag a tile onto another, collapse to a pile) fit better than folders — but the user's call was "forget about it." No spec/plan was written for it.
- **Loose files still untracked** in repo root: `alt_logo.PNG`, `dbit.png`, `share.PNG`, and `docs/superpowers/handoffs/2026-06-15-toolbar-symmetry-icons.md`. Carried over from the prior handoff; still left as-is.

## What shipped this session (newest first)

### Gallery tile lift — `248bb2f`
Gallery tiles now read as gently lifted off the canvas (Procreate-style, adapted for a dark UI).
- `DrawBit/Views/Gallery/GalleryTileLift.swift` (NEW) — a reusable `.galleryTileLift()` `ViewModifier`. Pairs a soft dark drop shadow with a faint **light** halo, because a literal black drop shadow is nearly invisible on the `#1a1a1a` gallery background. Tuning constants live only here. No animation → no `UITestSupport` gating needed.
- Applied (one line each, after the existing border `.overlay`) to: `PieceThumbnailView` (piece tiles) and `NewPieceTile` (the "+" tile) in `DrawBit/Views/Gallery/PieceThumbnailView.swift`, and `DrawBit/Views/Gallery/FMTile.swift` (the pinned FM tile).
- The gallery background was intentionally **not** changed (keeps the canvas-continuity look); the glow-lift is what makes elevation read on dark.

### Apple Pencil hover pop — `9b644a9` (the bigger one)
Hovering an editor icon with the Apple Pencil (or a trackpad pointer) makes it spring up + lift, snapping back on exit. Editor-only; the gallery is intentionally excluded.
- `DrawBit/Views/Support/HoverPop.swift` (NEW) — the `.hoverPop(scale:lift:)` modifier: `scaleEffect` + upward `offset` + soft shadow driven by `.onHover`, with a spring **gated to `nil` under `UITestSupport.isRunning`**. `.onHover` carries Pencil hover on M-series iPad Pros and is a graceful no-op on non-hover hardware (no `@available` needed at the iOS 17 floor).
- `.hoverPop()` applied across the editor: `ToolBar.swift` (tools, mirror, undo/redo/clear, color swatch), `EditorView.swift` top bar (gallery/layers/animate/share), `FramesStrip.swift` (play/fps/onion/add), `LayersPanel.swift` (add/dupe/delete), `FrameRow.swift` (whole tile, as last body modifier), `LayerRow.swift` (pencil/eye/lock icons), and `ReferenceRow.swift` (eye/photo-picker/trash — caught by the final review as a missed cluster on the same panel).
- Full spec + plan committed: `docs/superpowers/specs/2026-06-20-pencil-hover-pop-design.md`, `docs/superpowers/plans/2026-06-20-pencil-hover-pop.md`.

## Verification
- Build: `xcodebuild -project DrawBit.xcodeproj -scheme DrawBit -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build`
- Full suite green: `… test` (unit + UI). The hover feature was validated with two full green runs; the tile-lift change ran `-only-testing:DrawBitUITests`.
- Both effects are visual — judge on the Simulator (trackpad-pointer hover triggers `.onHover`) and, ideally, Pencil hover on device.

## Gotchas
- **Known UI flake:** `ReferencePhotoUITests/testReferenceRowAppearsInLayersPanel` failed once in a full-suite run under load, then **passed in isolation**. It's the contention flake CLAUDE.md documents for the layers-panel UI tests (it polls for `Reference-toggle`), not a regression. If the full UI suite shows one failure here, re-run that test alone before assuming breakage.
- **Reusable-modifier pattern:** both features are a single `ViewModifier` in `Views/` applied at many call sites (`HoverPop`, `GalleryTileLift`). Keep tuning constants in the modifier; don't inline per-site. This is now the house pattern for cross-cutting visual polish.
- **Animation gating is load-bearing:** any new `.animation`/`withAnimation` must gate on `!UITestSupport.isRunning` (a live spring wedges XCUITest idle). `HoverPop` does this; `GalleryTileLift` has no animation so it doesn't need it.
- **New `.swift` files require a project regen:** `rm -rf DrawBit.xcodeproj && xcodegen generate` (`.xcodeproj` is gitignored). Both new files needed it.
- **Do NOT run debug builds on the physical iPad ("Penny")** — iPadOS 27 dev beta vs. installed Xcode mismatch crashes in `libxpc` before `main()`. Use the Simulator. (Carried from prior handoff.)
- **Shadows need non-clipping containers:** the gallery `LazyVGrid` doesn't clip and tiles sit inside the 30pt `edgeInset`, so the tile-lift halo isn't truncated. Keep that in mind if the gallery layout changes.
