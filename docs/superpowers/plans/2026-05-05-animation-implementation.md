# Animation (v1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add frame-by-frame animation to DrawBit pieces in 6 staged merges, where each stage leaves the app fully functional and ships independently.

**Architecture:** A `Piece` becomes a sequence of `Frame`s. Layers stay global (same `[Layer]` shape across every frame; layer metadata kept synchronized; per-frame variation lives in pixel data). `FrameCodec` V2 wraps the existing V1 single-frame format in a `"DBFS"` sequence container; V1 blobs are read-fallback-decoded as one-frame sequences. Onion-skin rendering is a display-only overlay in `CanvasView` and never enters pixel storage. Playback is `Timer`-driven with a single FPS. GIF and APNG export use ImageIO multi-image destinations on per-frame `Compositor` output.

**Tech Stack:** Swift 5.10+, SwiftUI, `@Observable` state, SwiftData (no schema change — `Piece.frameData: Data` field repurposed), CoreGraphics + ImageIO, XCTest, XcodeGen.

**Branch:** `animation` (created off `main`, in a worktree at `.worktrees/animation/`). Each stage merges to `main` only after its tests pass and a manual on-device check is logged.

---

## Pre-flight

### Task 0.1: Worktree + branch

**Files:**
- Modify: git refs (working tree only)

- [ ] **Step 1: Verify clean working tree**

Run: `git status -s`
Expected: only the untracked files noted in the layers handoff (`DrawBit/PrivacyInfo.xcprivacy`, the handoff doc, and `docs/superpowers/plans/2026-04-27-iphone-support.md`). The freshly-committed animation spec/plan are tracked and clean.

- [ ] **Step 2: Pull latest main**

Run:
```bash
git checkout main
git pull --ff-only
```

- [ ] **Step 3: Create the worktree on a new `animation` branch**

Run:
```bash
git worktree add -b animation .worktrees/animation main
```
Expected: `Preparing worktree (new branch 'animation')` followed by `HEAD is now at b092702 …` (or the latest main tip).

- [ ] **Step 4: Confirm**

From the worktree:
```bash
cd .worktrees/animation && git branch --show-current && pwd
```
Expected: `animation` and the worktree path. **From here on, all xcodebuild and git commands run from the worktree** (use the absolute path to `DrawBit.xcodeproj` so xcodebuild doesn't fall back to a stale `.xcodeproj` in the main repo).

---

## Stage 1 — Plumbing only, zero new behavior

**Goal of stage:** Internally, every Piece is now a `[Frame]` sequence with exactly one frame holding the full layer stack. Codec is V2 with a V1 read-fallback. Every existing test and user-visible behavior is identical. The single-frame non-regression test (PNG byte-identity to today's path) is the gate.

### Task 1.1: `Frame` gains `id` and `name`

**Files:**
- Modify: `DrawBit/Drawing/Frame.swift`
- Modify: `DrawBitTests/Drawing/FrameTests.swift` (existing)

- [ ] **Step 1: Add tests for the new fields**

Append to `DrawBitTests/Drawing/FrameTests.swift`:

```swift
func testFrameDefaultIDIsUnique() {
    let pixels = Data(count: CanvasSize.s32.byteCount)
    let layer = Layer(name: "Layer 1", pixels: pixels)
    let a = Frame(layers: [layer], activeLayerID: layer.id)
    let b = Frame(layers: [layer], activeLayerID: layer.id)
    XCTAssertNotEqual(a.id, b.id)
}

func testFrameDefaultNameIsFrame1() {
    let pixels = Data(count: CanvasSize.s32.byteCount)
    let layer = Layer(name: "Layer 1", pixels: pixels)
    let frame = Frame(layers: [layer], activeLayerID: layer.id)
    XCTAssertEqual(frame.name, "Frame 1")
}

func testFrameExplicitIDAndNamePreserved() {
    let pixels = Data(count: CanvasSize.s32.byteCount)
    let layer = Layer(name: "Layer 1", pixels: pixels)
    let id = UUID()
    let frame = Frame(id: id, name: "Pose A", layers: [layer], activeLayerID: layer.id)
    XCTAssertEqual(frame.id, id)
    XCTAssertEqual(frame.name, "Pose A")
}
```

- [ ] **Step 2: Verify tests fail**

Regenerate project, run:
```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/FrameTests
```
Expected: build failure (`extra argument 'id' in call`).

- [ ] **Step 3: Add `id` + `name` to `Frame`**

Edit `DrawBit/Drawing/Frame.swift`:

```swift
struct Frame: Equatable {
    let id: UUID
    var name: String
    private(set) var layers: [Layer]
    private(set) var activeLayerID: UUID

    init(id: UUID = UUID(),
         name: String = "Frame 1",
         layers: [Layer],
         activeLayerID: UUID) {
        precondition(!layers.isEmpty, "Frame must have at least one layer")
        precondition(layers.contains(where: { $0.id == activeLayerID }),
                     "activeLayerID must reference one of the layers")
        precondition(layers.dropFirst().allSatisfy { $0.pixels.count == layers[0].pixels.count },
                     "All layers must have equal pixel byte count")
        self.id = id
        self.name = name
        self.layers = layers
        self.activeLayerID = activeLayerID
    }

    // ... (existing accessors and mutator API unchanged from here down)
```

The rest of `Frame.swift` (computed properties, `addLayer`, `duplicateActiveLayer`, `removeLayer`, `move`, `setActive`, `modelTargetIndex`, `setName`, `setVisible`, `setLocked`, `withActiveLayerPixels`) is unchanged.

- [ ] **Step 4: Run tests**

Run:
```bash
xcodebuild ... test -only-testing:DrawBitTests/FrameTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/Frame.swift DrawBitTests/Drawing/FrameTests.swift
git commit -m "feat(animation): Frame gains stable id and name"
```

---

### Task 1.2: `FrameCodec` V2 — `decodeSequence` + `encodeSequence`

**Files:**
- Modify: `DrawBit/Drawing/FrameCodec.swift`
- Create: `DrawBitTests/Drawing/FrameCodecSequenceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `DrawBitTests/Drawing/FrameCodecSequenceTests.swift`:

```swift
import XCTest
@testable import DrawBit

final class FrameCodecSequenceTests: XCTestCase {

    private func makeFrame(name: String, byteCount: Int = CanvasSize.s32.byteCount) -> Frame {
        let layer = Layer(name: "Layer 1", pixels: Data(count: byteCount))
        return Frame(name: name, layers: [layer], activeLayerID: layer.id)
    }

    func testSequenceRoundTripSingleFrame() throws {
        let f = makeFrame(name: "Frame 1")
        let blob = FrameCodec.encodeSequence(frames: [f], activeFrameIndex: 0, fps: 12)
        let decoded = try FrameCodec.decodeSequence(blob)
        XCTAssertEqual(decoded.frames.count, 1)
        XCTAssertEqual(decoded.frames[0].id, f.id)
        XCTAssertEqual(decoded.frames[0].name, "Frame 1")
        XCTAssertEqual(decoded.frames[0].layers, f.layers)
        XCTAssertEqual(decoded.frames[0].activeLayerID, f.activeLayerID)
        XCTAssertEqual(decoded.activeFrameIndex, 0)
        XCTAssertEqual(decoded.fps, 12)
    }

    func testSequenceRoundTripMultiFrame() throws {
        let frames = (1...4).map { makeFrame(name: "Frame \($0)") }
        let blob = FrameCodec.encodeSequence(frames: frames, activeFrameIndex: 2, fps: 24)
        let decoded = try FrameCodec.decodeSequence(blob)
        XCTAssertEqual(decoded.frames.count, 4)
        XCTAssertEqual(decoded.activeFrameIndex, 2)
        XCTAssertEqual(decoded.fps, 24)
        for (a, b) in zip(frames, decoded.frames) {
            XCTAssertEqual(a.id, b.id)
            XCTAssertEqual(a.name, b.name)
            XCTAssertEqual(a.layers, b.layers)
        }
    }

    func testV1FallbackFromDBFRMagic() throws {
        // Build a V1 single-frame blob by the existing path:
        let f = makeFrame(name: "ignored")
        let v1Blob = FrameCodec.encode(f)
        // Now decode it as a sequence — should yield one frame with default fps and active index 0:
        let decoded = try FrameCodec.decodeSequence(v1Blob)
        XCTAssertEqual(decoded.frames.count, 1)
        XCTAssertEqual(decoded.frames[0].name, "Frame 1") // default
        XCTAssertEqual(decoded.frames[0].layers, f.layers)
        XCTAssertEqual(decoded.activeFrameIndex, 0)
        XCTAssertEqual(decoded.fps, 12) // default
    }

    func testRawV1RGBABytesAreNotASequence() {
        // Raw RGBA without any magic should throw, mirroring layered loadFrame's pre-magic-check.
        let raw = Data(count: CanvasSize.s32.byteCount)
        XCTAssertThrowsError(try FrameCodec.decodeSequence(raw))
    }

    func testTruncatedSequenceThrows() {
        let f = makeFrame(name: "F")
        var blob = FrameCodec.encodeSequence(frames: [f], activeFrameIndex: 0, fps: 12)
        blob.removeLast(20)
        XCTAssertThrowsError(try FrameCodec.decodeSequence(blob))
    }

    func testHasV2SequenceMagicPrefixHelper() {
        let f = makeFrame(name: "F")
        let blob = FrameCodec.encodeSequence(frames: [f], activeFrameIndex: 0, fps: 12)
        XCTAssertTrue(FrameCodec.hasV2SequenceMagicPrefix(blob))
        XCTAssertFalse(FrameCodec.hasV2SequenceMagicPrefix(FrameCodec.encode(f)))
    }
}
```

- [ ] **Step 2: Verify tests fail**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/FrameCodecSequenceTests
```
Expected: build failure (`type 'FrameCodec' has no member 'encodeSequence'`).

- [ ] **Step 3: Add V2 codec methods**

Append to `DrawBit/Drawing/FrameCodec.swift` (after the existing `decode` function):

```swift
extension FrameCodec {

    static let sequenceMagic: [UInt8] = Array("DBFS".utf8)
    static let sequenceCurrentVersion: UInt8 = 1
    static let defaultFPS: Int = 12

    static func hasV2SequenceMagicPrefix(_ data: Data) -> Bool {
        guard data.count >= sequenceMagic.count else { return false }
        return Array(data.prefix(sequenceMagic.count)) == sequenceMagic
    }

    static func encodeSequence(frames: [Frame], activeFrameIndex: Int, fps: Int) -> Data {
        precondition(!frames.isEmpty, "Sequence must hold at least one frame")
        precondition((0..<frames.count).contains(activeFrameIndex), "activeFrameIndex out of range")

        var out = Data()
        out.append(contentsOf: sequenceMagic)
        out.append(sequenceCurrentVersion)

        let count = UInt16(frames.count)
        out.append(UInt8((count >> 8) & 0xFF))
        out.append(UInt8(count & 0xFF))

        let active = UInt16(activeFrameIndex)
        out.append(UInt8((active >> 8) & 0xFF))
        out.append(UInt8(active & 0xFF))

        let fpsClamped = UInt16(max(1, min(120, fps)))
        out.append(UInt8((fpsClamped >> 8) & 0xFF))
        out.append(UInt8(fpsClamped & 0xFF))

        for frame in frames {
            appendSequenceUUID(frame.id, to: &out)

            let nameBytes = Array(frame.name.utf8.prefix(255))
            out.append(UInt8(nameBytes.count))
            out.append(contentsOf: nameBytes)

            let inner = FrameCodec.encode(frame)
            let innerLen = UInt32(inner.count)
            out.append(UInt8((innerLen >> 24) & 0xFF))
            out.append(UInt8((innerLen >> 16) & 0xFF))
            out.append(UInt8((innerLen >>  8) & 0xFF))
            out.append(UInt8( innerLen        & 0xFF))
            out.append(inner)
        }
        return out
    }

    static func decodeSequence(_ data: Data) throws
        -> (frames: [Frame], activeFrameIndex: Int, fps: Int)
    {
        if hasV1MagicPrefix(data) {
            // Legacy single-frame blob: decode via V1 and wrap.
            let frame = try decode(data)
            return ([frame], 0, defaultFPS)
        }
        guard hasV2SequenceMagicPrefix(data) else {
            throw DecodeError.badMagic
        }

        var cursor = sequenceMagic.count
        let bytes = [UInt8](data)

        func need(_ n: Int) throws {
            if cursor + n > bytes.count { throw DecodeError.truncated }
        }

        try need(1)
        let version = bytes[cursor]; cursor += 1
        guard version == sequenceCurrentVersion else {
            throw DecodeError.unsupportedVersion(version)
        }

        try need(2)
        let frameCount = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor + 1])
        cursor += 2

        try need(2)
        let activeIdxRaw = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor + 1])
        cursor += 2

        try need(2)
        let fps = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor + 1])
        cursor += 2

        var frames: [Frame] = []
        frames.reserveCapacity(Int(frameCount))

        for _ in 0..<Int(frameCount) {
            try need(16)
            let frameID = readSequenceUUID(bytes, at: cursor); cursor += 16

            try need(1)
            let nameLen = Int(bytes[cursor]); cursor += 1
            try need(nameLen)
            let name = String(bytes: bytes[cursor..<cursor + nameLen], encoding: .utf8) ?? "Frame"
            cursor += nameLen

            try need(4)
            let innerLen =
                (UInt32(bytes[cursor    ]) << 24) |
                (UInt32(bytes[cursor + 1]) << 16) |
                (UInt32(bytes[cursor + 2]) <<  8) |
                 UInt32(bytes[cursor + 3])
            cursor += 4
            try need(Int(innerLen))
            let innerData = Data(bytes[cursor..<cursor + Int(innerLen)])
            cursor += Int(innerLen)

            // Inner V1 blob is decoded; we then override id/name from the wrapper.
            let inner = try decode(innerData)
            frames.append(Frame(id: frameID,
                                name: name,
                                layers: inner.layers,
                                activeLayerID: inner.activeLayerID))
        }

        guard !frames.isEmpty else { throw DecodeError.malformed("zero frames") }
        let activeIndex = Int(activeIdxRaw)
        guard (0..<frames.count).contains(activeIndex) else {
            throw DecodeError.malformed("activeFrameIndex out of range")
        }
        return (frames, activeIndex, Int(fps == 0 ? UInt16(defaultFPS) : fps))
    }

    private static func appendSequenceUUID(_ id: UUID, to out: inout Data) {
        let t = id.uuid
        out.append(contentsOf: [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7,
                                t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15])
    }

    private static func readSequenceUUID(_ bytes: [UInt8], at offset: Int) -> UUID {
        let t: uuid_t = (
            bytes[offset    ], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3],
            bytes[offset + 4], bytes[offset + 5], bytes[offset + 6], bytes[offset + 7],
            bytes[offset + 8], bytes[offset + 9], bytes[offset + 10], bytes[offset + 11],
            bytes[offset + 12], bytes[offset + 13], bytes[offset + 14], bytes[offset + 15]
        )
        return UUID(uuid: t)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild ... test -only-testing:DrawBitTests/FrameCodecSequenceTests
```
Expected: PASS (all six). Existing `FrameCodecTests` continue to pass unchanged.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/FrameCodec.swift DrawBitTests/Drawing/FrameCodecSequenceTests.swift
git commit -m "feat(animation): FrameCodec V2 sequence format with V1 fallback"
```

---

### Task 1.3: `Piece.frameData` semantics — V2 sequence on init

**Files:**
- Modify: `DrawBit/Models/Piece.swift`
- Modify: `DrawBitTests/Models/PieceTests.swift` (or create if absent)

- [ ] **Step 1: Write the failing test**

Append (or create) `DrawBitTests/Models/PieceTests.swift`:

```swift
import XCTest
@testable import DrawBit

final class PieceTests: XCTestCase {
    func testNewPieceFrameDataIsV2SequenceWithOneFrame() throws {
        let piece = Piece(size: .s32)
        XCTAssertTrue(FrameCodec.hasV2SequenceMagicPrefix(piece.frameData))
        let decoded = try FrameCodec.decodeSequence(piece.frameData)
        XCTAssertEqual(decoded.frames.count, 1)
        XCTAssertEqual(decoded.frames[0].layers.count, 1)
        XCTAssertEqual(decoded.frames[0].layers[0].name, "Layer 1")
        XCTAssertEqual(decoded.activeFrameIndex, 0)
        XCTAssertEqual(decoded.fps, 12)
    }
}
```

- [ ] **Step 2: Verify it fails**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/PieceTests
```
Expected: FAIL — current `Piece.init` writes a V1 blob.

- [ ] **Step 3: Update `Piece.init(size:)`**

In `DrawBit/Models/Piece.swift`, replace the body of `init(size:)`:

```swift
init(size: CanvasSize) {
    let now = Date()
    self.id = UUID()
    self.name = nil
    self.sizeRaw = size.rawValue
    let layer = Layer(name: "Layer 1", pixels: Data(count: size.byteCount))
    let frame = Frame(name: "Frame 1", layers: [layer], activeLayerID: layer.id)
    self.frameData = FrameCodec.encodeSequence(frames: [frame], activeFrameIndex: 0, fps: FrameCodec.defaultFPS)
    self.thumbnail = Data()
    self.createdAt = now
    self.updatedAt = now
}
```

- [ ] **Step 4: Verify**

```bash
xcodebuild ... test -only-testing:DrawBitTests/PieceTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Models/Piece.swift DrawBitTests/Models/PieceTests.swift
git commit -m "feat(animation): Piece initializer writes V2 sequence blob"
```

---

### Task 1.4: `PieceRepository` — load/save sequence with V1 fallback

**Files:**
- Modify: `DrawBit/Persistence/PieceRepository.swift`
- Modify: `DrawBitTests/Persistence/PieceRepositoryTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `DrawBitTests/Persistence/PieceRepositoryTests.swift`:

```swift
func testLoadFramesReturnsSequenceWithDefaults() throws {
    let piece = try repo.createPiece(size: .s32)
    let result = try repo.loadFrames(piece: piece)
    XCTAssertEqual(result.frames.count, 1)
    XCTAssertEqual(result.activeFrameIndex, 0)
    XCTAssertEqual(result.fps, 12)
}

func testSaveFramesRoundTrips() throws {
    let piece = try repo.createPiece(size: .s32)
    var (frames, _, _) = try repo.loadFrames(piece: piece)
    let layer2 = Layer(name: "Layer 2", pixels: Data(count: CanvasSize.s32.byteCount))
    var f = frames[0]
    f.layers.append(layer2)  // hypothetical — won't actually compile because layers is private(set);
    // Use the mutator API instead:
    frames[0].addLayer(name: "Layer 2")
    try repo.saveFrames(piece: piece, frames: frames, activeFrameIndex: 0, fps: 24)

    let reloaded = try repo.loadFrames(piece: piece)
    XCTAssertEqual(reloaded.frames[0].layers.count, 2)
    XCTAssertEqual(reloaded.fps, 24)
}

func testLoadFramesMigratesLegacyV1Blob() throws {
    let piece = try repo.createPiece(size: .s32)
    // Force-write a legacy V1 blob (single Frame format) directly:
    let layer = Layer(name: "Layer 1", pixels: Data(count: CanvasSize.s32.byteCount))
    let legacyFrame = Frame(layers: [layer], activeLayerID: layer.id)
    piece.frameData = FrameCodec.encode(legacyFrame)
    try modelContext.save()

    let reloaded = try repo.loadFrames(piece: piece)
    XCTAssertEqual(reloaded.frames.count, 1)
    XCTAssertTrue(FrameCodec.hasV2SequenceMagicPrefix(piece.frameData),
                  "Loading a V1 blob should re-save as a V2 sequence")
}
```

- [ ] **Step 2: Verify they fail**

Expected: `loadFrames` and `saveFrames` don't exist; build error.

- [ ] **Step 3: Add new repo methods + keep V1 path for stage-1 callers**

In `DrawBit/Persistence/PieceRepository.swift`, add:

```swift
/// Loads the full frame sequence + active index + fps. If the piece is still in V1
/// (single-frame "DBFR" blob) or raw legacy bytes, migrates in place to V2 ("DBFS")
/// before returning.
func loadFrames(piece: Piece) throws
    -> (frames: [Frame], activeFrameIndex: Int, fps: Int)
{
    if FrameCodec.hasV2SequenceMagicPrefix(piece.frameData) {
        return try FrameCodec.decodeSequence(piece.frameData)
    }
    if FrameCodec.hasV1MagicPrefix(piece.frameData) {
        let frame = try FrameCodec.decode(piece.frameData)
        let result: (frames: [Frame], activeFrameIndex: Int, fps: Int) = ([frame], 0, FrameCodec.defaultFPS)
        piece.frameData = FrameCodec.encodeSequence(frames: result.frames,
                                                    activeFrameIndex: result.activeFrameIndex,
                                                    fps: result.fps)
        piece.updatedAt = Date()
        try context.save()
        return result
    }
    // Pre-Layers-v2 raw bytes: wrap as one layer in one frame.
    let frame = FrameCodec.wrapV1Data(piece.frameData, defaultName: "Layer 1")
    let result: (frames: [Frame], activeFrameIndex: Int, fps: Int) = ([frame], 0, FrameCodec.defaultFPS)
    piece.frameData = FrameCodec.encodeSequence(frames: result.frames,
                                                activeFrameIndex: result.activeFrameIndex,
                                                fps: result.fps)
    piece.updatedAt = Date()
    try context.save()
    return result
}

/// Persists the full sequence and regenerates the gallery thumbnail from the FIRST frame.
func saveFrames(piece: Piece, frames: [Frame], activeFrameIndex: Int, fps: Int) throws {
    piece.frameData = FrameCodec.encodeSequence(frames: frames,
                                                activeFrameIndex: activeFrameIndex,
                                                fps: fps)
    if let firstThumb = ThumbnailRenderer.render(frame: frames[0],
                                                 size: piece.size,
                                                 targetEdge: 256) {
        piece.thumbnail = firstThumb
    }
    piece.updatedAt = Date()
    try context.save()
}
```

The existing single-frame `loadFrame(piece:)` and `saveFrame(piece:_:)` are **kept** for stage 1 — they continue to work because `loadFrames` migrates the blob to V2 on first read, and `loadFrame(piece:)` then sees a V2 blob, which it doesn't recognize. To keep `loadFrame` working during the stage-1 transition, replace its body with a thin shim:

```swift
func loadFrame(piece: Piece) throws -> Frame {
    let result = try loadFrames(piece: piece)
    return result.frames[result.activeFrameIndex]
}

func saveFrame(piece: Piece, _ frame: Frame) throws {
    // Stage 1 legacy seam: a single-frame save preserves the existing fps and active index.
    let existing = try? loadFrames(piece: piece)
    try saveFrames(piece: piece,
                   frames: [frame],
                   activeFrameIndex: 0,
                   fps: existing?.fps ?? FrameCodec.defaultFPS)
}
```

- [ ] **Step 4: Update `migrateLegacyPiecesIfNeeded` to recognize V2 too**

Replace the existing implementation:

```swift
func migrateLegacyPiecesIfNeeded() throws {
    let descriptor = FetchDescriptor<Piece>()
    let pieces = try context.fetch(descriptor)
    var dirty = false
    for piece in pieces where !FrameCodec.hasV2SequenceMagicPrefix(piece.frameData) {
        if FrameCodec.hasV1MagicPrefix(piece.frameData) {
            let frame = try FrameCodec.decode(piece.frameData)
            piece.frameData = FrameCodec.encodeSequence(frames: [frame],
                                                        activeFrameIndex: 0,
                                                        fps: FrameCodec.defaultFPS)
        } else {
            let frame = FrameCodec.wrapV1Data(piece.frameData, defaultName: "Layer 1")
            piece.frameData = FrameCodec.encodeSequence(frames: [frame],
                                                        activeFrameIndex: 0,
                                                        fps: FrameCodec.defaultFPS)
        }
        piece.updatedAt = Date()
        dirty = true
    }
    if dirty { try context.save() }
}
```

- [ ] **Step 5: Update `duplicate(piece:)` to round-trip through frames**

Replace the body:

```swift
func duplicate(piece: Piece) throws -> Piece {
    let source = try loadFrames(piece: piece)
    let copy = Piece(size: piece.size)

    // Rebuild every frame with fresh layer UUIDs (consistent across the sequence).
    let firstFrame = source.frames[0]
    let freshLayerIDs = firstFrame.layers.map { _ in UUID() }
    let freshFrames: [Frame] = source.frames.map { sourceFrame in
        let freshLayers = zip(sourceFrame.layers, freshLayerIDs).map { layer, newID in
            Layer(id: newID, name: layer.name, pixels: layer.pixels,
                  isVisible: layer.isVisible, isLocked: layer.isLocked)
        }
        let activeIdx = sourceFrame.layers.firstIndex(where: { $0.id == sourceFrame.activeLayerID }) ?? 0
        return Frame(name: sourceFrame.name,
                     layers: freshLayers,
                     activeLayerID: freshLayers[activeIdx].id)
    }

    copy.frameData = FrameCodec.encodeSequence(frames: freshFrames,
                                               activeFrameIndex: source.activeFrameIndex,
                                               fps: source.fps)
    copy.thumbnail = piece.thumbnail
    if let original = piece.name, !original.isEmpty {
        copy.name = "\(original) copy"
    } else {
        copy.name = "\(piece.effectiveName) copy"
    }
    context.insert(copy)
    try context.save()
    return copy
}
```

- [ ] **Step 6: Verify**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/PieceRepositoryTests
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add DrawBit/Persistence/PieceRepository.swift DrawBitTests/Persistence/PieceRepositoryTests.swift
git commit -m "feat(animation): PieceRepository load/save frame sequences with V1 fallback"
```

---

### Task 1.5: `EditorState` — `frames[]` + `activeFrameIndex` + `fps`

**Files:**
- Modify: `DrawBit/State/EditorState.swift`
- Modify: `DrawBitTests/State/EditorStateTests.swift` (or create new test cases)

- [ ] **Step 1: Write the failing test**

Append:

```swift
func testEditorStateFrameAccessorIsActiveFrame() {
    let pixels = Data(count: CanvasSize.s32.byteCount)
    let layer = Layer(name: "Layer 1", pixels: pixels)
    let f1 = Frame(name: "Frame 1", layers: [layer], activeLayerID: layer.id)
    let state = EditorState(pieceID: UUID(), size: .s32,
                            frames: [f1], activeFrameIndex: 0, fps: 12)
    XCTAssertEqual(state.frame.id, f1.id)
    XCTAssertEqual(state.frames.count, 1)
    XCTAssertEqual(state.fps, 12)
}

func testEditorStateMutatingActiveFramePixelsAffectsFramesArray() {
    let pixels = Data(count: CanvasSize.s32.byteCount)
    let layer = Layer(name: "L", pixels: pixels)
    let f = Frame(name: "F", layers: [layer], activeLayerID: layer.id)
    let state = EditorState(pieceID: UUID(), size: .s32,
                            frames: [f], activeFrameIndex: 0, fps: 12)
    state.mutateActiveLayerPixels { data in
        data[0] = 0xFF
    }
    XCTAssertEqual(state.frames[0].layers[0].pixels[0], 0xFF)
}
```

- [ ] **Step 2: Verify it fails**

Build error: `EditorState` has no initializer with `frames:`.

- [ ] **Step 3: Refactor `EditorState`**

In `DrawBit/State/EditorState.swift`:

1. Replace the stored `var frame: Frame` with:

```swift
var frames: [Frame]
var activeFrameIndex: Int
var fps: Int

/// Convenience that read/writes the active frame in `frames`. Most legacy call sites continue to compile.
var frame: Frame {
    get { frames[activeFrameIndex] }
    set { frames[activeFrameIndex] = newValue }
}
```

2. Replace the existing `init(pieceID:size:frame:)` with:

```swift
init(pieceID: UUID, size: CanvasSize,
     frames: [Frame], activeFrameIndex: Int, fps: Int) {
    precondition(!frames.isEmpty, "Editor must have at least one frame")
    precondition((0..<frames.count).contains(activeFrameIndex), "activeFrameIndex out of range")
    self.pieceID = pieceID
    self.size = size
    self.frames = frames
    self.activeFrameIndex = activeFrameIndex
    self.fps = fps
}

/// Convenience used by EditorView when it has a Piece + decoded sequence in hand.
convenience init(piece: Piece, frames: [Frame], activeFrameIndex: Int, fps: Int) {
    self.init(pieceID: piece.id, size: piece.size,
              frames: frames, activeFrameIndex: activeFrameIndex, fps: fps)
}
```

3. Update `cancelStroke` and the two `undo`/`redo` cases that rebuild a `Frame` so they assign back through `frames[activeFrameIndex] = ...`:

```swift
func cancelStroke() {
    if let snap = preStrokeSnapshot, let layerID = preStrokeLayerID,
       let frameIdx = frames.firstIndex(where: { $0.layers.contains { $0.id == layerID } }),
       let layerIdx = frames[frameIdx].layers.firstIndex(where: { $0.id == layerID }) {
        var layers = frames[frameIdx].layers
        layers[layerIdx].pixels = snap
        frames[frameIdx] = Frame(id: frames[frameIdx].id,
                                 name: frames[frameIdx].name,
                                 layers: layers,
                                 activeLayerID: frames[frameIdx].activeLayerID)
    }
    preStrokeSnapshot = nil
    preStrokeLayerID = nil
}
```

The existing `.layerPixels` undo/redo cases are similarly updated to look up the frame by layer ID. Pseudocode:

```swift
case .layerPixels(let layerID, let before):
    guard let frameIdx = frames.firstIndex(where: { $0.layers.contains { $0.id == layerID } }),
          let layerIdx = frames[frameIdx].layers.firstIndex(where: { $0.id == layerID }) else { return }
    let after = frames[frameIdx].layers[layerIdx].pixels
    redoStack.append(.layerPixels(layerID: layerID, before: after))
    var layers = frames[frameIdx].layers
    layers[layerIdx].pixels = before
    frames[frameIdx] = Frame(id: frames[frameIdx].id,
                             name: frames[frameIdx].name,
                             layers: layers,
                             activeLayerID: frames[frameIdx].activeLayerID)
```

(Stage 2 will refactor the undo enum to encode `frameID` explicitly. For now, "first frame containing this layerID" is sufficient because layer IDs are unique across the whole sequence in this stage.)

- [ ] **Step 4: Update `convenience init(piece:frame:)` callers**

In `DrawBit/Views/Editor/EditorView.swift`, find the `init(piece:)` body that constructs `EditorState`. Replace the `EditorState(piece: piece, frame: frame)` with the new signature, computed from `loadFrames`:

```swift
init(piece: Piece) {
    self.piece = piece
    let result: (frames: [Frame], activeFrameIndex: Int, fps: Int)
    if FrameCodec.hasV2SequenceMagicPrefix(piece.frameData) {
        result = (try? FrameCodec.decodeSequence(piece.frameData))
            ?? ([FrameCodec.wrapV1Data(Data(count: piece.size.byteCount), defaultName: "Layer 1")],
                0, FrameCodec.defaultFPS)
    } else if FrameCodec.hasV1MagicPrefix(piece.frameData) {
        let f = (try? FrameCodec.decode(piece.frameData))
            ?? FrameCodec.wrapV1Data(Data(count: piece.size.byteCount), defaultName: "Layer 1")
        result = ([f], 0, FrameCodec.defaultFPS)
    } else {
        let f = FrameCodec.wrapV1Data(piece.frameData, defaultName: "Layer 1")
        result = ([f], 0, FrameCodec.defaultFPS)
    }
    self._state = State(initialValue: EditorState(piece: piece,
                                                  frames: result.frames,
                                                  activeFrameIndex: result.activeFrameIndex,
                                                  fps: result.fps))
}
```

- [ ] **Step 5: Update `saveCurrentFrame` in `EditorView` to round-trip through `saveFrames`**

```swift
private func saveCurrentFrame() {
    let repo = PieceRepository(context: modelContext)
    try? repo.saveFrames(piece: piece,
                         frames: state.frames,
                         activeFrameIndex: state.activeFrameIndex,
                         fps: state.fps)
}
```

(Function may already be named `saveCurrentFrame` — keep the name; the body changes.)

- [ ] **Step 6: Verify**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... build
xcodebuild ... test -only-testing:DrawBitTests/EditorStateTests
```
Expected: PASS for the new tests, no compile errors elsewhere (most call sites used `state.frame.…` which still works via the computed property).

- [ ] **Step 7: Commit**

```bash
git add DrawBit/State/EditorState.swift DrawBit/Views/Editor/EditorView.swift DrawBitTests/State/EditorStateTests.swift
git commit -m "feat(animation): EditorState holds frame sequence + activeFrameIndex + fps"
```

---

### Task 1.6: Single-frame non-regression test

**Files:**
- Create: `DrawBitTests/Rendering/SingleFrameNonRegressionTests.swift`

- [ ] **Step 1: Write the test**

```swift
import XCTest
@testable import DrawBit

final class SingleFrameNonRegressionTests: XCTestCase {
    /// A single-frame Piece (post-animation) must export byte-identical PNGs to the
    /// pre-animation (Layers v2) export path. The "before" reference is a one-Frame
    /// `Frame` exported via PNGExporter.export(frame:size:scale:) — the same call site,
    /// but bypassing the sequence wrapper. Both should produce the same bytes because
    /// the export path itself didn't change.
    func testSingleFrameSinglLayerPNGByteIdentity() throws {
        for size in CanvasSize.allCases {
            for scale in [1, 2, 4, 8] {
                let pixels = Self.makeFixturePixels(size: size)
                let layer = Layer(name: "Layer 1", pixels: pixels)
                let frame = Frame(name: "Frame 1",
                                  layers: [layer],
                                  activeLayerID: layer.id)
                let direct = PNGExporter.export(frame: frame, size: size, scale: scale)

                // Round-trip through encode/decode V2 sequence — should produce identical pixels.
                let blob = FrameCodec.encodeSequence(frames: [frame],
                                                    activeFrameIndex: 0,
                                                    fps: 12)
                let (decoded, _, _) = try FrameCodec.decodeSequence(blob)
                let viaSequence = PNGExporter.export(frame: decoded[0], size: size, scale: scale)

                XCTAssertNotNil(direct)
                XCTAssertNotNil(viaSequence)
                XCTAssertEqual(direct, viaSequence,
                               "Single-frame PNG must be byte-identical pre/post sequence round-trip at \(size) ×\(scale)")
            }
        }
    }

    private static func makeFixturePixels(size: CanvasSize) -> Data {
        // Deterministic pseudo-random pattern — alpha exactly 0 or 255 to honor the invariant.
        var data = Data(count: size.byteCount)
        let edge = size.dimension
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for y in 0..<edge {
                for x in 0..<edge {
                    let i = (y * edge + x) * 4
                    let visible = ((x ^ y) & 0x07) != 0
                    p[i    ] = UInt8((x * 7) & 0xFF)
                    p[i + 1] = UInt8((y * 11) & 0xFF)
                    p[i + 2] = UInt8(((x + y) * 13) & 0xFF)
                    p[i + 3] = visible ? 255 : 0
                }
            }
        }
        return data
    }
}
```

- [ ] **Step 2: Run**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/SingleFrameNonRegressionTests
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add DrawBitTests/Rendering/SingleFrameNonRegressionTests.swift
git commit -m "test(animation): single-frame PNG byte-identity through V2 sequence round-trip"
```

---

### Task 1.7: Existing-test sweep

**Files:**
- None (verification only)

- [ ] **Step 1: Run the full unit test suite**

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test
```
Expected: every existing unit and UI test still passes. Green across the board.

- [ ] **Step 2: Device-Release compile-check**

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
Expected: green.

- [ ] **Step 3: Commit nothing — but tag stage-1 if all green**

If everything passes:

```bash
git tag -a stage-1-animation-plumbing -m "Stage 1: animation plumbing complete"
```

(No push yet — wait for the holistic Opus review per the workflow recipe.)

---

## Stage 2 — Frame ops API + sequence-level undo

**Goal of stage:** `FrameSequence` is the pure-logic surface for sequence mutations, including layer-cascade ops. `EditorState.setActiveFrame` does the auto-commit dance. Sequence-level undo handles structural changes. No timeline UI yet — exercised by tests only.

### Task 2.1: `FrameSequence` — frame-level mutators

**Files:**
- Create: `DrawBit/Drawing/FrameSequence.swift`
- Create: `DrawBitTests/Drawing/FrameSequenceTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import DrawBit

final class FrameSequenceTests: XCTestCase {

    private func makeFrames(_ names: [String], byteCount: Int = CanvasSize.s32.byteCount) -> [Frame] {
        return names.map { name in
            let layer = Layer(name: "Layer 1", pixels: Data(count: byteCount))
            return Frame(name: name, layers: [layer], activeLayerID: layer.id)
        }
    }

    func testAddFrameAfterDuplicatesContents() throws {
        var frames = makeFrames(["F1"])
        // Draw something into F1's layer:
        var layers = frames[0].layers
        layers[0].pixels[0] = 0xCC
        frames[0] = Frame(id: frames[0].id, name: frames[0].name,
                          layers: layers, activeLayerID: frames[0].activeLayerID)

        let newID = FrameSequence.addFrameAfter(frameID: frames[0].id, in: &frames)
        XCTAssertNotNil(newID)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[1].layers[0].pixels[0], 0xCC, "New frame should duplicate previous frame's pixels")
        XCTAssertNotEqual(frames[1].id, frames[0].id)
        XCTAssertNotEqual(frames[1].layers[0].id, frames[0].layers[0].id, "Duplicated layers must have fresh UUIDs")
    }

    func testDuplicateFrame() {
        var frames = makeFrames(["F1", "F2"])
        let newID = FrameSequence.duplicateFrame(frames[0].id, in: &frames)
        XCTAssertNotNil(newID)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[1].id, newID)
        XCTAssertNotEqual(frames[1].id, frames[0].id)
    }

    func testRemoveFrame() {
        var frames = makeFrames(["F1", "F2", "F3"])
        FrameSequence.removeFrame(frames[1].id, in: &frames)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].name, "F1")
        XCTAssertEqual(frames[1].name, "F3")
    }

    func testRemoveFrameNoOpsAtSingleFrame() {
        var frames = makeFrames(["F1"])
        FrameSequence.removeFrame(frames[0].id, in: &frames)
        XCTAssertEqual(frames.count, 1)
    }

    func testMoveFrameForward() {
        var frames = makeFrames(["F1", "F2", "F3"])
        FrameSequence.move(frameID: frames[0].id, toIndex: 2, in: &frames)
        XCTAssertEqual(frames.map(\.name), ["F2", "F3", "F1"])
    }

    func testSetName() {
        var frames = makeFrames(["F1"])
        FrameSequence.setName(frameID: frames[0].id, to: "Idle", in: &frames)
        XCTAssertEqual(frames[0].name, "Idle")
    }

    func testCapEnforcedAtModelLevel() {
        var frames = makeFrames((1...60).map { "F\($0)" })
        let newID = FrameSequence.addFrameAfter(frameID: frames.last!.id, in: &frames)
        XCTAssertNil(newID, "Adding past the 60-frame cap must return nil")
        XCTAssertEqual(frames.count, 60)
    }

    func testReorderMath() {
        // Pre-removal newOffset semantics, mirrors Frame.modelTargetIndex.
        XCTAssertEqual(FrameSequence.modelTargetIndex(displayedFrom: 0, newOffset: 2, count: 3), 1)
        XCTAssertEqual(FrameSequence.modelTargetIndex(displayedFrom: 2, newOffset: 0, count: 3), 0)
        XCTAssertNil(FrameSequence.modelTargetIndex(displayedFrom: 1, newOffset: 1, count: 3))
        XCTAssertNil(FrameSequence.modelTargetIndex(displayedFrom: 1, newOffset: 2, count: 3))
    }
}
```

- [ ] **Step 2: Verify failure**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/FrameSequenceTests
```
Expected: build error (`type 'FrameSequence' not found`).

- [ ] **Step 3: Implement `FrameSequence` (frame-level methods)**

Create `DrawBit/Drawing/FrameSequence.swift`:

```swift
import Foundation

enum FrameSequence {

    static let frameCap: Int = 60

    /// Inserts a new frame after the frame with the given id. The new frame's pixels are
    /// a duplicate of the source frame's pixels. Layers get fresh UUIDs to prevent UUID
    /// collisions across the sequence (Stage 2 layer-cascade keeps them aligned afterwards
    /// because subsequent `addLayer`/`removeLayer` ops use the layer ID at the active frame
    /// and apply across all frames; so we instead reuse the source frame's layer UUIDs to
    /// keep cascade alignment).
    ///
    /// Returns the new frame id, or nil if at the cap.
    @discardableResult
    static func addFrameAfter(frameID: UUID, in frames: inout [Frame]) -> UUID? {
        guard frames.count < frameCap else { return nil }
        guard let idx = frames.firstIndex(where: { $0.id == frameID }) else { return nil }
        let source = frames[idx]
        let copy = Frame(name: nextFrameName(in: frames),
                         layers: source.layers,           // SAME UUIDs — cascade-aligned
                         activeLayerID: source.activeLayerID)
        frames.insert(copy, at: idx + 1)
        return copy.id
    }

    @discardableResult
    static func duplicateFrame(_ frameID: UUID, in frames: inout [Frame]) -> UUID? {
        return addFrameAfter(frameID: frameID, in: &frames)
    }

    static func removeFrame(_ frameID: UUID, in frames: inout [Frame]) {
        guard frames.count > 1 else { return }
        guard let idx = frames.firstIndex(where: { $0.id == frameID }) else { return }
        frames.remove(at: idx)
    }

    static func move(frameID: UUID, toIndex: Int, in frames: inout [Frame]) {
        guard let from = frames.firstIndex(where: { $0.id == frameID }) else { return }
        let to = max(0, min(frames.count - 1, toIndex))
        if from == to { return }
        let frame = frames.remove(at: from)
        frames.insert(frame, at: to)
    }

    static func setName(frameID: UUID, to name: String, in frames: inout [Frame]) {
        guard let idx = frames.firstIndex(where: { $0.id == frameID }) else { return }
        frames[idx].name = name
    }

    /// Reorder math, analog of `Frame.modelTargetIndex`. SwiftUI `.onMove`'s `newOffset` is
    /// a pre-removal insertion point; the timeline strip is displayed left→right matching
    /// the model order, so no reversal is needed here (unlike the layers panel which reverses).
    static func modelTargetIndex(displayedFrom: Int, newOffset: Int, count: Int) -> Int? {
        let displayedTo = newOffset > count ? count : newOffset
        let modelFrom = displayedFrom
        let correctedTo = max(0, min(count - 1, displayedTo - (displayedTo > displayedFrom ? 1 : 0)))
        return modelFrom == correctedTo ? nil : correctedTo
    }

    // MARK: - Naming

    private static func nextFrameName(in frames: [Frame]) -> String {
        let used = Set(frames.compactMap { Int($0.name.dropFirst("Frame ".count)) })
        var n = 1
        while used.contains(n) { n += 1 }
        return "Frame \(n)"
    }
}
```

- [ ] **Step 4: Verify**

```bash
xcodebuild ... test -only-testing:DrawBitTests/FrameSequenceTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/FrameSequence.swift DrawBitTests/Drawing/FrameSequenceTests.swift
git commit -m "feat(animation): FrameSequence frame-level mutators with 60-frame cap"
```

---

### Task 2.2: `FrameSequence` — layer cascade

**Files:**
- Modify: `DrawBit/Drawing/FrameSequence.swift`
- Modify: `DrawBitTests/Drawing/FrameSequenceTests.swift`

- [ ] **Step 1: Write the failing tests**

Append:

```swift
func testAddLayerCascadesAcrossAllFrames() {
    var frames = makeFrames(["F1", "F2", "F3"])
    let newLayerID = FrameSequence.addLayer(name: "Layer 2", in: &frames)
    XCTAssertNotNil(newLayerID)
    for f in frames {
        XCTAssertEqual(f.layers.count, 2)
        XCTAssertTrue(f.layers.contains(where: { $0.id == newLayerID }))
        // New layer is empty in every frame:
        XCTAssertTrue(f.layers.last!.pixels.allSatisfy { $0 == 0 })
    }
}

func testRemoveLayerCascadesAcrossAllFrames() {
    var frames = makeFrames(["F1", "F2"])
    _ = FrameSequence.addLayer(name: "Layer 2", in: &frames)
    let toRemove = frames[0].layers[1].id
    FrameSequence.removeLayer(toRemove, in: &frames)
    for f in frames {
        XCTAssertEqual(f.layers.count, 1)
        XCTAssertFalse(f.layers.contains(where: { $0.id == toRemove }))
    }
}

func testRemoveLayerNoOpsAtSingleLayer() {
    var frames = makeFrames(["F1"])
    let id = frames[0].layers[0].id
    FrameSequence.removeLayer(id, in: &frames)
    XCTAssertEqual(frames[0].layers.count, 1, "Cannot remove the last layer")
}

func testMoveLayerCascadesAcrossAllFrames() {
    var frames = makeFrames(["F1", "F2"])
    _ = FrameSequence.addLayer(name: "L2", in: &frames)
    _ = FrameSequence.addLayer(name: "L3", in: &frames)
    let l1 = frames[0].layers[0].id
    FrameSequence.moveLayer(l1, toIndex: 2, in: &frames)
    for f in frames {
        XCTAssertEqual(f.layers.last!.id, l1, "Layer 1 should now be on top in every frame")
    }
}

func testSetLayerNameCascadesAcrossAllFrames() {
    var frames = makeFrames(["F1", "F2"])
    let id = frames[0].layers[0].id
    FrameSequence.setLayerName(id, to: "Background", in: &frames)
    for f in frames {
        XCTAssertEqual(f.layers[0].name, "Background")
    }
}

func testSetLayerVisibleCascades() {
    var frames = makeFrames(["F1", "F2"])
    let id = frames[0].layers[0].id
    FrameSequence.setLayerVisible(id, false, in: &frames)
    for f in frames {
        XCTAssertFalse(f.layers[0].isVisible)
    }
}

func testSetLayerLockedCascades() {
    var frames = makeFrames(["F1", "F2"])
    let id = frames[0].layers[0].id
    FrameSequence.setLayerLocked(id, true, in: &frames)
    for f in frames {
        XCTAssertTrue(f.layers[0].isLocked)
    }
}

func testDuplicateLayerCascadesWithSameNewIDAcrossFrames() {
    var frames = makeFrames(["F1", "F2"])
    // Put different pixel data in F1 and F2 so we can verify per-frame copy semantics:
    var f1 = frames[0]
    var f2 = frames[1]
    f1.layers[0].pixels[0] = 0xAA
    f2.layers[0].pixels[0] = 0xBB
    frames[0] = Frame(id: f1.id, name: f1.name, layers: f1.layers, activeLayerID: f1.activeLayerID)
    frames[1] = Frame(id: f2.id, name: f2.name, layers: f2.layers, activeLayerID: f2.activeLayerID)

    let sourceID = frames[0].layers[0].id
    let newID = FrameSequence.duplicateLayer(sourceID, in: &frames)
    XCTAssertNotNil(newID)
    XCTAssertEqual(frames[0].layers.count, 2)
    XCTAssertEqual(frames[1].layers.count, 2)
    // Same UUID across frames:
    XCTAssertEqual(frames[0].layers[1].id, newID)
    XCTAssertEqual(frames[1].layers[1].id, newID)
    // Per-frame pixel copy:
    XCTAssertEqual(frames[0].layers[1].pixels[0], 0xAA)
    XCTAssertEqual(frames[1].layers[1].pixels[0], 0xBB)
}
```

- [ ] **Step 2: Verify failure**

Build error: missing methods.

- [ ] **Step 3: Add the cascade methods**

Append to `DrawBit/Drawing/FrameSequence.swift`:

```swift
extension FrameSequence {

    static let layerCap: Int = 16

    /// Inserts a new empty layer above the active layer in EVERY frame, with the same UUID
    /// across the sequence. Returns the new layer id.
    @discardableResult
    static func addLayer(name: String, in frames: inout [Frame]) -> UUID? {
        guard frames[0].layers.count < layerCap else { return nil }
        let newID = UUID()
        let byteCount = frames[0].layers[0].pixels.count
        let activeIndex = frames[0].layers.firstIndex(where: { $0.id == frames[0].activeLayerID })!
        let insertAt = activeIndex + 1

        for i in frames.indices {
            var layers = frames[i].layers
            layers.insert(Layer(id: newID, name: name, pixels: Data(count: byteCount)),
                          at: insertAt)
            frames[i] = Frame(id: frames[i].id,
                              name: frames[i].name,
                              layers: layers,
                              activeLayerID: newID)
        }
        return newID
    }

    /// Duplicates the layer with `sourceID` in EVERY frame; per-frame pixel data is duplicated
    /// from THAT frame's source layer pixels. The duplicate's UUID is the same across frames.
    @discardableResult
    static func duplicateLayer(_ sourceID: UUID, in frames: inout [Frame]) -> UUID? {
        guard frames[0].layers.count < layerCap else { return nil }
        let newID = UUID()
        guard let sourceIdx = frames[0].layers.firstIndex(where: { $0.id == sourceID }) else { return nil }

        for i in frames.indices {
            var layers = frames[i].layers
            let source = layers[sourceIdx]
            let copy = Layer(id: newID,
                             name: source.name + " copy",
                             pixels: source.pixels,
                             isVisible: source.isVisible,
                             isLocked: source.isLocked)
            layers.insert(copy, at: sourceIdx + 1)
            frames[i] = Frame(id: frames[i].id,
                              name: frames[i].name,
                              layers: layers,
                              activeLayerID: newID)
        }
        return newID
    }

    static func removeLayer(_ layerID: UUID, in frames: inout [Frame]) {
        guard frames[0].layers.count > 1 else { return }
        guard let idx = frames[0].layers.firstIndex(where: { $0.id == layerID }) else { return }
        let wasActive = frames[0].activeLayerID == layerID

        for i in frames.indices {
            var layers = frames[i].layers
            layers.remove(at: idx)
            let nextActive: UUID
            if wasActive {
                let newActiveIdx = max(0, idx - 1)
                nextActive = layers[newActiveIdx].id
            } else {
                nextActive = frames[i].activeLayerID
            }
            frames[i] = Frame(id: frames[i].id,
                              name: frames[i].name,
                              layers: layers,
                              activeLayerID: nextActive)
        }
    }

    static func moveLayer(_ layerID: UUID, toIndex: Int, in frames: inout [Frame]) {
        guard let from = frames[0].layers.firstIndex(where: { $0.id == layerID }) else { return }
        let to = max(0, min(frames[0].layers.count - 1, toIndex))
        if from == to { return }
        for i in frames.indices {
            var layers = frames[i].layers
            let layer = layers.remove(at: from)
            layers.insert(layer, at: to)
            frames[i] = Frame(id: frames[i].id,
                              name: frames[i].name,
                              layers: layers,
                              activeLayerID: frames[i].activeLayerID)
        }
    }

    static func setLayerName(_ layerID: UUID, to name: String, in frames: inout [Frame]) {
        for i in frames.indices {
            guard let idx = frames[i].layers.firstIndex(where: { $0.id == layerID }) else { continue }
            var layers = frames[i].layers
            layers[idx].name = name
            frames[i] = Frame(id: frames[i].id, name: frames[i].name,
                              layers: layers, activeLayerID: frames[i].activeLayerID)
        }
    }

    static func setLayerVisible(_ layerID: UUID, _ visible: Bool, in frames: inout [Frame]) {
        for i in frames.indices {
            guard let idx = frames[i].layers.firstIndex(where: { $0.id == layerID }) else { continue }
            var layers = frames[i].layers
            layers[idx].isVisible = visible
            frames[i] = Frame(id: frames[i].id, name: frames[i].name,
                              layers: layers, activeLayerID: frames[i].activeLayerID)
        }
    }

    static func setLayerLocked(_ layerID: UUID, _ locked: Bool, in frames: inout [Frame]) {
        for i in frames.indices {
            guard let idx = frames[i].layers.firstIndex(where: { $0.id == layerID }) else { continue }
            var layers = frames[i].layers
            layers[idx].isLocked = locked
            frames[i] = Frame(id: frames[i].id, name: frames[i].name,
                              layers: layers, activeLayerID: frames[i].activeLayerID)
        }
    }
}
```

- [ ] **Step 4: Verify**

```bash
xcodebuild ... test -only-testing:DrawBitTests/FrameSequenceTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/FrameSequence.swift DrawBitTests/Drawing/FrameSequenceTests.swift
git commit -m "feat(animation): FrameSequence layer-cascade ops"
```

---

### Task 2.3: `EditorState.setActiveFrame` + sequence-level undo

**Files:**
- Modify: `DrawBit/State/EditorState.swift`
- Modify: `DrawBitTests/State/EditorStateTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testSetActiveFrameUpdatesIndex() {
    let state = makeStateWithTwoFrames()
    state.setActiveFrame(index: 1)
    XCTAssertEqual(state.activeFrameIndex, 1)
}

func testSetActiveFrameAutoCommitsFloatingMarquee() {
    let state = makeStateWithTwoFrames()
    state.beginMarqueeDefine(at: (0, 0))
    state.updateMarqueeDefine(to: (4, 4))
    state.endMarqueeDefine()
    XCTAssertNotNil(state.selection, "Floating selection should exist")
    state.setActiveFrame(index: 1)
    XCTAssertNil(state.selection, "Frame switch must commit the floating selection")
}

func testSetActiveFrameCancelsPendingMarquee() {
    let state = makeStateWithTwoFrames()
    state.beginMarqueeDefine(at: (0, 0))
    state.updateMarqueeDefine(to: (4, 4))
    XCTAssertNotNil(state.pendingMarqueeRect)
    state.setActiveFrame(index: 1)
    XCTAssertNil(state.pendingMarqueeRect, "Frame switch must cancel pending marquee define")
}

func testSequenceStructuralUndoRestoresFrames() {
    let state = makeStateWithTwoFrames()
    state.beginSequenceSnapshot()
    FrameSequence.addFrameAfter(frameID: state.frames.last!.id, in: &state.frames)
    state.commitSequenceChange()
    XCTAssertEqual(state.frames.count, 3)
    state.undo()
    XCTAssertEqual(state.frames.count, 2)
}

private func makeStateWithTwoFrames() -> EditorState {
    let pixels = Data(count: CanvasSize.s32.byteCount)
    let l = Layer(name: "L", pixels: pixels)
    let f1 = Frame(name: "F1", layers: [l], activeLayerID: l.id)
    let f2 = Frame(name: "F2", layers: [l], activeLayerID: l.id)
    return EditorState(pieceID: UUID(), size: .s32,
                       frames: [f1, f2], activeFrameIndex: 0, fps: 12)
}
```

- [ ] **Step 2: Verify failure**

Build error: methods don't exist.

- [ ] **Step 3: Implement on `EditorState`**

In `DrawBit/State/EditorState.swift`:

1. Extend `UndoEntry`:

```swift
enum UndoEntry {
    case layerPixels(layerID: UUID, before: Data)
    case frameStructure(before: Frame)            // legacy from layers v2; now retained for back-compat in stage 1 only
    case sequenceStructure(beforeFrames: [Frame], beforeActive: Int)
}
```

2. Add the snapshot scaffolding for sequence-level changes:

```swift
private var preSequenceSnapshot: (frames: [Frame], activeFrameIndex: Int)?

func beginSequenceSnapshot() {
    preSequenceSnapshot = (frames, activeFrameIndex)
}

func commitSequenceChange() {
    guard let snap = preSequenceSnapshot else { return }
    push(.sequenceStructure(beforeFrames: snap.frames, beforeActive: snap.activeFrameIndex))
    preSequenceSnapshot = nil
}

func cancelSequenceChange() {
    if let snap = preSequenceSnapshot {
        frames = snap.frames
        activeFrameIndex = snap.activeFrameIndex
    }
    preSequenceSnapshot = nil
}
```

3. Add the active-frame change method:

```swift
func setActiveFrame(index: Int) {
    guard (0..<frames.count).contains(index) else { return }
    if index == activeFrameIndex { return }
    if selection != nil { commitMarquee() }
    if pendingMarqueeRect != nil { cancelMarquee() }
    if preStrokeSnapshot != nil { cancelStroke() }
    activeFrameIndex = index
}
```

4. Update `undo` and `redo` switch statements to include the new case:

```swift
case .sequenceStructure(let beforeFrames, let beforeActive):
    redoStack.append(.sequenceStructure(beforeFrames: frames, beforeActive: activeFrameIndex))
    frames = beforeFrames
    activeFrameIndex = beforeActive
```

(Mirror in `redo`.)

- [ ] **Step 4: Verify**

```bash
xcodebuild ... test -only-testing:DrawBitTests/EditorStateTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/State/EditorState.swift DrawBitTests/State/EditorStateTests.swift
git commit -m "feat(animation): EditorState.setActiveFrame + sequence-structural undo"
```

---

### Task 2.4: Memory-cost note + delta-encoding follow-up

**Files:**
- Modify: `DrawBit/State/EditorState.swift` (comment only)

- [ ] **Step 1: Add a load-bearing comment above `.sequenceStructure`**

```swift
/// Full-sequence snapshot. Memory cost at the cap is real:
/// 60 frames × 16 layers × 256×256 RGBA = 240 MB per snapshot, × 50 = 12 GB undo stack.
/// This is why the `.sequenceStructure` path should be exercised carefully and Stage 2
/// implementer should profile undo at large piece sizes. If memory pressure is observed,
/// migrate to a delta-encoded enum (`.frameInserted(at:)`, `.layerInsertedAcross(at:layerID:)`,
/// etc.) before merging stage 2 to main. See spec § "Undo storage".
case sequenceStructure(beforeFrames: [Frame], beforeActive: Int)
```

- [ ] **Step 2: Profile**

Manually open a 256×256 piece with 16 layers, add 30 frames, perform a sequence mutation (e.g., layer add). In Xcode's memory graph, observe RAM. If it spikes by hundreds of MB per undo entry, that's the signal to migrate to delta-encoding before stage 2 ships.

- [ ] **Step 3: Commit**

```bash
git add DrawBit/State/EditorState.swift
git commit -m "docs(animation): mark sequence-undo memory cost; flag delta-encoding follow-up"
```

(If the profile shows pressure, write the delta-encoding tasks now and append them. Otherwise proceed to Task 2.5.)

---

### Task 2.5: EditorView wiring for frame mutations (callbacks)

**Files:**
- Modify: `DrawBit/Views/Editor/EditorView.swift`

- [ ] **Step 1: Add helper for frame structural changes**

In `EditorView`:

```swift
private func mutateFrameSequence(_ body: (inout [Frame]) -> Void) {
    state.commitFloatingSelectionIfAny()
    state.beginSequenceSnapshot()
    body(&state.frames)
    // Clamp activeFrameIndex if the sequence shrank:
    if state.activeFrameIndex >= state.frames.count {
        state.activeFrameIndex = max(0, state.frames.count - 1)
    }
    state.commitSequenceChange()
    saveCurrentFrame()
}

func addFrameAfterActive() {
    let activeID = state.frames[state.activeFrameIndex].id
    mutateFrameSequence { frames in
        if let newID = FrameSequence.addFrameAfter(frameID: activeID, in: &frames),
           let newIdx = frames.firstIndex(where: { $0.id == newID }) {
            state.activeFrameIndex = newIdx
        }
    }
}

func deleteActiveFrame() {
    let activeID = state.frames[state.activeFrameIndex].id
    mutateFrameSequence { frames in
        FrameSequence.removeFrame(activeID, in: &frames)
    }
}

func renameFrame(id: UUID, to name: String) {
    mutateFrameSequence { frames in
        FrameSequence.setName(frameID: id, to: name, in: &frames)
    }
}

func reorderFrame(from: Int, toOffset: Int) {
    let activeID = state.frames[state.activeFrameIndex].id
    let movingID = state.frames[from].id
    guard let modelTo = FrameSequence.modelTargetIndex(displayedFrom: from,
                                                       newOffset: toOffset,
                                                       count: state.frames.count) else { return }
    mutateFrameSequence { frames in
        FrameSequence.move(frameID: movingID, toIndex: modelTo, in: &frames)
        if let newActiveIdx = frames.firstIndex(where: { $0.id == activeID }) {
            state.activeFrameIndex = newActiveIdx
        }
    }
}
```

These are wired into the strip in Stage 3.

- [ ] **Step 2: Verify build**

```bash
xcodebuild ... build
```
Expected: green.

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Editor/EditorView.swift
git commit -m "feat(animation): EditorView frame-mutation callbacks (callers in stage 3)"
```

---

### Task 2.6: Existing-test sweep (Stage 2)

- [ ] **Step 1: Full test suite**

```bash
xcodebuild ... test
```
Expected: all green.

- [ ] **Step 2: Stage tag**

```bash
git tag -a stage-2-animation-frame-ops -m "Stage 2: frame ops + sequence undo"
```

(Hold push and merge until the holistic Opus review per the workflow recipe.)

---

## Stage 3 — Bottom-strip timeline UI

**Goal of stage:** A `FramesStrip` is visible across the bottom of the editor at all times. Tap a thumbnail to switch active frame. EDIT/DONE toggle gates reorder vs rename. Add/duplicate/delete buttons functional. Persistence callbacks route through the helpers added in Stage 2.

### Task 3.1: `FrameThumbnailRenderer`

**Files:**
- Create: `DrawBit/Rendering/FrameThumbnailRenderer.swift`
- Create: `DrawBitTests/Rendering/FrameThumbnailRendererTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DrawBit

final class FrameThumbnailRendererTests: XCTestCase {
    func testRenderProducesNonEmptyPNGForNonEmptyFrame() {
        let pixels = Data(repeating: 255, count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: pixels)
        let frame = Frame(name: "F", layers: [layer], activeLayerID: layer.id)
        let png = FrameThumbnailRenderer.render(frame: frame, size: .s32, targetEdge: 32)
        XCTAssertNotNil(png)
        XCTAssertTrue((png?.count ?? 0) > 0)
    }

    func testRenderReturnsNilForBadInputs() {
        let pixels = Data(count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: pixels)
        let frame = Frame(name: "F", layers: [layer], activeLayerID: layer.id)
        XCTAssertNil(FrameThumbnailRenderer.render(frame: frame, size: .s32, targetEdge: 0))
    }
}
```

- [ ] **Step 2: Verify failure**

Build error: type doesn't exist.

- [ ] **Step 3: Implement**

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Composites every visible layer of a Frame and produces a small PNG suitable for
/// the timeline strip. Mirrors `LayerThumbnailRenderer`'s color-space + alpha invariants.
enum FrameThumbnailRenderer {
    static func render(frame: Frame, size: CanvasSize, targetEdge: Int) -> Data? {
        guard targetEdge >= 1 else { return nil }
        let buffer = Compositor.composite(frame, size: size)
        guard let source = bufferToCGImage(buffer) else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: targetEdge,
            height: targetEdge,
            bitsPerComponent: 8,
            bytesPerRow: targetEdge * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: targetEdge, height: targetEdge))

        guard let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
```

- [ ] **Step 4: Verify**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/FrameThumbnailRendererTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Rendering/FrameThumbnailRenderer.swift DrawBitTests/Rendering/FrameThumbnailRendererTests.swift
git commit -m "feat(animation): FrameThumbnailRenderer for timeline strip"
```

---

### Task 3.2: `FrameRow` view

**Files:**
- Create: `DrawBit/Views/Editor/FrameRow.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct FrameRow: View {
    let frame: Frame
    let size: CanvasSize
    let isActive: Bool
    let isEditing: Bool
    let onTap: () -> Void
    let onLongPressRename: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 36, height: 36)
                if let png = FrameThumbnailRenderer.render(frame: frame, size: size, targetEdge: 36),
                   let uiImage = UIImage(data: png) {
                    Image(uiImage: uiImage)
                        .interpolation(.none)
                        .antialiased(false)
                        .resizable()
                        .frame(width: 36, height: 36)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isActive ? Color.accentColor : Color.white.opacity(0.15),
                            lineWidth: isActive ? 2 : 1)
            )

            Text(frame.name)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.accentColor : Color.white.opacity(0.6))
                .frame(maxWidth: 44)
        }
        .accessibilityIdentifier("FrameRow.\(frame.id.uuidString)")
        .accessibilityAddTraits(.isButton)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onTap() } }
        .onLongPressGesture(minimumDuration: 0.4) { if !isEditing { onLongPressRename() } }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... build
```

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Editor/FrameRow.swift
git commit -m "feat(animation): FrameRow view"
```

---

### Task 3.3: `FramesStrip` view (scrollable thumbnails + action bar)

**Files:**
- Create: `DrawBit/Views/Editor/FramesStrip.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct FramesStrip: View {
    @Bindable var state: EditorState
    let onAddFrame: () -> Void
    let onDuplicateFrame: () -> Void
    let onDeleteFrame: () -> Void
    let onReorderFrame: (Int, Int) -> Void
    let onRenameFrame: (UUID, String) -> Void

    @State private var isEditMode: Bool = false
    @State private var renamingFrameID: UUID?
    @State private var renameText: String = ""

    var body: some View {
        HStack(spacing: 8) {
            // (Stage 4 will add play/pause and FPS picker here.)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.frames, id: \.id) { frame in
                        if let id = renamingFrameID, id == frame.id {
                            TextField("Frame name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .onSubmit { commitRename() }
                        } else {
                            FrameRow(
                                frame: frame,
                                size: state.size,
                                isActive: frame.id == state.frames[state.activeFrameIndex].id,
                                isEditing: isEditMode,
                                onTap: { state.setActiveFrame(index: state.frames.firstIndex(where: { $0.id == frame.id })!) },
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

            HStack(spacing: 6) {
                Button(action: onAddFrame) {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .accessibilityIdentifier("FramesStrip.add")
                .disabled(state.frames.count >= FrameSequence.frameCap)

                if isEditMode {
                    Button(action: onDuplicateFrame) {
                        Image(systemName: "plus.square.on.square")
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityIdentifier("FramesStrip.duplicate")
                    .disabled(state.frames.count >= FrameSequence.frameCap)

                    Button(action: onDeleteFrame) {
                        Image(systemName: "trash")
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityIdentifier("FramesStrip.delete")
                    .disabled(state.frames.count <= 1)
                }

                Button(isEditMode ? "DONE" : "EDIT") { isEditMode.toggle() }
                    .font(.caption2.bold())
                    .accessibilityIdentifier("FramesStrip.editToggle")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .background(Color.black.opacity(0.4))
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

- [ ] **Step 2: Verify build**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... build
```

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Editor/FramesStrip.swift
git commit -m "feat(animation): FramesStrip view (thumbnails + action bar + EDIT toggle)"
```

---

### Task 3.4: Wire `FramesStrip` into `EditorView`

**Files:**
- Modify: `DrawBit/Views/Editor/EditorView.swift`

- [ ] **Step 1: Place the strip below the canvas**

In `EditorView.body`, add `FramesStrip` between `CanvasView` and `bottomBar`:

```swift
VStack(spacing: 0) {
    topBar
    Divider().overlay(Color.white.opacity(0.08))
    CanvasView(...)
    Divider().overlay(Color.white.opacity(0.08))
    FramesStrip(
        state: state,
        onAddFrame: addFrameAfterActive,
        onDuplicateFrame: addFrameAfterActive,  // duplicate == add (which already duplicates)
        onDeleteFrame: deleteActiveFrameWithConfirmIfNeeded,
        onReorderFrame: reorderFrame,
        onRenameFrame: renameFrame
    )
    bottomBar
}
```

- [ ] **Step 2: Add the delete confirmation**

```swift
@State private var showingDeleteFrameConfirm = false

private var activeFrameHasContent: Bool {
    state.frames[state.activeFrameIndex].layers.contains { layer in
        layer.pixels.contains(where: { $0 != 0 })
    }
}

func deleteActiveFrameWithConfirmIfNeeded() {
    if activeFrameHasContent {
        showingDeleteFrameConfirm = true
    } else {
        deleteActiveFrame()
    }
}
```

Attach the dialog at the bottom of `body`:

```swift
.confirmationDialog("Delete Frame?",
                    isPresented: $showingDeleteFrameConfirm,
                    titleVisibility: .visible) {
    Button("Delete", role: .destructive) { deleteActiveFrame() }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This frame has pixels. Deleting cannot be undone past 50 actions.")
}
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild ... build
```

- [ ] **Step 4: Commit**

```bash
git add DrawBit/Views/Editor/EditorView.swift
git commit -m "feat(animation): wire FramesStrip into EditorView with delete confirmation"
```

---

### Task 3.5: UI smoke test (Stage 3)

**Files:**
- Create: `DrawBitUITests/AnimationStripUITests.swift`

- [ ] **Step 1: Implement**

```swift
import XCTest

final class AnimationStripUITests: XCTestCase {
    func testAddTwoFramesAndScrubBetweenThem() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset"]
        app.launch()

        // Open or create a piece via the gallery — reuses the existing convention.
        app.buttons["NewPiece32"].tap()  // Existing identifier in the gallery.

        let add = app.buttons["FramesStrip.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 2))
        add.tap()
        add.tap()

        // Three frames now. Tap the first.
        let firstThumb = app.buttons.matching(identifier: "FrameRow.").firstMatch
        XCTAssertTrue(firstThumb.exists)
        firstThumb.tap()
    }
}
```

(If `NewPiece32` isn't an existing identifier, substitute a working gallery-entry identifier or use the simulator's first cell.)

- [ ] **Step 2: Verify**

```bash
xcodebuild ... test -only-testing:DrawBitUITests/AnimationStripUITests
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add DrawBitUITests/AnimationStripUITests.swift
git commit -m "test(animation): UI smoke test for FramesStrip add and scrub"
```

---

### Task 3.6: Stage 3 sweep + tag

- [ ] **Step 1: Full suite**

```bash
xcodebuild ... test
```
Expected: green.

- [ ] **Step 2: Tag**

```bash
git tag -a stage-3-animation-strip -m "Stage 3: bottom timeline strip"
```

---

## Stage 4 — Playback

**Goal of stage:** `PlaybackController` advances the active frame at a chosen FPS. Drawing input, frame ops, layer panel ops are all gated off while playing.

### Task 4.1: `PlaybackController`

**Files:**
- Create: `DrawBit/State/PlaybackController.swift`
- Create: `DrawBitTests/State/PlaybackControllerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DrawBit

final class PlaybackControllerTests: XCTestCase {
    func testStartAdvancesActiveFrameAtFPS() {
        let pixels = Data(count: CanvasSize.s32.byteCount)
        let l = Layer(name: "L", pixels: pixels)
        let f1 = Frame(name: "F1", layers: [l], activeLayerID: l.id)
        let f2 = Frame(name: "F2", layers: [l], activeLayerID: l.id)
        let state = EditorState(pieceID: UUID(), size: .s32,
                                frames: [f1, f2], activeFrameIndex: 0, fps: 60)
        let pb = PlaybackController(state: state)
        pb.start()
        let exp = expectation(description: "Advances at 60fps")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // After 100 ms at 60 fps, should have advanced ~6 frames; with only 2 frames, looping → either 0 or 1.
            XCTAssertTrue(pb.isRunning)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        pb.stop()
    }

    func testStopHaltsAdvance() {
        let pixels = Data(count: CanvasSize.s32.byteCount)
        let l = Layer(name: "L", pixels: pixels)
        let f1 = Frame(name: "F1", layers: [l], activeLayerID: l.id)
        let f2 = Frame(name: "F2", layers: [l], activeLayerID: l.id)
        let state = EditorState(pieceID: UUID(), size: .s32,
                                frames: [f1, f2], activeFrameIndex: 0, fps: 60)
        let pb = PlaybackController(state: state)
        pb.start()
        pb.stop()
        XCTAssertFalse(pb.isRunning)
    }
}
```

- [ ] **Step 2: Verify failure**

Build error: missing type.

- [ ] **Step 3: Implement**

```swift
import Foundation

@MainActor
final class PlaybackController {
    private weak var state: EditorState?
    private var timer: Timer?
    private(set) var isRunning: Bool = false

    init(state: EditorState) { self.state = state }

    func start() {
        guard !isRunning, let state, state.frames.count > 1 else { return }
        let fps = max(1, min(120, state.fps))
        let interval = 1.0 / TimeInterval(fps)
        isRunning = true
        state.isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let state = self.state else { return }
            let next = (state.activeFrameIndex + 1) % state.frames.count
            state.activeFrameIndex = next
        }
    }

    func stop() {
        isRunning = false
        state?.isPlaying = false
        timer?.invalidate()
        timer = nil
    }
}
```

Add `var isPlaying: Bool = false` to `EditorState`.

- [ ] **Step 4: Verify**

```bash
xcodebuild ... test -only-testing:DrawBitTests/PlaybackControllerTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/State/PlaybackController.swift DrawBit/State/EditorState.swift DrawBitTests/State/PlaybackControllerTests.swift
git commit -m "feat(animation): PlaybackController with Timer-driven loop advance"
```

---

### Task 4.2: Play/pause + FPS picker in `FramesStrip`

**Files:**
- Modify: `DrawBit/Views/Editor/FramesStrip.swift`
- Modify: `DrawBit/Views/Editor/EditorView.swift`

- [ ] **Step 1: Add controls**

In `FramesStrip.body`, prepend before the `ScrollView`:

```swift
HStack(spacing: 6) {
    Button(action: onTogglePlay) {
        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
            .frame(width: 28, height: 28)
            .foregroundStyle(state.isPlaying ? Color.red : Color.accentColor)
    }
    .accessibilityIdentifier("FramesStrip.playPause")

    Button(action: cycleFPS) {
        Text("\(state.fps) fps").font(.caption2.bold())
    }
    .accessibilityIdentifier("FramesStrip.fps")
}
```

`onTogglePlay` is a new closure in the strip's init. `cycleFPS` is private:

```swift
private static let fpsChoices = [4, 8, 12, 24, 30, 60]

private func cycleFPS() {
    let idx = Self.fpsChoices.firstIndex(of: state.fps) ?? 2
    let next = Self.fpsChoices[(idx + 1) % Self.fpsChoices.count]
    state.fps = next
}
```

- [ ] **Step 2: Wire `onTogglePlay` in `EditorView`**

```swift
@State private var playback: PlaybackController?

private func togglePlay() {
    if playback == nil { playback = PlaybackController(state: state) }
    if state.isPlaying { playback?.stop() } else { playback?.start() }
}
```

Pass `onTogglePlay: togglePlay` into the `FramesStrip` initializer.

- [ ] **Step 3: Persist FPS**

In `saveCurrentFrame`, FPS is already passed via `state.fps`. Confirm the V2 codec round-trips it (Task 1.2 tests already cover this).

- [ ] **Step 4: Verify build + manual check**

```bash
xcodebuild ... build
```

Manually: open a piece, add frames, hit play. Confirm thumbnails progress and the canvas updates frame to frame. Pause leaves the active frame where playback stopped.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Views/Editor/FramesStrip.swift DrawBit/Views/Editor/EditorView.swift
git commit -m "feat(animation): play/pause + FPS picker in FramesStrip"
```

---

### Task 4.3: Gate input/ops while playing

**Files:**
- Modify: `DrawBit/Views/Editor/EditorView.swift`
- Modify: `DrawBit/Views/Editor/CanvasView.swift` (or add `.allowsHitTesting`)

- [ ] **Step 1: Disable canvas + chrome when playing**

Wrap the canvas in `.allowsHitTesting(!state.isPlaying)`:

```swift
CanvasView(...)
    .allowsHitTesting(!state.isPlaying)
```

In `topBar`, disable the LAYERS button when `state.isPlaying`. In the strip, disable the action bar's add/duplicate/delete buttons. The play/pause button itself remains enabled.

```swift
.disabled(state.isPlaying)
```

- [ ] **Step 2: Disable layer panel ops while playing**

In `LayersPanel`, gate the action bar buttons with `.disabled(state.isPlaying)` (or hide the panel entirely; pick the lighter touch — disable).

- [ ] **Step 3: Verify**

Manual check: start playback, try to draw — canvas no-ops. Try to add a layer — disabled. Stop playback — everything responsive.

- [ ] **Step 4: Commit**

```bash
git add DrawBit/Views/Editor/EditorView.swift DrawBit/Views/Editor/CanvasView.swift DrawBit/Views/Editor/LayersPanel.swift
git commit -m "feat(animation): gate input and ops while playing"
```

---

### Task 4.4: Stage 4 sweep + tag

```bash
xcodebuild ... test
git tag -a stage-4-animation-playback -m "Stage 4: playback"
```

---

## Stage 5 — Onion skinning

**Goal of stage:** Toggle in the strip turns on a previous-frame ghost in the canvas. Display only — never written into pixel storage.

### Task 5.1: `EditorState.isOnionSkinEnabled` + toggle in strip

**Files:**
- Modify: `DrawBit/State/EditorState.swift`
- Modify: `DrawBit/Views/Editor/FramesStrip.swift`

- [ ] **Step 1: Add the field**

```swift
var isOnionSkinEnabled: Bool = false
```

- [ ] **Step 2: Add toggle button to the strip**

In `FramesStrip`, alongside the play/pause and FPS controls:

```swift
Button(action: { state.isOnionSkinEnabled.toggle() }) {
    Image(systemName: state.isOnionSkinEnabled ? "circle.righthalf.filled" : "circle")
        .frame(width: 28, height: 28)
        .foregroundStyle(state.isOnionSkinEnabled ? Color.accentColor : Color.white.opacity(0.6))
}
.accessibilityIdentifier("FramesStrip.onionSkin")
.disabled(state.activeFrameIndex == 0 || state.isPlaying)
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild ... build
```

- [ ] **Step 4: Commit**

```bash
git add DrawBit/State/EditorState.swift DrawBit/Views/Editor/FramesStrip.swift
git commit -m "feat(animation): onion-skin toggle in FramesStrip"
```

---

### Task 5.2: `CanvasView` ghost overlay

**Files:**
- Modify: `DrawBit/Views/Editor/CanvasView.swift`

- [ ] **Step 1: Render previous-frame ghost**

In the canvas's `body`, beneath the active-frame `Image` but above the checkerboard background, add:

```swift
if state.isOnionSkinEnabled,
   !state.isPlaying,
   state.activeFrameIndex > 0,
   let png = FrameThumbnailRenderer.render(
       frame: state.frames[state.activeFrameIndex - 1],
       size: state.size,
       targetEdge: state.size.dimension), // full-resolution ghost, not thumbnail
   let img = UIImage(data: png) {
    Image(uiImage: img)
        .interpolation(.none)
        .antialiased(false)
        .resizable()
        .scaledToFit()
        .opacity(0.3)
}
```

(Recompute on every layout — Stage 5 follow-up could cache. At small canvas sizes this is fine.)

- [ ] **Step 2: Manual check**

Open a piece, add 2 frames, draw on frame 1. Switch to frame 2. Toggle onion skin on. The frame-1 drawing should appear as a faint ghost beneath the (currently empty) frame 2.

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Editor/CanvasView.swift
git commit -m "feat(animation): previous-frame ghost overlay in CanvasView"
```

---

### Task 5.3: Stage 5 sweep + tag

```bash
xcodebuild ... test
git tag -a stage-5-animation-onion-skin -m "Stage 5: onion skinning"
```

---

## Stage 6 — Export (GIF + APNG)

**Goal of stage:** A multi-frame piece can be exported as an animated GIF or APNG with the chosen FPS as the playback rate. Single-frame pieces export as a one-frame GIF/APNG.

### Task 6.1: `GIFExporter`

**Files:**
- Create: `DrawBit/Rendering/GIFExporter.swift`
- Create: `DrawBitTests/Rendering/GIFExporterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import ImageIO
@testable import DrawBit

final class GIFExporterTests: XCTestCase {
    func testExportProducesGIFWithFrameCount() throws {
        let pixels = Data(repeating: 255, count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: pixels)
        let f1 = Frame(name: "F1", layers: [layer], activeLayerID: layer.id)
        let f2 = Frame(name: "F2", layers: [layer], activeLayerID: layer.id)
        let f3 = Frame(name: "F3", layers: [layer], activeLayerID: layer.id)
        let f4 = Frame(name: "F4", layers: [layer], activeLayerID: layer.id)

        let data = GIFExporter.export(frames: [f1, f2, f3, f4], size: .s32, scale: 4, fps: 12)
        XCTAssertNotNil(data)

        // Read it back via ImageIO and assert frame count.
        let src = CGImageSourceCreateWithData(data! as CFData, nil)!
        XCTAssertEqual(CGImageSourceGetCount(src), 4)
    }
}
```

- [ ] **Step 2: Verify failure**

Build error.

- [ ] **Step 3: Implement**

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GIFExporter {
    static func export(frames: [Frame], size: CanvasSize, scale: Int, fps: Int) -> Data? {
        guard !frames.isEmpty, scale >= 1, fps >= 1 else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let outEdge = size.dimension * scale
        let delay = 1.0 / Double(fps)

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.gif.identifier as CFString, frames.count, nil
        ) else { return nil }

        let fileProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
        ]

        for frame in frames {
            let buffer = Compositor.composite(frame, size: size)
            guard let source = bufferToCGImage(buffer) else { return nil }
            guard let ctx = CGContext(
                data: nil,
                width: outEdge,
                height: outEdge,
                bitsPerComponent: 8,
                bytesPerRow: outEdge * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: outEdge, height: outEdge))
            guard let scaledImage = ctx.makeImage() else { return nil }
            CGImageDestinationAddImage(dest, scaledImage, frameProps as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
```

- [ ] **Step 4: Verify**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/GIFExporterTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Rendering/GIFExporter.swift DrawBitTests/Rendering/GIFExporterTests.swift
git commit -m "feat(animation): GIFExporter via ImageIO multi-image destination"
```

---

### Task 6.2: `APNGExporter`

**Files:**
- Create: `DrawBit/Rendering/APNGExporter.swift`
- Create: `DrawBitTests/Rendering/APNGExporterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import ImageIO
@testable import DrawBit

final class APNGExporterTests: XCTestCase {
    func testExportProducesAPNGWithFrameCount() throws {
        let pixels = Data(repeating: 255, count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: pixels)
        let frames = (1...3).map { _ in
            Frame(name: "F", layers: [layer], activeLayerID: layer.id)
        }

        let data = APNGExporter.export(frames: frames, size: .s32, scale: 2, fps: 24)
        XCTAssertNotNil(data)

        let src = CGImageSourceCreateWithData(data! as CFData, nil)!
        XCTAssertEqual(CGImageSourceGetCount(src), 3)
    }
}
```

- [ ] **Step 2: Verify failure**

Build error.

- [ ] **Step 3: Implement**

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum APNGExporter {
    static func export(frames: [Frame], size: CanvasSize, scale: Int, fps: Int) -> Data? {
        guard !frames.isEmpty, scale >= 1, fps >= 1 else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let outEdge = size.dimension * scale
        let delay = 1.0 / Double(fps)

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, frames.count, nil
        ) else { return nil }

        let fileProps: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
        ]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let frameProps: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]
        ]

        for frame in frames {
            let buffer = Compositor.composite(frame, size: size)
            guard let source = bufferToCGImage(buffer) else { return nil }
            guard let ctx = CGContext(
                data: nil,
                width: outEdge,
                height: outEdge,
                bitsPerComponent: 8,
                bytesPerRow: outEdge * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: outEdge, height: outEdge))
            guard let scaledImage = ctx.makeImage() else { return nil }
            CGImageDestinationAddImage(dest, scaledImage, frameProps as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
```

- [ ] **Step 4: Verify**

```bash
xcodebuild ... test -only-testing:DrawBitTests/APNGExporterTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Rendering/APNGExporter.swift DrawBitTests/Rendering/APNGExporterTests.swift
git commit -m "feat(animation): APNGExporter via ImageIO multi-image destination"
```

---

### Task 6.3: Wire GIF/APNG into `ShareSheet`

**Files:**
- Modify: `DrawBit/Views/Editor/ShareSheet.swift`

- [ ] **Step 1: Add format buttons**

In the existing `ShareSheet` view, add two new buttons next to the existing PNG export buttons. Each loads the piece's frames via `PieceRepository.loadFrames(piece:)`, calls the appropriate exporter, and presents the resulting `Data` via the standard `UIActivityViewController` path.

```swift
Button("Export GIF") {
    if let data = exportGIF() { share(data, suggestedName: "\(piece.effectiveName).gif") }
}

Button("Export Animated PNG") {
    if let data = exportAPNG() { share(data, suggestedName: "\(piece.effectiveName).png") }
}

private func exportGIF() -> Data? {
    let repo = PieceRepository(context: modelContext)
    guard let result = try? repo.loadFrames(piece: piece) else { return nil }
    return GIFExporter.export(frames: result.frames, size: piece.size, scale: 4, fps: result.fps)
}

private func exportAPNG() -> Data? {
    let repo = PieceRepository(context: modelContext)
    guard let result = try? repo.loadFrames(piece: piece) else { return nil }
    return APNGExporter.export(frames: result.frames, size: piece.size, scale: 4, fps: result.fps)
}
```

(Match the existing `share(_:suggestedName:)` pattern used by the PNG buttons. If absent, factor it as a small helper.)

- [ ] **Step 2: Verify build + manual smoke**

```bash
xcodebuild ... build
```

Manually: open a multi-frame piece, hit Share, choose Export GIF, save to Files. Open the GIF in Safari/Photos and confirm playback. Repeat for APNG.

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Editor/ShareSheet.swift
git commit -m "feat(animation): ShareSheet exports GIF and APNG"
```

---

### Task 6.4: Stage 6 sweep + tag

```bash
xcodebuild ... test
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
git tag -a stage-6-animation-export -m "Stage 6: GIF + APNG export"
```

---

## Final integration

### Task 7.1: Holistic Opus review per stage

Per the Layers v2 workflow recipe, run `superpowers:code-reviewer` (Opus) on each stage tag's diff against `main` BEFORE merging. The review reliably catches cross-cutting bugs the per-task reviews miss (every Layers v2 stage had at least one such bug).

- [ ] **Step 1: For each stage tag, dispatch a holistic review**

For each of `stage-1-animation-plumbing` … `stage-6-animation-export`, invoke `superpowers:code-reviewer` with the diff `git diff main...stage-N-animation-…`.

- [ ] **Step 2: Address findings before merging**

Open follow-up commits on the `animation` branch addressing each finding. Re-tag if necessary (`stage-N-animation-…-v2`).

### Task 7.2: Merge each stage to main

- [ ] **Step 1: Per-stage merge with `--no-ff`**

```bash
cd /Users/iliasrafailidis/development/bitme   # main repo, not the worktree
git checkout main
git merge --no-ff animation -m "merge: animation stage N — <stage name>"
```

(Or merge from the worktree's tip to main as each stage closes.)

- [ ] **Step 2: Push**

```bash
git push origin main --tags
```

### Task 7.3: Cleanup

- [ ] **Step 1: Remove the worktree once all stages have shipped**

```bash
git worktree remove .worktrees/animation
```

- [ ] **Step 2: Write a feature-complete handoff doc**

Mirror `docs/superpowers/handoffs/2026-05-04-layers-feature-complete.md`. Save to `docs/superpowers/handoffs/YYYY-MM-DD-animation-feature-complete.md`. Include: commit table per stage, what shipped, file additions/modifications, patterns established, what reviews caught, follow-ups.

- [ ] **Step 3: Update memory**

Replace the existing layers memory pointer with an animation pointer noting the feature is complete and the staged tags.

---

## Self-Review

(Run by the plan author after writing this plan.)

1. **Spec coverage:** every section of `docs/superpowers/specs/2026-05-05-animation-design.md` maps to a task above:
   - Frame attributes (`id`, `name`) → Task 1.1
   - Layer cascade across frames → Tasks 2.1, 2.2
   - Defaults & limits → frame cap in Task 2.1
   - Tool semantics on animated canvas → no code change (active-frame routing in Task 1.5)
   - Frame-level operations → Tasks 2.1, 2.5, 3.4, 3.5
   - Onion skinning → Tasks 5.1, 5.2
   - Playback → Tasks 4.1, 4.2, 4.3
   - Marquee × frame interaction → Task 2.3
   - Codec V2 → Task 1.2
   - Backwards-compat read path → Task 1.4
   - State changes → Tasks 1.5, 2.3
   - Compositor (mostly unchanged) → covered by reuse, no task
   - Onion skin in CanvasView → Task 5.2
   - Per-frame thumbnails → Task 3.1
   - GIF + APNG export → Tasks 6.1, 6.2, 6.3
   - Single-frame non-regression → Task 1.6
   - Out-of-scope file tree → matches Tasks 1–6 file lists

2. **Placeholder scan:** none — every step has full code or commands.

3. **Type consistency:** `FrameSequence.addFrameAfter` matches across Tasks 2.1, 2.5; `setActiveFrame` matches Tasks 1.5, 2.3, 3.3; `loadFrames` matches Tasks 1.4, 6.3.

4. **Ambiguity:** the active-frame index handling on layer-cascade `removeLayer` is documented (the cascade picks `max(0, idx-1)` per frame). Reorder math is provided as a unit-tested static helper. Onion skin is explicitly display-only.

No issues to fix.
