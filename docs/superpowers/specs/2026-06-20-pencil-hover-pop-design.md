# Apple Pencil hover — icon "pop" in the editor

**Date:** 2026-06-20
**Status:** Approved design, pre-implementation

## Why

Procreate uses Apple Pencil hover throughout: bringing the Pencil near a tool, palette, or icon makes it react *before* you tap. It makes the app feel alive and responsive under the Pencil. DrawBit has no hover feedback today — every icon is static until tapped.

We want the same slick feel in DrawBit's **editor**: hovering the Pencil over an editor icon makes it spring up and lift, snapping back when the Pencil moves away. This is pure tactile feedback (no tooltips, no text), and it applies to the editor only — the gallery keeps its current calm, static feel.

## What it does

When the Apple Pencil hovers over an interactive icon in the editor (or a trackpad pointer, which uses the same signal), the icon:

- **scales up ~15%**,
- **lifts** slightly (small upward offset + soft drop shadow),
- **springs** into place, and snaps back when the hover ends.

On hardware without hover (older iPads, no Pencil 2/Pro, touch-only), nothing fires — the UI is identical to today. No availability gating needed.

## How it works

### One reusable modifier

All behavior lives in a single `HoverPop` view modifier, added next to the other view-layer helpers in `DrawBit/Views/Support/` (alongside `PixelFont.swift`). It is a SwiftUI-only View modifier — it belongs in the Views layer and does not touch State, Persistence, Drawing, or Rendering.

```swift
struct HoverPop: ViewModifier {
    @State private var hovering = false
    var scale: CGFloat = 1.15
    var lift: CGFloat = 2

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
    func hoverPop(scale: CGFloat = 1.15, lift: CGFloat = 2) -> some View {
        modifier(HoverPop(scale: scale, lift: lift))
    }
}
```

Usage: `.hoverPop()` on a button's icon/label. All tuning constants (scale, lift, shadow, spring) live in this one file.

### Design rationale

- **`.onHover` is the right signal.** On M-series iPad Pros it fires for Apple Pencil hover; it also fires for trackpad pointers, which means it can be exercised in the simulator. On non-hover hardware it simply never fires — graceful degradation with zero extra code, no `@available` checks on the iOS 17.0 floor.
- **Non-layout transforms.** `scaleEffect` and `offset` don't participate in layout, so neighbors don't reflow and hit-targets stay fixed. The icon pops *over* its neighbors; taps still land exactly where they did.
- **Animation gated under UI test.** `UITestSupport.isRunning` forces the animation to `nil` during UI tests. This is load-bearing per the project's UI-test-stability invariant: a live `.spring` (continuously animating during hover) would prevent XCUITest from ever reaching idle and wedge its automatic sync. Gating keeps the existing UI suite stable. Mirrors how every other `.animation`/`withAnimation` site in the app is gated.

### Application sites (editor only)

Add `.hoverPop()` at each icon button site:

- `DrawBit/Views/Editor/ToolBar.swift` — tool buttons, mirror, undo/redo/clear, color swatch
- `DrawBit/Views/Editor/EditorView.swift` — top bar: gallery / layers / animate / export
- `DrawBit/Views/Editor/FramesStrip.swift` — play/pause, fps, onion-skin, ADD, frame thumbnails (`FrameRow`)
- `DrawBit/Views/Editor/LayersPanel.swift` — add/dupe/delete buttons + per-row eye/lock/thumbnail icons (`LayerRow`)
- `DrawBit/Views/Editor/DrawBitColorPicker.swift` — swatch grid (currently `.onTapGesture` views; the modifier applies the same way)

Gallery tiles (`PieceThumbnailView`, `GalleryView`) are intentionally **excluded**.

### Coexistence with drag

`FrameRow` and `LayerRow` are draggable (`.draggable`/`.dropDestination`). `.onHover` and drag gestures coexist without conflict — hover is a separate pointer phase from drag. No special handling required.

## Risks & edge cases

- **Clipping.** A scaled-up icon can be clipped if its container clips its bounds. Verify each cluster renders the pop without truncation; add minimal padding only where a real clip is observed. Do not add padding speculatively.
- **No behavior change to taps/selection.** Hover only drives visuals. Selection logic (e.g. `state.setTool`, `SelectionFeedback.shared.fire()`) is untouched.

## Testing

Hover is a hardware/pointer interaction that XCUITest cannot synthesize, so there is no automated hover assertion. Verification is:

1. **Regression guard — full UI suite passes.** Confirms the animation-gating is correct and idle sync is not wedged:
   ```bash
   xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
     -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
   ```
2. **Manual — simulator pointer hover.** With a Mac trackpad/mouse pointer captured by the simulator, hover each editor cluster (tools, top bar, frames, layers, swatches); confirm each icon pops, lifts, and snaps back, and that tapping still selects.
3. **Manual — on-device Pencil hover.** On an M-series iPad Pro with Apple Pencil 2 / Pencil Pro, confirm the same pop fires on Pencil hover across all editor clusters and that no icon is clipped.

## Out of scope

- Gallery tile hover.
- Tooltips / name labels on hover (chose pure scale+lift).
- Brush/size previews on hover.
- Glow/highlight styling (chose scale+lift over a static highlight).
