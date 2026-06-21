# Apple Pencil Hover Pop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the Apple Pencil (or a trackpad pointer) hovers an editor icon, the icon springs up and lifts, snapping back on exit.

**Architecture:** A single reusable `HoverPop` SwiftUI `ViewModifier` (`.hoverPop()`) drives a `scaleEffect` + upward `offset` + soft shadow on `.onHover`, animated with a spring. It is applied at each editor icon site. No shared button component exists today, so the modifier is added per-site; that is the intended design, not a shortcut.

**Tech Stack:** SwiftUI, iOS 17.0. `.onHover` carries Apple Pencil hover on M-series iPad Pros and trackpad-pointer hover (the latter usable in the Simulator).

## Global Constraints

- **iOS deployment floor: 17.0.** `.onHover` needs no `@available` gating at this floor; on non-hover hardware it simply never fires (graceful no-op).
- **Animation must be gated under UI test.** Every `.animation`/`withAnimation` site gates on `UITestSupport.isRunning` (a live spring would wedge XCUITest's idle sync). The `HoverPop` animation MUST pass `nil` when `UITestSupport.isRunning` is true. This mirrors `LayersPanel.swift:142` and `LayerRow.swift:98`.
- **Views layer only.** This change touches `DrawBit/Views/**` exclusively. Do not import or modify State, Persistence, Drawing, or Rendering.
- **Regenerate the Xcode project after adding any new `.swift` file:** `rm -rf DrawBit.xcodeproj && xcodegen generate` (the project references sources by path).
- **Hover is not unit-testable.** It is a pointer/hardware interaction XCUITest cannot synthesize. Verification is: the build compiles, the existing full UI suite still passes (proves animation-gating didn't wedge idle), and manual hover in Simulator/on-device. No new unit/UI test asserts the pop itself.
- **Editor only.** Gallery tiles (`PieceThumbnailView`, `GalleryView`) are out of scope.

**Build-check command (used as the per-task gate):**
```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```
If that simulator isn't installed: `xcrun simctl list devices available | grep -i iPad` and substitute the name.

---

## File Structure

- **Create:** `DrawBit/Views/Support/HoverPop.swift` — the `HoverPop` modifier + `View.hoverPop(...)` extension. One responsibility: hover visual feedback.
- **Modify:** `DrawBit/Views/Editor/ToolBar.swift` — tools, mirror, undo/redo/clear, color swatch.
- **Modify:** `DrawBit/Views/Editor/EditorView.swift` — top bar (gallery/layers/animate/share).
- **Modify:** `DrawBit/Views/Editor/FramesStrip.swift` — play/pause, fps, onion, ADD.
- **Modify:** `DrawBit/Views/Editor/LayersPanel.swift` — add/dupe/delete action bar.
- **Modify:** `DrawBit/Views/Editor/FrameRow.swift` — the frame tile.
- **Modify:** `DrawBit/Views/Editor/LayerRow.swift` — per-row pencil/eye/lock icons.
- **Modify:** `DrawBit/Views/Editor/DrawBitColorPicker.swift` — swatch grid.

---

### Task 1: The `HoverPop` modifier

**Files:**
- Create: `DrawBit/Views/Support/HoverPop.swift`

**Interfaces:**
- Produces: `extension View { func hoverPop(scale: CGFloat = 1.15, lift: CGFloat = 2) -> some View }` — applies a hover-driven scale + lift + shadow with a gated spring.

- [ ] **Step 1: Create the modifier file**

Create `DrawBit/Views/Support/HoverPop.swift`:

```swift
import SwiftUI

/// Procreate-style hover feedback: while the Apple Pencil (or a trackpad
/// pointer) hovers this view, it springs up and lifts, snapping back on exit.
///
/// `.onHover` carries Pencil hover on M-series iPad Pros and pointer hover from
/// a trackpad; on hardware without hover it never fires, so this is a graceful
/// no-op there. `scaleEffect`/`offset` don't participate in layout — neighbors
/// never reflow and the underlying hit-target stays put, so taps are unaffected.
///
/// The animation is gated to `nil` under UI test: a live spring would prevent
/// XCUITest from reaching idle and wedge its automatic sync (same gating as
/// `LayersPanel`/`LayerRow`).
struct HoverPop: ViewModifier {
    var scale: CGFloat = 1.15
    var lift: CGFloat = 2
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1.0)
            .offset(y: hovering ? -lift : 0)
            .shadow(color: .black.opacity(hovering ? 0.45 : 0),
                    radius: hovering ? 6 : 0, y: hovering ? 3 : 0)
            .animation(UITestSupport.isRunning ? nil
                       : .spring(response: 0.25, dampingFraction: 0.6),
                       value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Adds Procreate-style hover pop. Tune `scale`/`lift` per-site if needed.
    func hoverPop(scale: CGFloat = 1.15, lift: CGFloat = 2) -> some View {
        modifier(HoverPop(scale: scale, lift: lift))
    }
}
```

- [ ] **Step 2: Regenerate the project (new source file)**

Run:
```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
```
Expected: `Created project at DrawBit.xcodeproj`.

- [ ] **Step 3: Build-check**

Run the build-check command (see Global Constraints).
Expected: `** BUILD SUCCEEDED **`. (`UITestSupport.isRunning` already exists — referenced in `RootView.swift`/`LayersPanel.swift` — so it resolves without new imports.)

- [ ] **Step 4: Commit**

```bash
git add DrawBit/Views/Support/HoverPop.swift project.yml
git commit -m "feat: add HoverPop modifier for Pencil hover feedback"
```

---

### Task 2: Apply to the tool toolbar (the flagship — tune feel here)

**Files:**
- Modify: `DrawBit/Views/Editor/ToolBar.swift`

**Interfaces:**
- Consumes: `View.hoverPop()` from Task 1.

This is the most-hovered surface; verify the feel here first. Attach `.hoverPop()` to the **label content** (so the visual pops while the `Button`'s `.frame(maxWidth: .infinity)` tap slice stays fixed).

- [ ] **Step 1: Tool buttons** — in the `ForEach(Tool.allCases)` label (ToolBar.swift:22-23), add `.hoverPop()` after `.foregroundStyle(...)`:

```swift
                } label: {
                    iconLabel(systemImage: tool.sfSymbol, title: tool.displayName)
                        .foregroundStyle(state.tool == tool ? Color.toolSelected : Color.white.opacity(0.55))
                        .hoverPop()
                }
```

- [ ] **Step 2: Mirror button** — after its `.foregroundStyle` (ToolBar.swift:36):

```swift
                iconLabel(systemImage: "arrow.left.and.right", title: "Mirror")
                    .foregroundStyle(state.isMirrorEnabled ? Color.toolSelected : Color.white.opacity(0.55))
                    .hoverPop()
```

- [ ] **Step 3: Undo, Redo, Clear** — add `.hoverPop()` after the `.foregroundStyle(...)` on each of the three `iconLabel(...)` calls (ToolBar.swift:46-47, 55-56, 66-67). Example for Undo:

```swift
                iconLabel(systemImage: "arrow.uturn.backward", title: "Undo")
                    .foregroundStyle(state.canUndo ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                    .hoverPop()
```

Do the same for Redo (`"arrow.uturn.forward"`) and Clear (`"trash"`).

- [ ] **Step 4: Color swatch** — on the swatch label (ToolBar.swift:76):

```swift
            Button(action: onRequestColorPicker) {
                colorSwatchLabel(color: selectedColor)
                    .hoverPop()
            }
```

- [ ] **Step 5: Build-check**

Run the build-check command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual feel check (Simulator pointer)**

Launch the app in the Simulator, open a piece. With the Mac trackpad/mouse pointer captured by the Simulator (move the cursor over the toolbar), confirm each tool icon scales up + lifts and snaps back, and that clicking still selects the tool. If the pop feels too strong/weak, adjust `scale`/`lift` defaults in `HoverPop.swift` now (one place) before continuing.

- [ ] **Step 7: Commit**

```bash
git add DrawBit/Views/Editor/ToolBar.swift DrawBit/Views/Support/HoverPop.swift
git commit -m "feat: hover pop on the tool toolbar"
```

---

### Task 3: Apply to top bar, frames transport, layers action bar

**Files:**
- Modify: `DrawBit/Views/Editor/EditorView.swift`
- Modify: `DrawBit/Views/Editor/FramesStrip.swift`
- Modify: `DrawBit/Views/Editor/LayersPanel.swift`

**Interfaces:**
- Consumes: `View.hoverPop()` from Task 1.

These are all plain (non-draggable) buttons; the change is identical at each site — `.hoverPop()` on the label content.

- [ ] **Step 1: Top bar (EditorView.swift:165-234)** — add `.hoverPop()` to each of the four button labels:
  - GALLERY: after the label `HStack(spacing: 6) { ... }` closing brace (EditorView.swift:174).
  - LAYERS: after the `Image("LayersIcon")...frame(width: 44, height: 44)` chain (EditorView.swift:190).
  - ANIMATE: after `PixelArtIcon(...).frame(width: 44, height: 44)` (EditorView.swift:209).
  - SHARE: after `ShareGlyph().frame(width: 26, height: 26).frame(width: 44, height: 44)` (EditorView.swift:226).

Example (LAYERS):
```swift
            } label: {
                Image("LayersIcon")
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .frame(width: 26, height: 26)
                    .frame(width: 44, height: 44)
                    .hoverPop()
            }
```

- [ ] **Step 2: Frames transport + ADD (FramesStrip.swift)** — add `.hoverPop()` to each `stripButton(...)` label: play/pause (line 28), fps (line 40), onion (line 51), ADD (line 131). Example (play/pause):

```swift
                Button(action: onTogglePlay) {
                    stripButton(systemImage: state.isPlaying ? "pause.fill" : "play.fill",
                                title: state.isPlaying ? "PAUSE" : "PLAY")
                        .hoverPop()
                }
```

- [ ] **Step 3: Layers action bar (LayersPanel.swift)** — add `.hoverPop()` after the `.foregroundStyle(...)` on each `actionButton(...)`: ADD (line 53), DUPE (line 68), DELETE (line 95). Example (ADD):

```swift
                            actionButton(systemImage: "plus", title: "ADD")
                                .foregroundStyle(addDisabled ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                                .hoverPop()
```

- [ ] **Step 4: Build-check**

Run the build-check command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Views/Editor/EditorView.swift DrawBit/Views/Editor/FramesStrip.swift DrawBit/Views/Editor/LayersPanel.swift
git commit -m "feat: hover pop on top bar, frames transport, layers action bar"
```

---

### Task 4: Apply to draggable rows (FrameRow tile + LayerRow icons)

**Files:**
- Modify: `DrawBit/Views/Editor/FrameRow.swift`
- Modify: `DrawBit/Views/Editor/LayerRow.swift`

**Interfaces:**
- Consumes: `View.hoverPop()` from Task 1.

These rows are draggable. `.onHover` is a distinct pointer phase from drag and coexists, but they get their own task so a reviewer can confirm drag-to-reorder still works.

- [ ] **Step 1: FrameRow tile** — make the whole tile pop. Add `.hoverPop()` as the **last** modifier of `FrameRow.body`, after `.modifier(FrameRowAccessibility(...))` (FrameRow.swift:45-48):

```swift
            .modifier(FrameRowAccessibility(
                frame: frame, index: index, frameCount: frameCount, showsCustomName: showsCustomName,
                onDuplicate: onDuplicate, onRename: onRename, onDelete: onDelete, onMove: onMove
            ))
            .hoverPop()
```

- [ ] **Step 2: LayerRow icons** — pop the three inline icon buttons. Add `.hoverPop()` to the pencil (LayerRow.swift:59-62), eye (68-71), and lock (75-78) `Image` chains, after `.contentShape(Rectangle())`. Example (eye):

```swift
            Button { onToggleVisible() } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(.white.opacity(layer.isVisible ? 0.85 : 0.45))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .hoverPop()
            }
```

Do the same for the pencil (`"pencil"`) and lock (`"lock.fill"`/`"lock.open"`) buttons. Leave the thumbnail drag-handle as-is (no pop) so the grip reads as stable.

- [ ] **Step 3: Build-check**

Run the build-check command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual check — drag still works**

In the Simulator, open a piece, show the timeline, and drag a frame to reorder it; open the layers panel and drag a layer to reorder. Confirm reorder still completes (hover doesn't block drag), and the frame tile / layer icons pop on pointer hover.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Views/Editor/FrameRow.swift DrawBit/Views/Editor/LayerRow.swift
git commit -m "feat: hover pop on frame tiles and layer-row icons"
```

---

### Task 5: Apply to color-picker swatches (clipping-risk site)

**Files:**
- Modify: `DrawBit/Views/Editor/DrawBitColorPicker.swift`

**Interfaces:**
- Consumes: `View.hoverPop()` from Task 1.

Swatches sit in a tight grid; a popped swatch is meant to lift *over* its neighbors. Verify the sheet/grid container doesn't clip the pop.

- [ ] **Step 1: Swatch** — in `swatch(hex:)` (DrawBitColorPicker.swift:159-167), add `.hoverPop()` after the `.overlay(...)` and before `.contentShape(Rectangle())`:

```swift
        return Rectangle()
            .fill(Color(rgba: swatchColor))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Rectangle().stroke(
                    isSelected ? Color.white : Color.white.opacity(0.18),
                    lineWidth: isSelected ? 2 : 0.5
                )
            )
            .hoverPop()
            .contentShape(Rectangle())
            .onTapGesture {
```

- [ ] **Step 2: Build-check**

Run the build-check command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual check — no clipping**

In the Simulator, open the color picker, hover swatches. Confirm a hovered swatch pops *above* its neighbors without being clipped at the grid/sheet edge, and selection still works on tap. If an edge swatch is clipped, add a small `.padding(2)` to the grid container at the clipped edge only (do not add padding speculatively).

- [ ] **Step 4: Commit**

```bash
git add DrawBit/Views/Editor/DrawBitColorPicker.swift
git commit -m "feat: hover pop on color-picker swatches"
```

---

### Task 6: Regression + manual sign-off

**Files:** none (verification only).

- [ ] **Step 1: Full UI suite (regression gate for animation gating)**

Run:
```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```
Expected: `** TEST SUCCEEDED **`, all unit + UI tests pass. This confirms the gated animation under `UITestSupport.isRunning` did not wedge XCUITest's idle wait. If a UI test newly hangs/flakes, re-check that every `.hoverPop()` resolves to the `nil` animation under test (it should, via the shared modifier) — do not add per-site gating.

- [ ] **Step 2: Manual on-device hover (if hardware available)**

On an M-series iPad Pro with Apple Pencil 2 / Pencil Pro, open a piece and hover (don't touch) each editor cluster: tools, top bar, frames strip, layers panel, color picker. Confirm each icon pops + lifts on Pencil hover, snaps back on exit, no clipping, and taps/selection are unchanged. (Touch-only devices show no pop — that's the intended graceful degradation.)

- [ ] **Step 3: Finalize the branch**

Use the `superpowers:finishing-a-development-branch` skill to choose how to integrate `pencil-hover-pop` (merge / PR / cleanup).

---

## Self-Review

- **Spec coverage:** modifier (Task 1); editor sites — toolbar (Task 2), top bar + frames transport + layers action bar (Task 3), draggable frame/layer rows (Task 4), swatches (Task 5); animation gating (in the modifier, Task 1); regression + manual (Task 6); gallery explicitly excluded (Global Constraints). All spec sections covered.
- **Type consistency:** `hoverPop(scale:lift:)` signature defined in Task 1 is used unchanged (default args) in Tasks 2-5. `UITestSupport.isRunning` matches existing usage in `LayersPanel.swift`/`LayerRow.swift`.
- **Placeholder scan:** no TBD/TODO; every code step shows the actual edit; the deliberate "no new automated test for hover" is justified under Global Constraints (hardware interaction), not a gap.
