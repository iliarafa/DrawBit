# Animation Strip Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the animation strip to match the toolbar (pixel font, uppercase icon-over-label buttons, monochrome states, group dividers) and fix six usability issues: a tap-to-open fps menu, a blank-frame ADD button, a DUPLICATE/RENAME/DELETE long-press context menu, drag-to-reorder, a clearer onion-skin toggle, removal of EDIT mode, and corner number badges.

**Architecture:** Pure-logic gets one new function (`FrameSequence.addBlankFrameAfter`) under TDD. Everything else is the view layer (`FramesStrip`, `FrameRow`) plus thin wiring methods on `EditorView`. No model/persistence/rendering changes; existing frame mutations already snapshot undo and persist via `mutateFrameSequence`.

**Tech Stack:** Swift, SwiftUI, XCTest. iPad-only. App display font is `PressStart2P` via `Font.pixel(_:)`. Reference styling: `DrawBit/Views/Editor/ToolBar.swift`.

---

## File structure

- `DrawBit/Drawing/FrameSequence.swift` — **modify**: add `addBlankFrameAfter`. Pure logic (Foundation only).
- `DrawBitTests/Drawing/FrameSequenceTests.swift` — **modify**: add tests for `addBlankFrameAfter`.
- `DrawBit/Views/Editor/EditorView.swift` — **modify**: add `addBlankFrameAfter()`, `duplicateActiveFrame()`, `moveFrame(fromIndex:toIndex:)`; rewire the `FramesStrip(...)` call site.
- `DrawBit/Views/Editor/FramesStrip.swift` — **rewrite**: toolbar-style control clusters, fps `Menu`, group dividers, ADD button, no EDIT mode.
- `DrawBit/Views/Editor/FrameRow.swift` — **rewrite**: number badge, custom-name overlay, white active ring, pixel font, context menu, drag-to-reorder.
- `DrawBitUITests/AnimationStripUITests.swift` — **modify**: update for the new ADD-is-blank behavior, removed EDIT toggle, and context menu.

**No new files are created**, so the Xcode project does **not** need regenerating.

---

## Task 1: Blank-frame model function

**Files:**
- Modify: `DrawBit/Drawing/FrameSequence.swift`
- Test: `DrawBitTests/Drawing/FrameSequenceTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `DrawBitTests/Drawing/FrameSequenceTests.swift`, after `testDuplicateFrame()` (around line 38):

```swift
func testAddBlankFrameAfterInsertsEmptyFrame() {
    var frames = makeFrames(["F1"])
    // Draw something into F1 so we can prove the new frame is NOT a copy.
    var layers = frames[0].layers
    layers[0].pixels[0] = 0xCC
    frames[0] = Frame(id: frames[0].id, name: frames[0].name,
                      layers: layers, activeLayerID: frames[0].activeLayerID)

    let newID = FrameSequence.addBlankFrameAfter(frameID: frames[0].id, in: &frames)
    XCTAssertNotNil(newID)
    XCTAssertEqual(frames.count, 2)
    XCTAssertEqual(frames[1].id, newID)
    XCTAssertNotEqual(frames[1].id, frames[0].id)
    // New frame is blank in every layer:
    XCTAssertTrue(frames[1].layers.allSatisfy { $0.pixels.allSatisfy { $0 == 0 } },
                  "Blank-added frame must have all-zero pixels")
    // Source frame is untouched:
    XCTAssertEqual(frames[0].layers[0].pixels[0], 0xCC)
}

func testAddBlankFrameAfterPreservesLayerUUIDsAndOrder() {
    var frames = makeFrames(["F1"])
    _ = FrameSequence.addLayer(name: "Layer 2", in: &frames)
    let sourceLayerIDs = frames[0].layers.map(\.id)

    _ = FrameSequence.addBlankFrameAfter(frameID: frames[0].id, in: &frames)
    // The cascade invariant: the new frame has the SAME layer UUIDs in the same order.
    XCTAssertEqual(frames[1].layers.map(\.id), sourceLayerIDs)
}

func testAddBlankFrameAfterRespectsCap() {
    var frames = makeFrames((1...60).map { "F\($0)" })
    let newID = FrameSequence.addBlankFrameAfter(frameID: frames.last!.id, in: &frames)
    XCTAssertNil(newID, "Adding past the 60-frame cap must return nil")
    XCTAssertEqual(frames.count, 60)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/FrameSequenceTests
```
Expected: compile failure / FAIL — `addBlankFrameAfter` does not exist.

- [ ] **Step 3: Implement `addBlankFrameAfter`**

In `DrawBit/Drawing/FrameSequence.swift`, add immediately after `duplicateFrame` (after line 26):

```swift
/// Inserts a new EMPTY frame after the frame with the given id: same layer UUIDs,
/// names, visibility and lock state (so the cascade invariant holds) but all-zero
/// pixels. Contrast with `addFrameAfter`/`duplicateFrame`, which copy pixels.
/// Returns the new frame id, or nil if at the cap.
@discardableResult
static func addBlankFrameAfter(frameID: UUID, in frames: inout [Frame]) -> UUID? {
    guard frames.count < frameCap else { return nil }
    guard let idx = frames.firstIndex(where: { $0.id == frameID }) else { return nil }
    let source = frames[idx]
    let blankLayers = source.layers.map { layer in
        Layer(id: layer.id,
              name: layer.name,
              pixels: Data(count: layer.pixels.count),
              isVisible: layer.isVisible,
              isLocked: layer.isLocked)
    }
    let copy = Frame(name: nextFrameName(in: frames),
                     layers: blankLayers,
                     activeLayerID: source.activeLayerID)
    frames.insert(copy, at: idx + 1)
    return copy.id
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/FrameSequenceTests
```
Expected: PASS (all FrameSequenceTests green, including the three new ones).

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/FrameSequence.swift DrawBitTests/Drawing/FrameSequenceTests.swift
git commit -m "feat(frames): add blank-frame insert (addBlankFrameAfter)"
```

---

## Task 2: EditorView wiring

**Files:**
- Modify: `DrawBit/Views/Editor/EditorView.swift` (methods near line 469; call site lines 50–59)

- [ ] **Step 1: Add the three wiring methods**

In `DrawBit/Views/Editor/EditorView.swift`, add after `addFrameAfterActive()` (after line 477):

```swift
func addBlankFrameAfter() {
    let activeID = state.frames[state.activeFrameIndex].id
    mutateFrameSequence { frames in
        if let newID = FrameSequence.addBlankFrameAfter(frameID: activeID, in: &frames),
           let idx = frames.firstIndex(where: { $0.id == newID }) {
            state.activeFrameIndex = idx
        }
    }
}

func duplicateActiveFrame() {
    let activeID = state.frames[state.activeFrameIndex].id
    mutateFrameSequence { frames in
        if let newID = FrameSequence.duplicateFrame(activeID, in: &frames),
           let idx = frames.firstIndex(where: { $0.id == newID }) {
            state.activeFrameIndex = idx
        }
    }
}

/// Index-based reorder for drag-and-drop (plain from/to, not `.onMove` offsets).
func moveFrame(fromIndex: Int, toIndex: Int) {
    guard fromIndex != toIndex,
          state.frames.indices.contains(fromIndex) else { return }
    let activeID = state.frames[state.activeFrameIndex].id
    let movingID = state.frames[fromIndex].id
    mutateFrameSequence { frames in
        FrameSequence.move(frameID: movingID, toIndex: toIndex, in: &frames)
        if let newActiveIdx = frames.firstIndex(where: { $0.id == activeID }) {
            state.activeFrameIndex = newActiveIdx
        }
    }
}
```

- [ ] **Step 2: Rewire the `FramesStrip` call site (keep current argument order)**

The current `FramesStrip` signature is unchanged in this task, so keep the existing argument order and only rebind three closures. Replace the `FramesStrip(...)` initializer at lines 50–59 with:

```swift
FramesStrip(
    state: state,
    onAddFrame: addBlankFrameAfter,
    onDuplicateFrame: duplicateActiveFrame,
    onDeleteFrame: deleteActiveFrameWithConfirmIfNeeded,
    onReorderFrame: { moveFrame(fromIndex: $0, toIndex: $1) },
    onRenameFrame: renameFrame,
    onActivateFrame: setActiveFrameAndPersistIfDirty,
    onTogglePlay: togglePlay
)
```

Note: `addFrameAfterActive` stays in the file — it is still used by the ANIMATE toggle (line ~178) to seed frame 2 with a copy. The now-unused `reorderFrame(from:toOffset:)` may be left as-is; do not delete it in this task (avoid churn). The argument *order* changes to its final form in Task 3 when `FramesStrip`'s signature moves `onDeleteFrame` to the end.

- [ ] **Step 3: Build to verify it compiles**

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add DrawBit/Views/Editor/EditorView.swift
git commit -m "feat(frames): wire ADD=blank, DUPLICATE=copy, index-based move"
```

---

## Task 3: FramesStrip — toolbar-style controls, fps menu, no EDIT mode

**Files:**
- Rewrite: `DrawBit/Views/Editor/FramesStrip.swift`

This task restyles the control clusters and removes EDIT mode. `FrameRow` is still called with its **current** interface (`frame/size/isActive/isEditing/onTap/onLongPressRename`) — it is rewritten in Task 4. The inline rename `TextField` stays here.

- [ ] **Step 1: Replace the file contents**

Replace all of `DrawBit/Views/Editor/FramesStrip.swift` with:

```swift
import SwiftUI

struct FramesStrip: View {
    let state: EditorState
    let onAddFrame: () -> Void
    let onDuplicateFrame: () -> Void
    /// Index-based reorder (from, to) used by FrameRow drag-and-drop.
    let onReorderFrame: (Int, Int) -> Void
    let onRenameFrame: (UUID, String) -> Void
    let onActivateFrame: (Int) -> Void
    let onTogglePlay: () -> Void
    let onDeleteFrame: () -> Void

    @State private var renamingFrameID: UUID?
    @State private var renameText: String = ""

    private static let fpsChoices = [4, 8, 12, 24, 30, 60]

    var body: some View {
        HStack(spacing: 18) {
            // Transport group
            HStack(spacing: 16) {
                Button(action: onTogglePlay) {
                    stripButton(systemImage: state.isPlaying ? "pause.fill" : "play.fill",
                                title: state.isPlaying ? "PAUSE" : "PLAY")
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.frames.count <= 1 ? Color.white.opacity(0.25) : Color.white)
                .disabled(state.frames.count <= 1)
                .accessibilityIdentifier("FramesStrip.playPause")
                .accessibilityLabel(state.isPlaying ? "Pause animation" : "Play animation")

                Menu {
                    ForEach(Self.fpsChoices, id: \.self) { choice in
                        Button {
                            state.fps = choice
                        } label: {
                            if choice == state.fps {
                                Label("\(choice) FPS", systemImage: "checkmark")
                            } else {
                                Text("\(choice) FPS")
                            }
                        }
                    }
                } label: {
                    stripButton(systemImage: "speedometer", title: "\(state.fps) FPS")
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.isPlaying ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                .disabled(state.isPlaying)
                .accessibilityIdentifier("FramesStrip.fps")
                .accessibilityLabel("Playback speed")
                .accessibilityValue("\(state.fps) frames per second")

                Button(action: { state.isOnionSkinEnabled.toggle() }) {
                    stripButton(systemImage: "square.2.layers.3d", title: "ONION")
                }
                .buttonStyle(.plain)
                .foregroundStyle(onionColor)
                .disabled(state.activeFrameIndex == 0 || state.isPlaying)
                .accessibilityIdentifier("FramesStrip.onionSkin")
                .accessibilityLabel(state.isOnionSkinEnabled ? "Onion skin on" : "Onion skin off")
                .accessibilityHint("Shows a faded preview of the previous frame behind the current one")
            }

            divider

            // Frames
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(state.frames.enumerated()), id: \.element.id) { index, frame in
                        if renamingFrameID == frame.id {
                            TextField("Frame name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .onSubmit { commitRename() }
                                .submitLabel(.done)
                        } else {
                            FrameRow(
                                frame: frame,
                                size: state.size,
                                isActive: frame.id == state.frames[state.activeFrameIndex].id,
                                isEditing: false,
                                onTap: {
                                    if renamingFrameID != nil && renamingFrameID != frame.id {
                                        commitRename()
                                    }
                                    if let idx = state.frames.firstIndex(where: { $0.id == frame.id }) {
                                        onActivateFrame(idx)
                                    }
                                },
                                onLongPressRename: {
                                    renamingFrameID = frame.id
                                    renameText = frame.name
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .disabled(state.isPlaying)

            divider

            // Actions
            Button(action: onAddFrame) {
                stripButton(systemImage: "plus", title: "ADD")
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.frames.count >= FrameSequence.frameCap
                             ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
            .disabled(state.frames.count >= FrameSequence.frameCap)
            .accessibilityIdentifier("FramesStrip.add")
            .accessibilityLabel("Add blank frame")
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .background(Color.black.opacity(0.4))
    }

    private var divider: some View {
        Divider().frame(height: 36).overlay(Color.white.opacity(0.15))
    }

    private var onionColor: Color {
        if state.activeFrameIndex == 0 || state.isPlaying { return Color.white.opacity(0.25) }
        return state.isOnionSkinEnabled ? Color.white : Color.white.opacity(0.55)
    }

    /// Toolbar-consistent button: SF Symbol over an uppercase pixel-font label.
    /// Mirrors `ToolBar.iconLabel`.
    private func stripButton(systemImage: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
            Text(title)
                .font(.pixel(8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    private func commitRename() {
        guard let id = renamingFrameID else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           let current = state.frames.first(where: { $0.id == id }),
           trimmed != current.name {
            onRenameFrame(id, trimmed)
        }
        renamingFrameID = nil
        renameText = ""
    }
}
```

Note: `onDuplicateFrame` and `onDeleteFrame` are declared but not yet *used* in this task (the EDIT-mode buttons are gone; they get used by `FrameRow`'s context menu in Task 4). That is intentional — keep them in the signature.

- [ ] **Step 2: Update the EditorView call site to the final argument order**

In `DrawBit/Views/Editor/EditorView.swift`, ensure the `FramesStrip(...)` call matches the new signature (note `onDeleteFrame` is now last):

```swift
FramesStrip(
    state: state,
    onAddFrame: addBlankFrameAfter,
    onDuplicateFrame: duplicateActiveFrame,
    onReorderFrame: { moveFrame(fromIndex: $0, toIndex: $1) },
    onRenameFrame: renameFrame,
    onActivateFrame: setActiveFrameAndPersistIfDirty,
    onTogglePlay: togglePlay,
    onDeleteFrame: deleteActiveFrameWithConfirmIfNeeded
)
```

- [ ] **Step 3: Build to verify it compiles**

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```
Expected: BUILD SUCCEEDED. Swift will warn that `onDuplicateFrame`/`onDeleteFrame` are unused-ish (they're stored properties, so no warning) — fine.

- [ ] **Step 4: Commit**

```bash
git add DrawBit/Views/Editor/FramesStrip.swift DrawBit/Views/Editor/EditorView.swift
git commit -m "feat(frames): restyle strip controls to toolbar style, drop EDIT mode"
```

---

## Task 4: FrameRow — number badge, context menu, drag-to-reorder

**Files:**
- Rewrite: `DrawBit/Views/Editor/FrameRow.swift`
- Modify: `DrawBit/Views/Editor/FramesStrip.swift` (the `FrameRow(...)` call site)

- [ ] **Step 1: Replace `FrameRow.swift`**

Replace all of `DrawBit/Views/Editor/FrameRow.swift` with:

```swift
import SwiftUI

struct FrameRow: View {
    let frame: Frame
    let size: CanvasSize
    let index: Int
    let isActive: Bool
    let frameCount: Int
    let onTap: () -> Void
    let onDuplicate: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    /// Index-based reorder (from, to).
    let onMove: (Int, Int) -> Void

    private static let edge: CGFloat = 46

    /// Show the name overlay only when the user actually named the frame —
    /// suppress the auto-generated "Frame N" names.
    private var showsCustomName: Bool {
        frame.name.range(of: #"^Frame \d+$"#, options: .regularExpression) == nil
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.25))
                .frame(width: Self.edge, height: Self.edge)

            if let cg = FrameThumbnailRenderer.renderCGImage(frame: frame, size: size, targetEdge: Int(Self.edge)) {
                Image(uiImage: UIImage(cgImage: cg))
                    .interpolation(.none)
                    .antialiased(false)
                    .resizable()
                    .frame(width: Self.edge, height: Self.edge)
            }

            // Number badge, top-left.
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("\(index + 1)")
                        .font(.pixel(7))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(isActive ? Color.white : Color.black.opacity(0.7))
                        .foregroundStyle(isActive ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(2)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .frame(width: Self.edge, height: Self.edge)

            // Custom-name overlay, bottom strip.
            if showsCustomName {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(frame.name.uppercased())
                        .font(.pixel(6))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.6))
                        .foregroundStyle(.white)
                }
                .frame(width: Self.edge, height: Self.edge)
            }
        }
        .frame(width: Self.edge, height: Self.edge)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isActive ? Color.white : Color.white.opacity(0.15),
                        lineWidth: isActive ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            Button { onDuplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { onRename() } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                .disabled(frameCount <= 1)
        }
        .draggable("\(index)") {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.2))
                .frame(width: Self.edge, height: Self.edge)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let from = Int(s), from != index else { return false }
            onMove(from, index)
            return true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("FrameRow.\(frame.id.uuidString)")
        .accessibilityLabel(showsCustomName ? "Frame \(index + 1), \(frame.name)" : "Frame \(index + 1)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Duplicate") { onDuplicate() }
        .accessibilityAction(named: "Rename") { onRename() }
        .accessibilityAction(named: "Delete") { onDelete() }
    }
}
```

Note: the context menu uses the system font (Title Case "Duplicate"/"Rename"/"Delete"), per the project rule that menus/alerts stay on the system font for legibility (`PixelFont.swift`). The pixel font is for bar chrome only.

- [ ] **Step 2: Update the `FrameRow(...)` call site in `FramesStrip.swift`**

Replace the `else { FrameRow(...) }` block inside the `ForEach` with:

```swift
} else {
    FrameRow(
        frame: frame,
        size: state.size,
        index: index,
        isActive: frame.id == state.frames[state.activeFrameIndex].id,
        frameCount: state.frames.count,
        onTap: {
            if renamingFrameID != nil && renamingFrameID != frame.id {
                commitRename()
            }
            if let idx = state.frames.firstIndex(where: { $0.id == frame.id }) {
                onActivateFrame(idx)
            }
        },
        onDuplicate: {
            if let idx = state.frames.firstIndex(where: { $0.id == frame.id }) {
                onActivateFrame(idx)
            }
            onDuplicateFrame()
        },
        onRename: {
            renamingFrameID = frame.id
            renameText = frame.name
        },
        onDelete: {
            if let idx = state.frames.firstIndex(where: { $0.id == frame.id }) {
                onActivateFrame(idx)
            }
            onDeleteFrame()
        },
        onMove: { from, to in onReorderFrame(from, to) }
    )
}
```

Rationale: `onDuplicateFrame`/`onDeleteFrame` act on the *active* frame, so the row first makes itself active (mirroring how DUPLICATE/DELETE always target the active frame), then invokes the action.

- [ ] **Step 3: Build to verify it compiles**

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual smoke test (simulator)**

Run the app, open a piece, tap ANIMATE. Verify: pixel-font uppercase labels match the toolbar; the strip shows PLAY / 12 FPS (speedometer) / ONION | frames | ADD with dividers; tapping 12 FPS opens a menu and selecting 60 sets it in one tap; ADD inserts a blank frame; long-pressing a frame shows Duplicate/Rename/Delete; dragging a frame reorders it; the active frame has a white ring + inverted number badge. Confirm taps still select frames (i.e. `.draggable` did not swallow taps). If taps are swallowed, see the fallback note below.

> **Fallback if `.draggable` interferes with tap or scroll:** wrap the tap in a `simultaneousGesture`, or gate the draggable behind the contextMenu's drag by removing the custom preview. The reorder can also be exposed as VoiceOver `accessibilityAction(named: "Move left"/"Move right")` calling `onMove`. Do not block the task on drag polish — selection, ADD, and the context menu are the must-pass behaviors.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Views/Editor/FrameRow.swift DrawBit/Views/Editor/FramesStrip.swift
git commit -m "feat(frames): number badges, context menu, drag-to-reorder on FrameRow"
```

---

## Task 5: Update UI tests

**Files:**
- Modify: `DrawBitUITests/AnimationStripUITests.swift`

The existing tests reference `FramesStrip.add` and `FrameRow.<UUID>` (both preserved) and do **not** reference the removed EDIT toggle, so they should still pass. Add one test for the new ADD-is-blank behavior and one asserting EDIT mode is gone.

- [ ] **Step 1: Add the new tests**

Append inside `final class AnimationStripUITests` (before the closing brace):

```swift
func testEditModeToggleIsGone() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
    app.launch()

    XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 5))
    app.buttons["NewButton"].tap()
    XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 3))
    app.buttons["NewPiece-32"].tap()

    let animate = app.buttons["Animate"]
    XCTAssertTrue(animate.waitForExistence(timeout: 5))
    animate.tap()

    XCTAssertTrue(app.buttons["FramesStrip.add"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["FramesStrip.editToggle"].exists,
                   "EDIT mode toggle must be removed from the strip")
}

func testAddInsertsBlankFrame() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
    app.launch()

    XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 5))
    app.buttons["NewButton"].tap()
    XCTAssertTrue(app.buttons["NewPiece-32"].waitForExistence(timeout: 3))
    app.buttons["NewPiece-32"].tap()

    let animate = app.buttons["Animate"]
    XCTAssertTrue(animate.waitForExistence(timeout: 5))
    animate.tap()

    let add = app.buttons["FramesStrip.add"]
    XCTAssertTrue(add.waitForExistence(timeout: 5))

    let frameRowsPredicate = NSPredicate(format: "identifier BEGINSWITH 'FrameRow.'")
    let before = app.buttons.matching(frameRowsPredicate).count
    add.tap()
    var grew = false
    for _ in 0..<10 {
        if app.buttons.matching(frameRowsPredicate).count > before { grew = true; break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    XCTAssertTrue(grew, "ADD must insert a new frame row")
    // Behavioral note: blank-vs-copy pixel content is asserted at the unit level
    // (FrameSequenceTests.testAddBlankFrameAfterInsertsEmptyFrame); the UI test
    // only verifies the button inserts a frame.
}
```

- [ ] **Step 2: Run the animation UI tests**

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitUITests/AnimationStripUITests
```
Expected: PASS (the four existing tests plus the two new ones). The onion-skin test (`testOnionSkinToggleGatedAndNotPersisted`) still relies on the `FramesStrip.onionSkin` identifier and the "Onion skin off"/"Onion skin on" labels, both preserved.

- [ ] **Step 3: Commit**

```bash
git add DrawBitUITests/AnimationStripUITests.swift
git commit -m "test(frames): cover ADD-is-blank and removed EDIT mode"
```

---

## Task 6: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```
Expected: all unit + UI tests pass (the established baseline is 248 unit + 8 UI; this plan adds 3 unit + 2 UI).

- [ ] **Step 2: Device compile-check (no signing)**

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Final manual pass**

Confirm against the spec's "What changes" list at the iPad Pro 13" simulator: fps menu, blank ADD, DUPLICATE/RENAME/DELETE context menu, drag reorder, ONION icon+label, no EDIT mode, corner number badges, pure-monochrome selection, and that the strip reads as the same visual family as the toolbar.

- [ ] **Step 4: Finish the branch**

Use the `superpowers:finishing-a-development-branch` skill to merge `animation-strip-redesign` into `main` (or open a PR), per the user's preference.

---

## Self-review

**Spec coverage:**
- Problem 1 (fps) → Task 3 fps `Menu`. ✓
- Problem 2 (add/duplicate) → Task 1 (`addBlankFrameAfter`) + Task 2 (wiring) + Task 4 (context-menu DUPLICATE). ✓
- Problem 3 (reorder) → Task 2 (`moveFrame`) + Task 4 (drag-and-drop). ✓
- Problem 4 (onion) → Task 3 (`square.2.layers.3d` + "ONION"). ✓
- Problem 5 (EDIT mode) → Task 3 (removed `isEditMode`/EDIT button). ✓
- Problem 6 (labels) → Task 4 (number badge + custom-name suppression). ✓
- Problem 7 (style) → Task 3 + Task 4 (`stripButton` mirrors `ToolBar.iconLabel`, dividers, monochrome). ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. ✓

**Type consistency:** `addBlankFrameAfter(frameID:in:)` (Task 1) matches its call in `EditorView.addBlankFrameAfter()` (Task 2). `FrameRow`'s new params (`index`, `frameCount`, `onDuplicate`, `onRename`, `onDelete`, `onMove`) match the call site in Task 4 Step 2. `FramesStrip`'s new signature (`onDeleteFrame` last; index-based `onReorderFrame`) matches the `EditorView` call site in Task 3 Step 2. `moveFrame(fromIndex:toIndex:)` is index-based and bound through `onReorderFrame: { moveFrame(fromIndex: $0, toIndex: $1) }`. ✓
```
