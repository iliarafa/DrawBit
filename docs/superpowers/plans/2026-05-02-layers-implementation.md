# Layers (v2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multi-layer support to DrawBit pieces in 4 staged merges, where each stage leaves the app fully functional and ships independently.

**Architecture:** Layers stored as a value-type `Frame` (`[Layer]` + `activeLayerID`), persisted as a versioned binary blob in `Piece.frameData` via a pure-logic `FrameCodec`. Display, thumbnail, and PNG export all flow through a new `Compositor` that produces a flat `CompositedBuffer` of premultiplied RGBA bytes. Because every layer is forced to 100% opacity, composited alpha stays {0, 255} and the existing rendering pipeline (sRGB, `.premultipliedLast`, no antialias, no interpolation) requires no semantic change. SwiftData remains accessed only via `PieceRepository`.

**Tech Stack:** Swift 5.10+, SwiftUI, `@Observable` state, SwiftData (single field rename + `@Attribute(.externalStorage)`), CoreGraphics for raster I/O, XCTest (unit + UI tests), XcodeGen for project regeneration.

**Branch:** `layers` (created off `main`). Each stage merges to `main` only after its tests pass and a manual on-device check is logged.

---

## Pre-flight

### Task 0.1: Create the `layers` branch

**Files:**
- Modify: git refs (working tree only — no source change)

- [ ] **Step 1: Verify clean working tree**

Run: `git status`
Expected: nothing committed should be ahead/dirty unrelated to this work; the unrelated `?? DrawBit/PrivacyInfo.xcprivacy` and `?? docs/superpowers/plans/2026-04-27-iphone-support.md` may exist — leave them.

- [ ] **Step 2: Create the branch from `main`**

Run:
```bash
git checkout main
git pull --ff-only
git checkout -b layers
```
Expected: `Switched to a new branch 'layers'`.

- [ ] **Step 3: Confirm branch**

Run: `git branch --show-current`
Expected: `layers`.

---

## Stage 1 — Plumbing only, zero new behavior

**Goal of stage:** Every existing test and user-visible behavior is identical. Internally, every piece is now a `Frame` with exactly one `Layer`. The non-regression PNG byte-identity test gates the merge.

### Task 1.1: `Layer` value type with passing tests

**Files:**
- Create: `DrawBit/Drawing/Layer.swift`
- Create: `DrawBitTests/Drawing/LayerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `DrawBitTests/Drawing/LayerTests.swift`:

```swift
import XCTest
@testable import DrawBit

final class LayerTests: XCTestCase {
    func testLayerIsEquatableOnAllFields() {
        let id = UUID()
        let pixels = Data(repeating: 0, count: CanvasSize.s32.byteCount)
        let a = Layer(id: id, name: "Layer 1", pixels: pixels, isVisible: true, isLocked: false)
        let b = Layer(id: id, name: "Layer 1", pixels: pixels, isVisible: true, isLocked: false)
        XCTAssertEqual(a, b)
    }

    func testLayerNotEqualWhenAnyFieldDiffers() {
        let id = UUID()
        let pixels = Data(repeating: 0, count: CanvasSize.s32.byteCount)
        let a = Layer(id: id, name: "Layer 1", pixels: pixels, isVisible: true, isLocked: false)
        XCTAssertNotEqual(a, Layer(id: UUID(), name: "Layer 1", pixels: pixels, isVisible: true, isLocked: false))
        XCTAssertNotEqual(a, Layer(id: id, name: "Other",   pixels: pixels, isVisible: true, isLocked: false))
        XCTAssertNotEqual(a, Layer(id: id, name: "Layer 1", pixels: Data(repeating: 1, count: pixels.count), isVisible: true, isLocked: false))
        XCTAssertNotEqual(a, Layer(id: id, name: "Layer 1", pixels: pixels, isVisible: false, isLocked: false))
        XCTAssertNotEqual(a, Layer(id: id, name: "Layer 1", pixels: pixels, isVisible: true, isLocked: true))
    }
}
```

- [ ] **Step 2: Verify the test fails**

Regenerate the project so XcodeGen picks up the new test file:
```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
```

Run:
```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/LayerTests
```
Expected: build failure ("cannot find 'Layer' in scope"). That's the failing-test step.

- [ ] **Step 3: Write the minimal implementation**

Create `DrawBit/Drawing/Layer.swift`:

```swift
import Foundation

struct Layer: Equatable {
    let id: UUID
    var name: String
    var pixels: Data
    var isVisible: Bool
    var isLocked: Bool

    init(id: UUID = UUID(), name: String, pixels: Data, isVisible: Bool = true, isLocked: Bool = false) {
        self.id = id
        self.name = name
        self.pixels = pixels
        self.isVisible = isVisible
        self.isLocked = isLocked
    }
}
```

- [ ] **Step 4: Regenerate, run test, verify pass**

Run:
```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/LayerTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/Layer.swift DrawBitTests/Drawing/LayerTests.swift
git commit -m "feat(layers): add Layer value type"
```

---

### Task 1.2: `Frame` value type with mutator API

**Files:**
- Create: `DrawBit/Drawing/Frame.swift`
- Create: `DrawBitTests/Drawing/FrameTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `DrawBitTests/Drawing/FrameTests.swift`:

```swift
import XCTest
@testable import DrawBit

final class FrameTests: XCTestCase {
    private func emptyLayer(name: String = "Layer 1") -> Layer {
        Layer(name: name, pixels: Data(count: CanvasSize.s32.byteCount))
    }

    func testInitWithSingleLayerSetsActiveCorrectly() {
        let layer = emptyLayer()
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.activeLayerID, layer.id)
    }

    func testActiveIndexLocatesActiveLayer() {
        let bottom = emptyLayer(name: "Bottom")
        let top    = emptyLayer(name: "Top")
        let frame  = Frame(layers: [bottom, top], activeLayerID: top.id)
        XCTAssertEqual(frame.activeIndex, 1)
    }

    func testAddLayerAboveInsertsAndSetsActive() {
        let bottom = emptyLayer(name: "Bottom")
        var frame  = Frame(layers: [bottom], activeLayerID: bottom.id)
        let added  = frame.addLayer(name: "Layer 2")
        XCTAssertEqual(frame.layers.count, 2)
        XCTAssertEqual(frame.layers[1].id, added.id)
        XCTAssertEqual(frame.activeLayerID, added.id)
    }

    func testRemoveLayerSelectsLayerBelow() {
        let l1 = emptyLayer(name: "L1")
        let l2 = emptyLayer(name: "L2")
        var frame = Frame(layers: [l1, l2], activeLayerID: l2.id)
        frame.removeLayer(id: l2.id)
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.activeLayerID, l1.id)
    }

    func testRemoveBottomLayerSelectsLayerAbove() {
        let l1 = emptyLayer(name: "L1")
        let l2 = emptyLayer(name: "L2")
        var frame = Frame(layers: [l1, l2], activeLayerID: l1.id)
        frame.removeLayer(id: l1.id)
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.activeLayerID, l2.id)
    }

    func testRemoveLastLayerIsNoOp() {
        let l1 = emptyLayer()
        var frame = Frame(layers: [l1], activeLayerID: l1.id)
        frame.removeLayer(id: l1.id)
        XCTAssertEqual(frame.layers.count, 1, "minimum 1 layer must be preserved")
        XCTAssertEqual(frame.activeLayerID, l1.id)
    }

    func testMoveLayerReorders() {
        let l1 = emptyLayer(name: "L1")
        let l2 = emptyLayer(name: "L2")
        let l3 = emptyLayer(name: "L3")
        var frame = Frame(layers: [l1, l2, l3], activeLayerID: l1.id)
        frame.move(id: l1.id, toIndex: 2)
        XCTAssertEqual(frame.layers.map(\.name), ["L2", "L3", "L1"])
        XCTAssertEqual(frame.activeLayerID, l1.id, "active stays on the moved layer")
    }

    func testSetActiveValidatesMembership() {
        let l1 = emptyLayer()
        var frame = Frame(layers: [l1], activeLayerID: l1.id)
        frame.setActive(id: UUID()) // unknown id
        XCTAssertEqual(frame.activeLayerID, l1.id, "unknown ids are ignored, not stored")
    }

    func testWithActiveLayerPixelsMutatesOnlyActiveLayer() {
        let l1 = emptyLayer(name: "L1")
        let l2 = emptyLayer(name: "L2")
        var frame = Frame(layers: [l1, l2], activeLayerID: l2.id)

        frame.withActiveLayerPixels { pixels in
            pixels[0] = 0xFF
        }

        XCTAssertEqual(frame.layers[0].pixels[0], 0x00, "L1 untouched")
        XCTAssertEqual(frame.layers[1].pixels[0], 0xFF, "L2 mutated")
    }
}
```

- [ ] **Step 2: Verify the test fails**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/FrameTests
```
Expected: build failure ("cannot find 'Frame' in scope").

- [ ] **Step 3: Write the implementation**

Create `DrawBit/Drawing/Frame.swift`:

```swift
import Foundation

struct Frame: Equatable {
    private(set) var layers: [Layer]
    private(set) var activeLayerID: UUID

    init(layers: [Layer], activeLayerID: UUID) {
        precondition(!layers.isEmpty, "Frame must have at least one layer")
        precondition(layers.contains(where: { $0.id == activeLayerID }),
                     "activeLayerID must reference one of the layers")
        self.layers = layers
        self.activeLayerID = activeLayerID
    }

    var activeIndex: Int {
        // Safe: invariant guarantees activeLayerID is in layers.
        layers.firstIndex(where: { $0.id == activeLayerID })!
    }

    var activeLayer: Layer {
        layers[activeIndex]
    }

    /// Adds a new empty layer above the active layer and makes it active. Returns the new layer.
    /// Caller is responsible for enforcing any cap; this method always inserts.
    @discardableResult
    mutating func addLayer(name: String) -> Layer {
        let pixelByteCount = layers[0].pixels.count
        let new = Layer(name: name, pixels: Data(count: pixelByteCount))
        let insertAt = activeIndex + 1
        layers.insert(new, at: insertAt)
        activeLayerID = new.id
        return new
    }

    /// Duplicates the active layer, places the duplicate above the original, and makes it active.
    @discardableResult
    mutating func duplicateActiveLayer(nameSuffix: String = " copy") -> Layer {
        let original = layers[activeIndex]
        let copy = Layer(
            name: original.name + nameSuffix,
            pixels: original.pixels,
            isVisible: original.isVisible,
            isLocked: original.isLocked
        )
        layers.insert(copy, at: activeIndex + 1)
        activeLayerID = copy.id
        return copy
    }

    /// Removes the layer with the given id. No-ops if removing the last layer.
    mutating func removeLayer(id: UUID) {
        guard layers.count > 1 else { return }
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = id == activeLayerID
        layers.remove(at: idx)
        if wasActive {
            // Prefer the layer below (idx - 1); otherwise the new layer at the same index.
            let newActiveIdx = max(0, idx - 1)
            activeLayerID = layers[newActiveIdx].id
        }
    }

    /// Moves the layer with the given id to `toIndex` (clamped to bounds). Active stays on the moved layer.
    mutating func move(id: UUID, toIndex: Int) {
        guard let from = layers.firstIndex(where: { $0.id == id }) else { return }
        let to = max(0, min(layers.count - 1, toIndex))
        if from == to { return }
        let layer = layers.remove(at: from)
        layers.insert(layer, at: to)
    }

    mutating func setActive(id: UUID) {
        guard layers.contains(where: { $0.id == id }) else { return }
        activeLayerID = id
    }

    mutating func setName(id: UUID, to name: String) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].name = name
    }

    mutating func setVisible(id: UUID, to visible: Bool) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].isVisible = visible
    }

    mutating func setLocked(id: UUID, to locked: Bool) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].isLocked = locked
    }

    /// Mutates the active layer's pixel data in place.
    mutating func withActiveLayerPixels(_ body: (inout Data) -> Void) {
        body(&layers[activeIndex].pixels)
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/FrameTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/Frame.swift DrawBitTests/Drawing/FrameTests.swift
git commit -m "feat(layers): add Frame value type with mutator API"
```

---

### Task 1.3: `FrameCodec` encode + decode round-trip

**Files:**
- Create: `DrawBit/Drawing/FrameCodec.swift`
- Create: `DrawBitTests/Drawing/FrameCodecTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `DrawBitTests/Drawing/FrameCodecTests.swift`:

```swift
import XCTest
@testable import DrawBit

final class FrameCodecTests: XCTestCase {
    private func sampleFrame() -> Frame {
        let bytes = Data((0..<CanvasSize.s32.byteCount).map { UInt8($0 & 0xFF) })
        let l1 = Layer(name: "Background", pixels: bytes, isVisible: true,  isLocked: false)
        let l2 = Layer(name: "Sketch",     pixels: bytes, isVisible: false, isLocked: true)
        return Frame(layers: [l1, l2], activeLayerID: l2.id)
    }

    func testRoundTripPreservesAllFields() throws {
        let original = sampleFrame()
        let data = FrameCodec.encode(original)
        let decoded = try FrameCodec.decode(data)
        XCTAssertEqual(decoded, original)
    }

    func testEncodedDataStartsWithMagic() {
        let data = FrameCodec.encode(sampleFrame())
        let magic = Array(data.prefix(4))
        XCTAssertEqual(magic, Array("DBFR".utf8))
    }

    func testHasV1MagicPrefixReturnsFalseForRawV1Bytes() {
        let v1Raw = Data(count: CanvasSize.s32.byteCount)
        XCTAssertFalse(FrameCodec.hasV1MagicPrefix(v1Raw))
    }

    func testHasV1MagicPrefixReturnsTrueForEncodedFrame() {
        let encoded = FrameCodec.encode(sampleFrame())
        XCTAssertTrue(FrameCodec.hasV1MagicPrefix(encoded))
    }

    func testWrapV1DataProducesSingleLayerFrame() {
        let pixelCount = CanvasSize.s32.byteCount
        let v1Raw = Data((0..<pixelCount).map { UInt8($0 & 0xFF) })
        let frame = FrameCodec.wrapV1Data(v1Raw, defaultName: "Layer 1")
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.layers[0].name, "Layer 1")
        XCTAssertEqual(frame.layers[0].pixels, v1Raw)
        XCTAssertEqual(frame.activeLayerID, frame.layers[0].id)
    }

    func testDecodeRejectsBadMagic() {
        var bad = FrameCodec.encode(sampleFrame())
        bad[0] = 0x00
        XCTAssertThrowsError(try FrameCodec.decode(bad))
    }

    func testDecodeRejectsTruncatedData() {
        let encoded = FrameCodec.encode(sampleFrame())
        let truncated = encoded.prefix(encoded.count - 1)
        XCTAssertThrowsError(try FrameCodec.decode(Data(truncated)))
    }
}
```

- [ ] **Step 2: Verify the test fails**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/FrameCodecTests
```
Expected: build failure ("cannot find 'FrameCodec' in scope").

- [ ] **Step 3: Write the implementation**

Create `DrawBit/Drawing/FrameCodec.swift`:

```swift
import Foundation

/// Versioned binary encoder/decoder for Frame.
///
/// Layout (big-endian where multibyte):
///   4  bytes   ASCII "DBFR" magic
///   1  byte    format version (currently 1)
///   2  bytes   layer count
///   16 bytes   active layer UUID
///   per layer:
///     16 bytes   layer UUID
///     1  byte    flags (bit 0 = visible, bit 1 = locked)
///     1  byte    name byte length (0..255)
///     N  bytes   name UTF-8
///     4  bytes   pixel byte count
///     N  bytes   raw RGBA pixel data
enum FrameCodec {
    static let magic: [UInt8] = Array("DBFR".utf8)
    static let currentVersion: UInt8 = 1

    enum DecodeError: Error {
        case badMagic
        case unsupportedVersion(UInt8)
        case truncated
        case malformed(String)
    }

    static func hasV1MagicPrefix(_ data: Data) -> Bool {
        guard data.count >= magic.count else { return false }
        return Array(data.prefix(magic.count)) == magic
    }

    static func wrapV1Data(_ pixels: Data, defaultName: String) -> Frame {
        let layer = Layer(name: defaultName, pixels: pixels)
        return Frame(layers: [layer], activeLayerID: layer.id)
    }

    static func encode(_ frame: Frame) -> Data {
        var out = Data()
        out.append(contentsOf: magic)
        out.append(currentVersion)

        let count = UInt16(frame.layers.count)
        out.append(UInt8((count >> 8) & 0xFF))
        out.append(UInt8(count & 0xFF))

        appendUUID(frame.activeLayerID, to: &out)

        for layer in frame.layers {
            appendUUID(layer.id, to: &out)
            var flags: UInt8 = 0
            if layer.isVisible { flags |= 0b0000_0001 }
            if layer.isLocked  { flags |= 0b0000_0010 }
            out.append(flags)

            let nameBytes = Array(layer.name.utf8.prefix(255))
            out.append(UInt8(nameBytes.count))
            out.append(contentsOf: nameBytes)

            let pixelLen = UInt32(layer.pixels.count)
            out.append(UInt8((pixelLen >> 24) & 0xFF))
            out.append(UInt8((pixelLen >> 16) & 0xFF))
            out.append(UInt8((pixelLen >>  8) & 0xFF))
            out.append(UInt8( pixelLen        & 0xFF))
            out.append(layer.pixels)
        }
        return out
    }

    static func decode(_ data: Data) throws -> Frame {
        var cursor = 0
        let bytes = [UInt8](data)

        func need(_ n: Int) throws {
            if cursor + n > bytes.count { throw DecodeError.truncated }
        }

        try need(magic.count)
        guard Array(bytes[cursor..<cursor+magic.count]) == magic else { throw DecodeError.badMagic }
        cursor += magic.count

        try need(1)
        let version = bytes[cursor]; cursor += 1
        guard version == currentVersion else { throw DecodeError.unsupportedVersion(version) }

        try need(2)
        let layerCount = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor+1])
        cursor += 2

        try need(16)
        let activeID = readUUID(bytes, at: cursor)
        cursor += 16

        var layers: [Layer] = []
        layers.reserveCapacity(Int(layerCount))

        for _ in 0..<Int(layerCount) {
            try need(16)
            let layerID = readUUID(bytes, at: cursor); cursor += 16

            try need(1)
            let flags = bytes[cursor]; cursor += 1
            let isVisible = (flags & 0b0000_0001) != 0
            let isLocked  = (flags & 0b0000_0010) != 0

            try need(1)
            let nameLen = Int(bytes[cursor]); cursor += 1
            try need(nameLen)
            let name = String(bytes: bytes[cursor..<cursor+nameLen], encoding: .utf8) ?? ""
            cursor += nameLen

            try need(4)
            let pixelLen =
                (UInt32(bytes[cursor    ]) << 24) |
                (UInt32(bytes[cursor + 1]) << 16) |
                (UInt32(bytes[cursor + 2]) <<  8) |
                 UInt32(bytes[cursor + 3])
            cursor += 4

            try need(Int(pixelLen))
            let pixels = Data(bytes[cursor..<cursor+Int(pixelLen)])
            cursor += Int(pixelLen)

            layers.append(Layer(id: layerID, name: name, pixels: pixels, isVisible: isVisible, isLocked: isLocked))
        }

        guard !layers.isEmpty else { throw DecodeError.malformed("zero layers") }
        guard layers.contains(where: { $0.id == activeID }) else {
            throw DecodeError.malformed("activeID does not match any layer")
        }
        return Frame(layers: layers, activeLayerID: activeID)
    }

    private static func appendUUID(_ id: UUID, to out: inout Data) {
        let t = id.uuid
        out.append(contentsOf: [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7,
                                t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15])
    }

    private static func readUUID(_ bytes: [UInt8], at offset: Int) -> UUID {
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

- [ ] **Step 4: Run, verify pass**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/FrameCodecTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/FrameCodec.swift DrawBitTests/Drawing/FrameCodecTests.swift
git commit -m "feat(layers): add FrameCodec versioned binary encode/decode"
```

---

### Task 1.4: `Compositor` with the topmost-non-transparent rule

**Files:**
- Create: `DrawBit/Rendering/Compositor.swift`
- Create: `DrawBitTests/Rendering/CompositorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `DrawBitTests/Rendering/CompositorTests.swift`:

```swift
import XCTest
@testable import DrawBit

final class CompositorTests: XCTestCase {
    private let size = CanvasSize.s32

    private func solidLayer(name: String, rgba: (UInt8, UInt8, UInt8, UInt8)) -> Layer {
        var data = Data(count: size.byteCount)
        for i in stride(from: 0, to: size.byteCount, by: 4) {
            data[i] = rgba.0; data[i+1] = rgba.1; data[i+2] = rgba.2; data[i+3] = rgba.3
        }
        return Layer(name: name, pixels: data)
    }

    func testSingleLayerCompositesToItsOwnBytes() {
        let l = solidLayer(name: "L", rgba: (255, 0, 0, 255))
        let frame = Frame(layers: [l], activeLayerID: l.id)
        let buf = Compositor.composite(frame, size: size)
        XCTAssertEqual(buf.data, l.pixels)
        XCTAssertEqual(buf.size, size)
    }

    func testTwoOpaqueLayersTopWins() {
        let bottom = solidLayer(name: "B", rgba: (255, 0, 0, 255))
        let top    = solidLayer(name: "T", rgba: (  0, 255, 0, 255))
        let frame = Frame(layers: [bottom, top], activeLayerID: bottom.id)
        let buf = Compositor.composite(frame, size: size)
        XCTAssertEqual(buf.data, top.pixels)
    }

    func testTopTransparentRevealsBottom() {
        let bottom = solidLayer(name: "B", rgba: (255, 0, 0, 255))
        let top    = solidLayer(name: "T", rgba: (  0,   0, 0,   0))
        let frame = Frame(layers: [bottom, top], activeLayerID: bottom.id)
        let buf = Compositor.composite(frame, size: size)
        XCTAssertEqual(buf.data, bottom.pixels)
    }

    func testHiddenLayerSkipped() {
        var bottom = solidLayer(name: "B", rgba: (255, 0, 0, 255))
        var top    = solidLayer(name: "T", rgba: (  0, 255, 0, 255))
        top.isVisible = false
        _ = bottom // appease compiler about var

        let frame = Frame(layers: [bottom, top], activeLayerID: bottom.id)
        let buf = Compositor.composite(frame, size: size)
        XCTAssertEqual(buf.data, bottom.pixels, "hidden top must not affect output")
    }

    func testAllHiddenProducesAllTransparent() {
        var l1 = solidLayer(name: "1", rgba: (255, 0, 0, 255)); l1.isVisible = false
        var l2 = solidLayer(name: "2", rgba: (  0, 255, 0, 255)); l2.isVisible = false
        let frame = Frame(layers: [l1, l2], activeLayerID: l1.id)
        let buf = Compositor.composite(frame, size: size)
        XCTAssertEqual(buf.data, Data(count: size.byteCount))
    }

    func testCompositedAlphaIsAlwaysZeroOr255() {
        // Per the rendering invariant, compositor output must never produce partial alpha.
        let bottom = solidLayer(name: "B", rgba: (255, 0, 0, 255))
        let top    = solidLayer(name: "T", rgba: (  0, 255, 0,   0))
        let frame = Frame(layers: [bottom, top], activeLayerID: bottom.id)
        let buf = Compositor.composite(frame, size: size)
        for i in stride(from: 3, to: buf.data.count, by: 4) {
            let a = buf.data[i]
            XCTAssertTrue(a == 0 || a == 255, "alpha must be 0 or 255, got \(a) at byte \(i)")
        }
    }
}
```

- [ ] **Step 2: Verify the test fails**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/CompositorTests
```
Expected: build failure ("cannot find 'Compositor' in scope").

- [ ] **Step 3: Write the implementation**

Create `DrawBit/Rendering/Compositor.swift`:

```swift
import Foundation

struct CompositedBuffer: Equatable {
    let data: Data
    let size: CanvasSize
}

enum Compositor {
    /// Composites visible layers using a "topmost non-transparent pixel wins" rule. Output's
    /// alpha is always 0 or 255 — preserved by the no-opacity scope of the layers feature.
    static func composite(_ frame: Frame, size: CanvasSize) -> CompositedBuffer {
        let byteCount = size.byteCount
        var out = Data(count: byteCount)

        // Walk layers top→bottom, painting only into still-transparent positions.
        let visible = frame.layers.filter { $0.isVisible }
        out.withUnsafeMutableBytes { outRaw in
            let dst = outRaw.bindMemory(to: UInt8.self)
            for layer in visible.reversed() {
                layer.pixels.withUnsafeBytes { srcRaw in
                    let src = srcRaw.bindMemory(to: UInt8.self)
                    var i = 0
                    while i < byteCount {
                        // Only fill if dst pixel is still fully transparent AND src is opaque.
                        if dst[i + 3] == 0 && src[i + 3] == 255 {
                            dst[i    ] = src[i    ]
                            dst[i + 1] = src[i + 1]
                            dst[i + 2] = src[i + 2]
                            dst[i + 3] = 255
                        }
                        i += 4
                    }
                }
            }
        }
        return CompositedBuffer(data: out, size: size)
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/CompositorTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Rendering/Compositor.swift DrawBitTests/Rendering/CompositorTests.swift
git commit -m "feat(layers): add Compositor with topmost-wins rule"
```

---

### Task 1.5: Rename `pixelsToCGImage` → `bufferToCGImage`

**Files:**
- Modify: `DrawBit/Rendering/PixelsToCGImage.swift`
- Modify: callers (will be touched in subsequent tasks; this task changes only the file itself + a thin compatibility test)
- Create: `DrawBitTests/Rendering/BufferToCGImageTests.swift`

- [ ] **Step 1: Write the failing test**

Create `DrawBitTests/Rendering/BufferToCGImageTests.swift`:

```swift
import XCTest
@testable import DrawBit

final class BufferToCGImageTests: XCTestCase {
    func testProducesCGImageWithCorrectDimensions() {
        let bytes = Data(count: CanvasSize.s32.byteCount)
        let buf = CompositedBuffer(data: bytes, size: .s32)
        let img = bufferToCGImage(buf)
        XCTAssertNotNil(img)
        XCTAssertEqual(img?.width, 32)
        XCTAssertEqual(img?.height, 32)
    }
}
```

- [ ] **Step 2: Verify the test fails**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/BufferToCGImageTests
```
Expected: build failure ("cannot find 'bufferToCGImage'").

- [ ] **Step 3: Update the implementation file**

Replace the entire contents of `DrawBit/Rendering/PixelsToCGImage.swift`:

```swift
import CoreGraphics
import Foundation

/// Wraps a CompositedBuffer's raw RGBA bytes in a CGImage. Uses sRGB explicitly (NEVER deviceRGB) so
/// rendering and export are consistent across iPad models including P3 displays.
func bufferToCGImage(_ buffer: CompositedBuffer) -> CGImage? {
    let dim = buffer.size.dimension
    let bytesPerRow = dim * 4

    guard let provider = CGDataProvider(data: buffer.data as CFData) else { return nil }
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let bitmapInfo: CGBitmapInfo = [
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    ]

    return CGImage(
        width: dim,
        height: dim,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}
```

Note: do NOT delete the file — XcodeGen references it. Just replace its contents.

- [ ] **Step 4: Run, verify pass**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/BufferToCGImageTests
```
Expected: PASS.

The full project will not compile yet because callers of the old `pixelsToCGImage` are still around. That gets fixed in Task 1.6 onward as we update each caller.

- [ ] **Step 5: Commit (test + impl together; project still has callers to fix)**

```bash
git add DrawBit/Rendering/PixelsToCGImage.swift DrawBitTests/Rendering/BufferToCGImageTests.swift
git commit -m "refactor(rendering): rename pixelsToCGImage -> bufferToCGImage"
```

---

### Task 1.6: `PNGExporter.export(frame:scale:)` + non-regression byte-identity test

**Files:**
- Modify: `DrawBit/Rendering/PNGExporter.swift`
- Create: `DrawBitTests/Rendering/SingleLayerNonRegressionTests.swift`

This is the load-bearing test for the entire feature: a single-layer piece exported via the new code path must produce **byte-identical** PNG output to the v1 code path.

- [ ] **Step 1: Write the failing non-regression test**

Create `DrawBitTests/Rendering/SingleLayerNonRegressionTests.swift`:

```swift
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DrawBit

final class SingleLayerNonRegressionTests: XCTestCase {
    /// Reference v1-style export: takes a raw PixelGrid and produces a PNG via the historic
    /// path (CGImage made from PixelGrid bytes directly, drawn into a CGContext at the target
    /// scale). This is held alongside the new code for the lifetime of the layers work and
    /// removed in a follow-up commit once all stages have shipped.
    private func v1ExportPNG(grid: PixelGrid, scale: Int) -> Data? {
        let dim = grid.dimension
        guard scale >= 1 else { return nil }
        guard let provider = CGDataProvider(data: grid.data as CFData) else { return nil }
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info: CGBitmapInfo = [CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)]
        guard let src = CGImage(width: dim, height: dim, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: dim * 4, space: cs, bitmapInfo: info, provider: provider,
                                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return nil
        }
        let outEdge = dim * scale
        guard let ctx = CGContext(data: nil, width: outEdge, height: outEdge, bitsPerComponent: 8,
                                  bytesPerRow: outEdge * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: outEdge, height: outEdge))
        guard let img = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private func patternedGrid(size: CanvasSize) -> PixelGrid {
        var data = Data(count: size.byteCount)
        let dim = size.dimension
        for y in 0..<dim {
            for x in 0..<dim {
                let i = (y * dim + x) * 4
                data[i    ] = UInt8((x * 8) & 0xFF)
                data[i + 1] = UInt8((y * 8) & 0xFF)
                data[i + 2] = UInt8((x ^ y) & 0xFF)
                data[i + 3] = ((x + y) % 3 == 0) ? 0 : 255
            }
        }
        return PixelGrid(data: data, size: size)
    }

    func testSingleLayerExportMatchesV1ForAllSizesAndScales() {
        for size in [CanvasSize.s16, .s32, .s64, .s128] {
            let grid = patternedGrid(size: size)
            let frame = Frame(
                layers: [Layer(name: "Layer 1", pixels: grid.data)],
                activeLayerID: UUID()
            )
            // Replace activeLayerID with the actual layer's id (Frame's init enforces membership).
            let layerID = frame.layers[0].id
            let goodFrame = Frame(layers: frame.layers, activeLayerID: layerID)

            for scale in [1, 2, 4, 8] {
                guard let v1 = v1ExportPNG(grid: grid, scale: scale) else {
                    XCTFail("v1 export failed for \(size) @ \(scale)x"); continue
                }
                guard let v2 = PNGExporter.export(frame: goodFrame, size: size, scale: scale) else {
                    XCTFail("v2 export failed for \(size) @ \(scale)x"); continue
                }
                XCTAssertEqual(v1, v2,
                    "PNG bytes diverged at \(size.displayName) @ \(scale)x — non-regression failed")
            }
        }
    }
}
```

- [ ] **Step 2: Verify the test fails**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/SingleLayerNonRegressionTests
```
Expected: build failure ("`PNGExporter.export(frame:size:scale:)` does not exist").

- [ ] **Step 3: Write the new export signature**

Replace `DrawBit/Rendering/PNGExporter.swift` contents:

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PNGExporter {
    static func export(frame: Frame, size: CanvasSize, scale: Int) -> Data? {
        guard scale >= 1 else { return nil }
        let buffer = Compositor.composite(frame, size: size)
        guard let source = bufferToCGImage(buffer) else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let outEdge = size.dimension * scale
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

The old `export(grid:scale:)` is fully replaced. Callers will be updated in Task 1.10.

- [ ] **Step 4: Run, verify pass**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/SingleLayerNonRegressionTests
```
Expected: PASS for all 16 combinations (4 sizes × 4 scales).

This is the gate test for the whole stage.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Rendering/PNGExporter.swift DrawBitTests/Rendering/SingleLayerNonRegressionTests.swift
git commit -m "feat(rendering): PNGExporter.export(frame:size:scale:) + byte-identity test"
```

---

### Task 1.7: `ThumbnailRenderer.render(frame:size:targetEdge:)`

**Files:**
- Modify: `DrawBit/Rendering/ThumbnailRenderer.swift`
- Create: `DrawBitTests/Rendering/ThumbnailRendererTests.swift`

- [ ] **Step 1: Write the failing test**

Create `DrawBitTests/Rendering/ThumbnailRendererTests.swift`:

```swift
import XCTest
@testable import DrawBit

final class ThumbnailRendererTests: XCTestCase {
    func testRendersToTargetEdgeForSingleLayerFrame() {
        let bytes = Data(count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: bytes)
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        let png = ThumbnailRenderer.render(frame: frame, size: .s32, targetEdge: 128)
        XCTAssertNotNil(png)
        XCTAssertGreaterThan(png?.count ?? 0, 0)
    }
}
```

- [ ] **Step 2: Verify the test fails**

Build error: signature mismatch.

- [ ] **Step 3: Replace contents**

Replace `DrawBit/Rendering/ThumbnailRenderer.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ThumbnailRenderer {
    static func render(frame: Frame, size: CanvasSize, targetEdge: Int) -> Data? {
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

- [ ] **Step 4: Run, verify pass**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/ThumbnailRendererTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Rendering/ThumbnailRenderer.swift DrawBitTests/Rendering/ThumbnailRendererTests.swift
git commit -m "feat(rendering): ThumbnailRenderer takes Frame+size"
```

---

### Task 1.8: `LayerThumbnailRenderer` for the panel

**Files:**
- Create: `DrawBit/Rendering/LayerThumbnailRenderer.swift`
- Create: `DrawBitTests/Rendering/LayerThumbnailRendererTests.swift`

- [ ] **Step 1: Write the failing test**

Create `DrawBitTests/Rendering/LayerThumbnailRendererTests.swift`:

```swift
import XCTest
@testable import DrawBit

final class LayerThumbnailRendererTests: XCTestCase {
    func testRendersSingleLayerToTargetEdge() {
        let bytes = Data(count: CanvasSize.s32.byteCount)
        let layer = Layer(name: "L", pixels: bytes)
        let png = LayerThumbnailRenderer.render(layer: layer, size: .s32, targetEdge: 64)
        XCTAssertNotNil(png)
        XCTAssertGreaterThan(png?.count ?? 0, 0)
    }
}
```

- [ ] **Step 2: Verify failure**

Build error: cannot find type.

- [ ] **Step 3: Implement**

Create `DrawBit/Rendering/LayerThumbnailRenderer.swift`:

```swift
import Foundation

/// Per-layer panel thumbnail. Wraps the layer's raw bytes in a one-layer Frame and
/// runs the standard ThumbnailRenderer so transparent areas are correctly transparent.
enum LayerThumbnailRenderer {
    static func render(layer: Layer, size: CanvasSize, targetEdge: Int) -> Data? {
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        return ThumbnailRenderer.render(frame: frame, size: size, targetEdge: targetEdge)
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/LayerThumbnailRendererTests
```

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Rendering/LayerThumbnailRenderer.swift DrawBitTests/Rendering/LayerThumbnailRendererTests.swift
git commit -m "feat(rendering): add LayerThumbnailRenderer for panel rows"
```

---

### Task 1.9: `Piece.pixels` → `Piece.frameData`

**Files:**
- Modify: `DrawBit/Models/Piece.swift`

- [ ] **Step 1: Inspect the current file**

Read `DrawBit/Models/Piece.swift` to confirm its current state.

- [ ] **Step 2: Replace contents**

```swift
import Foundation
import SwiftData

@Model
final class Piece {
    @Attribute(.unique) var id: UUID
    var name: String?
    var sizeRaw: Int

    /// Versioned blob holding the entire Frame (layers + active layer id).
    /// External storage keeps the row light when the blob grows with multiple layers.
    @Attribute(.externalStorage) var frameData: Data

    var thumbnail: Data
    var createdAt: Date
    var updatedAt: Date

    var size: CanvasSize {
        get { CanvasSize(rawValue: sizeRaw) ?? .s32 }
        set { sizeRaw = newValue.rawValue }
    }

    var effectiveName: String {
        if let name, !name.isEmpty { return name }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return "\(size.displayName) · \(df.string(from: createdAt))"
    }

    init(size: CanvasSize) {
        let now = Date()
        self.id = UUID()
        self.name = nil
        self.sizeRaw = size.rawValue
        // New pieces start as a single empty layer wrapped in a Frame and encoded.
        let layer = Layer(name: "Layer 1", pixels: Data(count: size.byteCount))
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        self.frameData = FrameCodec.encode(frame)
        self.thumbnail = Data()
        self.createdAt = now
        self.updatedAt = now
    }
}
```

- [ ] **Step 3: Build (project will fail because callers still use `pixels`)**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```
Expected: build errors at every site referencing `piece.pixels`. List them — those are the call sites updated in the next task.

- [ ] **Step 4: Note the failing call sites**

Write down the file:line references reported by xcodebuild. Expected sites:
- `DrawBit/Persistence/PieceRepository.swift` (load/save/duplicate)
- `DrawBit/State/EditorState.swift` (init from piece)
- `DrawBit/Views/Editor/EditorView.swift` (saveCurrentGrid)
- Any test that constructs `Piece` and reaches into `pixels`.

These get fixed in Task 1.10.

- [ ] **Step 5: Commit (intermediate; project not yet building)**

```bash
git add DrawBit/Models/Piece.swift
git commit -m "refactor(model): rename Piece.pixels -> frameData with Frame init"
```

---

### Task 1.10: `PieceRepository` — load/save Frame, eager + per-read migration

**Files:**
- Modify: `DrawBit/Persistence/PieceRepository.swift`
- Create: `DrawBitTests/Persistence/MigrationTests.swift`

- [ ] **Step 1: Read the current repository file**

Read `DrawBit/Persistence/PieceRepository.swift` to see its current API.

- [ ] **Step 2: Write the failing migration tests**

Create `DrawBitTests/Persistence/MigrationTests.swift`:

```swift
import XCTest
import SwiftData
@testable import DrawBit

@MainActor
final class MigrationTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Piece.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testV1RawBlobMigratesToSingleLayerFrameOnLoad() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let piece = Piece(size: .s32)
        // Force the piece into v1 shape: overwrite frameData with raw RGBA bytes (no DBFR magic).
        let v1 = Data(repeating: 0xAA, count: CanvasSize.s32.byteCount)
        piece.frameData = v1
        ctx.insert(piece)
        try ctx.save()

        let repo = PieceRepository(context: ctx)
        let frame = try repo.loadFrame(piece: piece)
        XCTAssertEqual(frame.layers.count, 1)
        XCTAssertEqual(frame.layers[0].pixels, v1)
        XCTAssertTrue(FrameCodec.hasV1MagicPrefix(piece.frameData),
                      "loadFrame must persist the migrated v2 blob back to disk")
    }

    func testEagerMigrationConvertsAllPieces() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let p1 = Piece(size: .s16)
        let p2 = Piece(size: .s32)
        p1.frameData = Data(repeating: 0x11, count: CanvasSize.s16.byteCount)
        p2.frameData = Data(repeating: 0x22, count: CanvasSize.s32.byteCount)
        ctx.insert(p1); ctx.insert(p2)
        try ctx.save()

        let repo = PieceRepository(context: ctx)
        try repo.migrateLegacyPiecesIfNeeded()

        XCTAssertTrue(FrameCodec.hasV1MagicPrefix(p1.frameData))
        XCTAssertTrue(FrameCodec.hasV1MagicPrefix(p2.frameData))
    }

    func testEagerMigrationIsIdempotent() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let piece = Piece(size: .s32)
        ctx.insert(piece)
        try ctx.save()
        let initialBlob = piece.frameData

        let repo = PieceRepository(context: ctx)
        try repo.migrateLegacyPiecesIfNeeded()
        try repo.migrateLegacyPiecesIfNeeded()

        XCTAssertEqual(piece.frameData, initialBlob, "second run must be a no-op")
    }
}
```

- [ ] **Step 3: Verify failure**

```bash
xcodebuild ... test -only-testing:DrawBitTests/MigrationTests
```
Expected: build failure ("`PieceRepository.loadFrame`/`migrateLegacyPiecesIfNeeded` does not exist").

- [ ] **Step 4: Update `PieceRepository`**

Modify the existing file to add the new API. Replace the body of `PieceRepository.swift` while keeping the existing class shape and other methods. Specifically:

1. Remove any references to `piece.pixels` and replace with `piece.frameData`.
2. Add `loadFrame(piece:)`, `saveFrame(piece:_:)`, and `migrateLegacyPiecesIfNeeded()` methods:

```swift
// Inside PieceRepository:

func loadFrame(piece: Piece) throws -> Frame {
    if FrameCodec.hasV1MagicPrefix(piece.frameData) {
        return try FrameCodec.decode(piece.frameData)
    }
    // Defense-in-depth: a piece slipped past the eager pass. Migrate in place.
    let frame = FrameCodec.wrapV1Data(piece.frameData, defaultName: "Layer 1")
    piece.frameData = FrameCodec.encode(frame)
    piece.updatedAt = Date()
    try context.save()
    return frame
}

func saveFrame(piece: Piece, _ frame: Frame) throws {
    piece.frameData = FrameCodec.encode(frame)
    piece.updatedAt = Date()
    let thumb = ThumbnailRenderer.render(frame: frame, size: piece.size, targetEdge: 256) ?? Data()
    piece.thumbnail = thumb
    try context.save()
}

func migrateLegacyPiecesIfNeeded() throws {
    let descriptor = FetchDescriptor<Piece>()
    let pieces = try context.fetch(descriptor)
    var dirty = false
    for piece in pieces where !FrameCodec.hasV1MagicPrefix(piece.frameData) {
        let frame = FrameCodec.wrapV1Data(piece.frameData, defaultName: "Layer 1")
        piece.frameData = FrameCodec.encode(frame)
        piece.updatedAt = Date()
        dirty = true
    }
    if dirty { try context.save() }
}
```

3. Update any existing `save(piece:pixels:)` (or equivalent) callers/methods that referred to `piece.pixels`. Those are now functions of a `Frame`, not a raw `Data`. If a method previously took `pixels: Data`, replace with `frame: Frame` and call through to `saveFrame`.

4. The `duplicate(piece:)` method (if present) must use `loadFrame(piece:)` to read the source's frame, regenerate fresh layer UUIDs (so the duplicate's layers don't share IDs with the source), encode, and store.

- [ ] **Step 5: Run migration tests**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/MigrationTests
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add DrawBit/Persistence/PieceRepository.swift DrawBitTests/Persistence/MigrationTests.swift
git commit -m "feat(persistence): Frame load/save + eager and per-read migration"
```

---

### Task 1.11: `EditorState` — `grid → frame` and `UndoEntry`

**Files:**
- Modify: `DrawBit/State/EditorState.swift`
- Create: `DrawBitTests/State/EditorStateLayersTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `DrawBitTests/State/EditorStateLayersTests.swift`:

```swift
import XCTest
@testable import DrawBit

final class EditorStateLayersTests: XCTestCase {
    private func newState() -> EditorState {
        let layer = Layer(name: "Layer 1", pixels: Data(count: CanvasSize.s32.byteCount))
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        return EditorState(pieceID: UUID(), size: .s32, frame: frame)
    }

    func testActiveLayerPixelGridReflectsActiveLayer() {
        let state = newState()
        XCTAssertEqual(state.activeLayerPixelGrid.size, .s32)
        XCTAssertEqual(state.activeLayerPixelGrid.data.count, CanvasSize.s32.byteCount)
    }

    func testDrawStrokeUndoRestoresActiveLayerOnly() {
        let state = newState()
        let originalPixels = state.activeLayerPixelGrid.data

        state.beginStrokeSnapshot()
        state.mutateActiveLayerPixels { data in
            data[0] = 0xFF
        }
        state.commitStroke()

        XCTAssertEqual(state.activeLayerPixelGrid.data[0], 0xFF)
        state.undo()
        XCTAssertEqual(state.activeLayerPixelGrid.data, originalPixels)
    }

    func testStructuralUndoRestoresWholeFrame() {
        let state = newState()
        let originalFrame = state.frame

        state.beginStructuralSnapshot()
        state.frame.addLayer(name: "Layer 2")
        state.commitStructuralChange()

        XCTAssertEqual(state.frame.layers.count, 2)
        state.undo()
        XCTAssertEqual(state.frame, originalFrame)
    }
}
```

- [ ] **Step 2: Verify failure**

```bash
xcodebuild ... test -only-testing:DrawBitTests/EditorStateLayersTests
```
Expected: build failure (EditorState API does not match).

- [ ] **Step 3: Replace `EditorState.swift`**

Replace the entire file with:

```swift
import Foundation
import Observation

@Observable
final class EditorState {
    let pieceID: UUID
    let size: CanvasSize

    /// Source of truth: the editable Frame. Tools mutate the active layer's pixels through this.
    var frame: Frame

    var tool: Tool = .pencil
    var color: RGBA = RGBA(r: 255, g: 255, b: 255, a: 255)

    var translation: CGSize = .zero
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0

    var selection: MarqueeSelection?
    var pendingMarqueeRect: PixelRect?

    private var selectionAnchor: (Int, Int)?
    private var dragAnchor: (Int, Int)?

    enum UndoEntry {
        case layerPixels(layerID: UUID, before: Data)
        case frameStructure(before: Frame)
    }

    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    private var preStrokeSnapshot: Data?
    private var preStrokeLayerID: UUID?
    private var preStructuralSnapshot: Frame?

    private let undoLimit = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var isMarqueeDefining: Bool { selectionAnchor != nil }
    var isMarqueeDragging: Bool { dragAnchor != nil }

    /// PixelGrid view of the active layer's pixels. Read-only — to mutate, use `mutateActiveLayerPixels`.
    var activeLayerPixelGrid: PixelGrid {
        PixelGrid(data: frame.activeLayer.pixels, size: size)
    }

    var activeLayerIsLocked: Bool { frame.activeLayer.isLocked }

    init(pieceID: UUID, size: CanvasSize, frame: Frame) {
        self.pieceID = pieceID
        self.size = size
        self.frame = frame
    }

    /// Convenience initializer mirroring v1's `init(piece:)`. Used by EditorView when a Frame is loaded.
    convenience init(piece: Piece, frame: Frame) {
        self.init(pieceID: piece.id, size: piece.size, frame: frame)
    }

    // MARK: - Active-layer pixel mutation

    func mutateActiveLayerPixels(_ body: (inout Data) -> Void) {
        frame.withActiveLayerPixels(body)
    }

    func setActiveLayerPixels(_ data: Data) {
        frame.withActiveLayerPixels { $0 = data }
    }

    // MARK: - Drawing-stroke undo

    func beginStrokeSnapshot() {
        preStrokeSnapshot = frame.activeLayer.pixels
        preStrokeLayerID = frame.activeLayerID
    }

    func commitStroke() {
        guard let snap = preStrokeSnapshot, let layerID = preStrokeLayerID else { return }
        push(.layerPixels(layerID: layerID, before: snap))
        preStrokeSnapshot = nil
        preStrokeLayerID = nil
    }

    func cancelStroke() {
        if let snap = preStrokeSnapshot, let layerID = preStrokeLayerID,
           let idx = frame.layers.firstIndex(where: { $0.id == layerID }) {
            // Restore by rebuilding the frame with the snapshot at idx.
            var layers = frame.layers
            layers[idx].pixels = snap
            frame = Frame(layers: layers, activeLayerID: frame.activeLayerID)
        }
        preStrokeSnapshot = nil
        preStrokeLayerID = nil
    }

    // MARK: - Structural-change undo

    func beginStructuralSnapshot() {
        preStructuralSnapshot = frame
    }

    func commitStructuralChange() {
        guard let snap = preStructuralSnapshot else { return }
        push(.frameStructure(before: snap))
        preStructuralSnapshot = nil
    }

    func cancelStructuralChange() {
        if let snap = preStructuralSnapshot {
            frame = snap
        }
        preStructuralSnapshot = nil
    }

    private func push(_ entry: UndoEntry) {
        undoStack.append(entry)
        if undoStack.count > undoLimit {
            undoStack.removeFirst(undoStack.count - undoLimit)
        }
        redoStack.removeAll()
    }

    func undo() {
        if selection != nil { commitMarquee() }
        guard let entry = undoStack.popLast() else { return }
        switch entry {
        case .layerPixels(let layerID, let before):
            guard let idx = frame.layers.firstIndex(where: { $0.id == layerID }) else { return }
            let after = frame.layers[idx].pixels
            redoStack.append(.layerPixels(layerID: layerID, before: after))
            var layers = frame.layers
            layers[idx].pixels = before
            frame = Frame(layers: layers, activeLayerID: frame.activeLayerID)
        case .frameStructure(let before):
            redoStack.append(.frameStructure(before: frame))
            frame = before
        }
    }

    func redo() {
        if selection != nil { commitMarquee() }
        guard let entry = redoStack.popLast() else { return }
        switch entry {
        case .layerPixels(let layerID, let before):
            guard let idx = frame.layers.firstIndex(where: { $0.id == layerID }) else { return }
            let after = frame.layers[idx].pixels
            undoStack.append(.layerPixels(layerID: layerID, before: after))
            var layers = frame.layers
            layers[idx].pixels = before
            frame = Frame(layers: layers, activeLayerID: frame.activeLayerID)
        case .frameStructure(let before):
            undoStack.append(.frameStructure(before: frame))
            frame = before
        }
    }

    // MARK: - Tool selection

    func setTool(_ next: Tool) {
        if selection != nil { commitMarquee() }
        if pendingMarqueeRect != nil { cancelMarquee() }
        tool = next
    }

    // MARK: - Marquee lifecycle (operates on active layer only)

    func beginMarqueeDefine(at point: (Int, Int)) {
        if selection != nil { commitMarquee() }
        beginStrokeSnapshot()
        selectionAnchor = point
        pendingMarqueeRect = PixelRect.from(point, point)
    }

    func updateMarqueeDefine(to point: (Int, Int)) {
        guard let anchor = selectionAnchor else { return }
        pendingMarqueeRect = PixelRect.from(anchor, point)
    }

    func endMarqueeDefine() {
        guard let rect = pendingMarqueeRect else { return }
        selectionAnchor = nil
        pendingMarqueeRect = nil
        var grid = activeLayerPixelGrid
        if let extracted = Marquee.extractAndCut(grid: &grid, rect: rect) {
            setActiveLayerPixels(grid.data)
            selection = MarqueeSelection(extracted: extracted, dragOffset: (0, 0))
        } else {
            cancelStroke()
        }
    }

    func beginMarqueeDrag(at point: (Int, Int)) {
        guard let sel = selection else { return }
        dragAnchor = (point.0 - sel.dragOffset.dx, point.1 - sel.dragOffset.dy)
    }

    func updateMarqueeDrag(to point: (Int, Int)) {
        guard var sel = selection, let anchor = dragAnchor else { return }
        sel.dragOffset = (dx: point.0 - anchor.0, dy: point.1 - anchor.1)
        selection = sel
    }

    func endMarqueeDrag() {
        dragAnchor = nil
    }

    func commitMarquee() {
        guard let sel = selection else { return }
        var grid = activeLayerPixelGrid
        Marquee.commit(into: &grid, selection: sel.extracted, offset: sel.dragOffset)
        setActiveLayerPixels(grid.data)
        selection = nil
        dragAnchor = nil
        commitStroke()
    }

    func cancelMarquee() {
        selection = nil
        pendingMarqueeRect = nil
        selectionAnchor = nil
        dragAnchor = nil
        cancelStroke()
    }
}

struct MarqueeSelection: Equatable {
    var extracted: ExtractedSelection
    var dragOffset: (dx: Int, dy: Int)

    var displayBounds: PixelRect {
        extracted.originalBounds.translated(dx: dragOffset.dx, dy: dragOffset.dy)
    }

    static func == (lhs: MarqueeSelection, rhs: MarqueeSelection) -> Bool {
        lhs.extracted == rhs.extracted
            && lhs.dragOffset.dx == rhs.dragOffset.dx
            && lhs.dragOffset.dy == rhs.dragOffset.dy
    }
}
```

- [ ] **Step 4: Run new + existing tests**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... test -only-testing:DrawBitTests/EditorStateLayersTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/State/EditorState.swift DrawBitTests/State/EditorStateLayersTests.swift
git commit -m "feat(state): EditorState owns Frame; tagged undo for pixels vs structure"
```

---

### Task 1.12: Update `EditorView`, `CanvasView`, and `ShareSheet` call sites

**Files:**
- Modify: `DrawBit/Views/Editor/EditorView.swift`
- Modify: `DrawBit/Views/Editor/CanvasView.swift`
- Modify: `DrawBit/Views/Editor/ShareSheet.swift`

This task makes the project build again. No new tests; the existing UI test (`DrawBitUITests`) is the implicit gate.

ShareSheet currently does (verified at `ShareSheet.swift:130`):
```swift
let grid = PixelGrid(data: piece.pixels, size: piece.size)
... PNGExporter.export(grid: grid, scale: scale) ...
```

Replace with:
```swift
let repo = PieceRepository(context: modelContext)
let frame = (try? repo.loadFrame(piece: piece))
    ?? Frame(layers: [Layer(name: "Layer 1", pixels: Data(count: piece.size.byteCount))],
             activeLayerID: UUID()) // unreachable fallback; loadFrame always succeeds for migrated pieces
... PNGExporter.export(frame: frame, size: piece.size, scale: scale) ...
```

If `ShareSheet` does not currently have `@Environment(\.modelContext)`, add it.

- [ ] **Step 1: Read both files**

Read `DrawBit/Views/Editor/EditorView.swift` and `DrawBit/Views/Editor/CanvasView.swift` in full.

- [ ] **Step 2: Update `EditorView.init` to load the Frame**

Replace EditorView's `init(piece:)` and `body.onAppear` so the editor state is built from a loaded `Frame`:

```swift
init(piece: Piece) {
    self.piece = piece
    // Initial state is created in body.task using PieceRepository to load the frame.
    self._state = State(initialValue: nil)
}

@State private var state: EditorState? = nil
```

In `body`, wrap the existing layout in a check:

```swift
var body: some View {
    Group {
        if let state {
            VStack(spacing: 0) {
                topBar(state: state)
                Divider().overlay(Color.white.opacity(0.08))
                CanvasView(state: state, ...)
                Divider().overlay(Color.white.opacity(0.08))
                bottomBar(state: state)
            }
        } else {
            ProgressView().background(Color(white: 0.10).ignoresSafeArea())
        }
    }
    .task {
        if state == nil {
            let repo = PieceRepository(context: modelContext)
            if let frame = try? repo.loadFrame(piece: piece) {
                state = EditorState(piece: piece, frame: frame)
            }
        }
    }
    // ... rest of modifiers identical, but reference `state!` or accept the optional
}
```

Replace existing `state.grid` references throughout the file with `state.activeLayerPixelGrid` for *reads*, and use `state.mutateActiveLayerPixels { ... }` for *writes*.

Update the four tool dispatches in `applyDrawPoint`:

```swift
private func applyDrawPoint(state: EditorState, x: Int, y: Int) {
    if state.activeLayerIsLocked && (state.tool == .pencil || state.tool == .eraser
                                     || state.tool == .fill   || state.tool == .marquee) {
        return // lock-pulse animation will be wired in Stage 4
    }
    switch state.tool {
    case .pencil:
        state.mutateActiveLayerPixels { data in
            var grid = PixelGrid(data: data, size: state.size)
            Pencil.paint(on: &grid, at: (x, y), color: state.color)
            data = grid.data
        }
    case .eraser:
        state.mutateActiveLayerPixels { data in
            var grid = PixelGrid(data: data, size: state.size)
            Eraser.erase(on: &grid, at: (x, y))
            data = grid.data
        }
    case .fill:
        state.mutateActiveLayerPixels { data in
            var grid = PixelGrid(data: data, size: state.size)
            Fill.fill(on: &grid, at: (x, y), with: state.color)
            data = grid.data
        }
    case .eyedropper:
        let buffer = Compositor.composite(state.frame, size: state.size)
        let grid = PixelGrid(data: buffer.data, size: state.size)
        if let picked = Eyedropper.pick(from: grid, at: (x, y)) {
            state.color = picked
        }
    case .marquee:
        applyMarqueePoint(state: state, x: x, y: y)
    }
}
```

Update `saveCurrentGrid` (rename to `saveCurrentFrame`):

```swift
private func saveCurrentFrame(state: EditorState) {
    let repo = PieceRepository(context: modelContext)
    try? repo.saveFrame(piece: piece, state.frame)
}
```

Update `clearCanvas` to clear the active layer only:

```swift
private func clearCanvas(state: EditorState) {
    if state.selection != nil { state.cancelMarquee() }
    state.beginStrokeSnapshot()
    state.setActiveLayerPixels(Data(count: state.size.byteCount))
    state.commitStroke()
    saveCurrentFrame(state: state)
}
```

- [ ] **Step 3: Update `CanvasView`**

Read CanvasView. It currently builds a CGImage from `state.grid`. Change it to build the CGImage from a composited buffer:

```swift
// Where the displayed CGImage is computed:
private var displayImage: CGImage? {
    let buffer = Compositor.composite(state.frame, size: state.size)
    return bufferToCGImage(buffer)
}
```

If marquee floats a selection, the existing draw-overlay path stays the same — it draws the floating extracted pixels on top of the composited image.

- [ ] **Step 4: Build the project**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```
Expected: success.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Views/Editor/EditorView.swift DrawBit/Views/Editor/CanvasView.swift
git commit -m "refactor(views): route editor through Frame + Compositor"
```

---

### Task 1.13: Wire eager migration into app launch

**Files:**
- Modify: `DrawBit/DrawBitApp.swift`

- [ ] **Step 1: Read current file**

Read `DrawBit/DrawBitApp.swift` — note where the ModelContainer is initialized.

- [ ] **Step 2: Run migration on first context use**

In `DrawBitApp.swift`, after the `ModelContainer` is created, schedule the eager migration. One pattern is a `task` modifier on the root view that runs once:

```swift
struct DrawBitApp: App {
    var sharedModelContainer: ModelContainer = {
        // ... existing setup
    }()

    var body: some Scene {
        WindowGroup {
            GalleryView()
                .task {
                    let ctx = ModelContext(sharedModelContainer)
                    let repo = PieceRepository(context: ctx)
                    try? repo.migrateLegacyPiecesIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
```

If GalleryView already has a `.task` modifier, append the migration call there.

- [ ] **Step 3: Build**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... build
```
Expected: success.

- [ ] **Step 4: Run all tests**

```bash
xcodebuild ... test
```
Expected: all unit tests PASS, including the existing test suite (Drawing/, Rendering/, Persistence/).

- [ ] **Step 5: Commit**

```bash
git add DrawBit/DrawBitApp.swift
git commit -m "feat(app): run eager layers migration on launch"
```

---

### Task 1.14: Existing-test sweep — every pre-stage-1 test must still pass

**Files:**
- Modify (only as needed): existing test files that constructed `Piece` via `pixels` directly

- [ ] **Step 1: Run the full test suite**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```

- [ ] **Step 2: For every failure, fix the call site**

Most failures will be in tests that previously did `piece.pixels = data` or `state.grid = ...`. Update each to use the new API:

- `piece.pixels = data` → `piece.frameData = FrameCodec.encode(Frame(layers: [Layer(name: "Layer 1", pixels: data)], activeLayerID: <that-layer-id>))`. (Or rely on `Piece(size:)` which already creates a one-layer Frame.)
- `state.grid` reads → `state.activeLayerPixelGrid`.
- `state.grid = newGrid` → `state.setActiveLayerPixels(newGrid.data)`.

- [ ] **Step 3: Re-run the full suite until green**

Repeat until `xcodebuild ... test` is fully green.

- [ ] **Step 4: Run the device-target compile check**

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
Expected: success.

- [ ] **Step 5: Commit any test fixes**

```bash
git add DrawBitTests/
git commit -m "test: update legacy call sites to use Frame API"
```

---

### Task 1.15: Manual on-device check (Stage 1 gate)

This is a non-code task — but it is the gate before merging Stage 1 to `main`.

- [ ] **Step 1: Open existing pieces from before this branch**

Boot the app on simulator (or device, ideally device). Confirm:
- Gallery loads, all existing pieces appear with their existing thumbnails.
- Tapping a piece opens the editor; pixels look identical to v1.

- [ ] **Step 2: Draw, save, reopen**

Draw a few strokes, dismiss editor, reopen. Pixels persist.

- [ ] **Step 3: Export to Photos**

Export a piece. Open in Photos. Visual sanity match to what's on screen.

- [ ] **Step 4: Verify migration is idempotent**

Quit and relaunch the app. Open a piece you've already opened post-migration. No flicker, no visible re-migration, pixels still correct.

- [ ] **Step 5: Tag and merge**

If everything looks right:

```bash
git tag stage-1-plumbing
git checkout main
git merge --no-ff layers -m "merge: layers stage 1 — plumbing only, no behavior change"
git push origin main
git checkout layers
```

Stage 1 done.

---

## Stage 2 — Read-only layers panel

**Goal of stage:** The user can see a layers panel with one row, rename it. No add / delete / reorder yet.

### Task 2.1: `LayerRow` view (read-only)

**Files:**
- Create: `DrawBit/Views/Editor/LayerRow.swift`

- [ ] **Step 1: Inspect existing view conventions**

Read `DrawBit/Views/Editor/RecentColorsStrip.swift` — match the styling tone (compact, monospace, dark grey background).

- [ ] **Step 2: Implement the row**

Create `DrawBit/Views/Editor/LayerRow.swift`:

```swift
import SwiftUI

struct LayerRow: View {
    let layer: Layer
    let size: CanvasSize
    let isActive: Bool
    let onTap: () -> Void
    let onRename: (String) -> Void

    @State private var isEditingName = false
    @State private var draftName = ""

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            if isEditingName {
                TextField("", text: $draftName)
                    .font(.pixel(11))
                    .foregroundStyle(.white)
                    .onSubmit {
                        onRename(String(draftName.prefix(32)))
                        isEditingName = false
                    }
            } else {
                Text(layer.name)
                    .font(.pixel(11))
                    .foregroundStyle(.white)
                    .onLongPressGesture {
                        draftName = layer.name
                        isEditingName = true
                    }
            }
            Spacer()
            Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                .foregroundStyle(.white.opacity(0.55))
            Image(systemName: layer.isLocked  ? "lock.fill" : "lock.open")
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.blue.opacity(0.30) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var thumbnail: some View {
        Group {
            if let png = LayerThumbnailRenderer.render(layer: layer, size: size, targetEdge: 64),
               let img = UIImage(data: png)?.cgImage {
                Image(decorative: img, scale: 1.0, orientation: .up)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .frame(width: 32, height: 32)
                    .background(checkerboard)
            } else {
                Rectangle().fill(.gray).frame(width: 32, height: 32)
            }
        }
    }

    private var checkerboard: some View {
        Canvas { ctx, sz in
            let s: CGFloat = 4
            for y in stride(from: 0, to: sz.height, by: s) {
                for x in stride(from: 0, to: sz.width, by: s) {
                    let isDark = (Int(x / s) + Int(y / s)) % 2 == 0
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(isDark ? .gray.opacity(0.4) : .gray.opacity(0.2)))
                }
            }
        }
        .frame(width: 32, height: 32)
    }
}
```

- [ ] **Step 3: Build**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... build
```
Expected: success.

- [ ] **Step 4: Commit**

```bash
git add DrawBit/Views/Editor/LayerRow.swift
git commit -m "feat(views): add LayerRow (read-only)"
```

- [ ] **Step 5: Skip — no test for purely visual view yet (covered by stage 2 UI test in Task 2.4)**

---

### Task 2.2: `LayersPanel` view (read-only, ~38% width overlay)

**Files:**
- Create: `DrawBit/Views/Editor/LayersPanel.swift`

- [ ] **Step 1: Implement the panel**

```swift
import SwiftUI

struct LayersPanel: View {
    @Bindable var state: EditorState
    let isPresented: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            if isPresented {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }

                VStack(spacing: 0) {
                    HStack {
                        Text("LAYERS").font(.pixel(11)).foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark").foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider().overlay(Color.white.opacity(0.08))

                    // Top of list = top of stack (layers stored bottom-up; reverse for display).
                    List {
                        ForEach(state.frame.layers.reversed(), id: \.id) { layer in
                            LayerRow(
                                layer: layer,
                                size: state.size,
                                isActive: layer.id == state.frame.activeLayerID,
                                onTap: { state.frame.setActive(id: layer.id) },
                                onRename: { newName in
                                    state.beginStructuralSnapshot()
                                    state.frame.setName(id: layer.id, to: newName)
                                    state.commitStructuralChange()
                                }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)

                    // Action bar — disabled placeholders for stage 2.
                    HStack(spacing: 12) {
                        Image(systemName: "plus").opacity(0.3)
                        Image(systemName: "doc.on.doc").opacity(0.3)
                        Image(systemName: "trash").opacity(0.3)
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: .infinity)
                .frame(width: 360)
                .background(Color(white: 0.10))
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isPresented)
    }
}
```

- [ ] **Step 2: Build**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... build
```

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Editor/LayersPanel.swift
git commit -m "feat(views): add LayersPanel (read-only overlay)"
```

---

### Task 2.3: Wire the LAYERS button + panel into `EditorView`

**Files:**
- Modify: `DrawBit/Views/Editor/EditorView.swift`

- [ ] **Step 1: Add panel-toggle state**

```swift
@State private var showingLayersPanel = false
```

- [ ] **Step 2: Add the button to the top bar**

Inside the existing `topBar` `HStack`, between size label and Share:

```swift
Button {
    showingLayersPanel.toggle()
} label: {
    Text("LAYERS").font(.pixel(11))
}
.foregroundStyle(showingLayersPanel ? .blue : .white)
```

- [ ] **Step 3: Overlay the panel on top of the editor**

Wrap the existing VStack in a ZStack and add the panel as an overlay:

```swift
ZStack(alignment: .trailing) {
    VStack(spacing: 0) {
        // ... existing content
    }
    LayersPanel(state: state, isPresented: showingLayersPanel) {
        showingLayersPanel = false
    }
}
```

- [ ] **Step 4: Build & manual smoke test**

Build, run on simulator. Verify:
- LAYERS button appears.
- Tapping it shows the panel.
- The single layer "Layer 1" appears.
- Long-press the name → text field appears → type → submit → name changes.
- Tap dim area → panel dismisses.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Views/Editor/EditorView.swift
git commit -m "feat(views): wire LAYERS button + panel into editor"
```

---

### Task 2.4: One UI smoke test (Stage 2)

**Files:**
- Modify: `DrawBitUITests/HappyPathTests/...` (or create `LayersPanelUITests.swift`)

- [ ] **Step 1: Add a test that opens the panel and renames the layer**

Create `DrawBitUITests/LayersPanelUITests.swift`:

```swift
import XCTest

final class LayersPanelUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOpenPanelAndRenameLayer() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset"]
        app.launch()

        // Create a fresh piece
        app.buttons["+ NEW"].firstMatch.tap() // depends on exact accessibility id of the New button
        // Pick a size — assume 32 is visible and tappable
        app.buttons["32 × 32"].firstMatch.tap()

        // Open the layers panel
        app.buttons["LAYERS"].tap()
        XCTAssertTrue(app.staticTexts["Layer 1"].waitForExistence(timeout: 2))

        // Long-press to rename
        app.staticTexts["Layer 1"].press(forDuration: 0.6)
        let field = app.textFields.firstMatch
        field.typeText("Sketch\n")

        XCTAssertTrue(app.staticTexts["Sketch"].waitForExistence(timeout: 2))
    }
}
```

If the accessibility identifiers for the `+ NEW` button or size buttons don't match, fix them in `GalleryView.swift` or pass through `accessibilityIdentifier(...)`. Keep the rest of this task focused on getting the test green.

- [ ] **Step 2: Run the UI test**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitUITests/LayersPanelUITests
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add DrawBitUITests/LayersPanelUITests.swift DrawBit/Views/Gallery/GalleryView.swift
git commit -m "test(ui): smoke test for stage-2 layers panel"
```

- [ ] **Step 4: Manual device check**

Run on a physical iPad. Open panel, rename layer, dismiss. No glitches.

- [ ] **Step 5: Tag and merge to main**

```bash
git tag stage-2-readonly-panel
git checkout main
git merge --no-ff layers -m "merge: layers stage 2 — read-only panel"
git push origin main
git checkout layers
```

---

## Stage 3 — Add / delete / duplicate / reorder

### Task 3.1: Wire the action bar (`+`, duplicate, `×`)

**Files:**
- Modify: `DrawBit/Views/Editor/LayersPanel.swift`

- [ ] **Step 1: Replace placeholder action bar with active buttons**

In `LayersPanel.swift`, replace the disabled HStack with:

```swift
HStack(spacing: 12) {
    Button {
        state.beginStructuralSnapshot()
        state.frame.addLayer(name: "Layer \(state.frame.layers.count + 1)")
        state.commitStructuralChange()
    } label: {
        Image(systemName: "plus")
    }
    .disabled(state.frame.layers.count >= 16)

    Button {
        state.beginStructuralSnapshot()
        state.frame.duplicateActiveLayer()
        state.commitStructuralChange()
    } label: {
        Image(systemName: "doc.on.doc")
    }
    .disabled(state.frame.layers.count >= 16)

    Button {
        let active = state.frame.activeLayer
        let isEmpty = active.pixels.allSatisfy { $0 == 0 }
        if isEmpty {
            state.beginStructuralSnapshot()
            state.frame.removeLayer(id: active.id)
            state.commitStructuralChange()
        } else {
            confirmDeleteLayerID = active.id
        }
    } label: {
        Image(systemName: "trash")
    }
    .disabled(state.frame.layers.count <= 1)

    Spacer()
}
.foregroundStyle(.white)
.padding(.horizontal, 12)
.padding(.vertical, 10)
.confirmationDialog(
    "Delete this layer?",
    isPresented: Binding(
        get: { confirmDeleteLayerID != nil },
        set: { if !$0 { confirmDeleteLayerID = nil } }
    )
) {
    Button("Delete", role: .destructive) {
        if let id = confirmDeleteLayerID {
            state.beginStructuralSnapshot()
            state.frame.removeLayer(id: id)
            state.commitStructuralChange()
        }
        confirmDeleteLayerID = nil
    }
    Button("Cancel", role: .cancel) { confirmDeleteLayerID = nil }
}
```

Add `@State private var confirmDeleteLayerID: UUID?` to LayersPanel.

- [ ] **Step 2: Build**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... build
```

- [ ] **Step 3: Manual smoke**

Add a second layer. Confirm it appears at the top of the displayed list (because it's stacked on top). Make active by tap. Duplicate. Delete (empty → no dialog; non-empty → dialog). Cap of 16 disables `+` and duplicate.

- [ ] **Step 4: Commit**

```bash
git add DrawBit/Views/Editor/LayersPanel.swift
git commit -m "feat(layers): add/duplicate/delete actions in panel"
```

---

### Task 3.2: Reorder via SwiftUI's `.onMove`

**Files:**
- Modify: `DrawBit/Views/Editor/LayersPanel.swift`

- [ ] **Step 1: Convert ForEach to support move**

Change the List section to:

```swift
List {
    ForEach(state.frame.layers.reversed(), id: \.id) { layer in
        // ... LayerRow as before
    }
    .onMove { indices, newOffset in
        // The displayed list is reversed; convert displayed indices back to model indices.
        guard let from = indices.first else { return }
        let count = state.frame.layers.count
        let displayedFrom = from
        let displayedTo = newOffset > count ? count : newOffset
        let modelFrom = count - 1 - displayedFrom
        let modelTo   = count - 1 - max(0, min(count - 1, displayedTo - (displayedTo > displayedFrom ? 1 : 0)))
        let id = state.frame.layers[modelFrom].id

        state.beginStructuralSnapshot()
        state.frame.move(id: id, toIndex: modelTo)
        state.commitStructuralChange()
    }
}
.environment(\.editMode, .constant(.active)) // expose drag handles
```

- [ ] **Step 2: Build & manual smoke**

Verify dragging a row in the panel reorders. Top-of-list still corresponds to top-of-stack visually on the canvas.

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Editor/LayersPanel.swift
git commit -m "feat(layers): reorder layers via drag in panel"
```

- [ ] **Step 4: Skip — covered by Stage 3 UI test below**

- [ ] **Step 5: Skip — no separate commit**

---

### Task 3.3: Auto-commit floating marquee on layer-state changes

**Files:**
- Modify: `DrawBit/State/EditorState.swift`
- Modify: `DrawBit/Views/Editor/LayersPanel.swift`

- [ ] **Step 1: Wrap layer mutations to commit any floating marquee first**

In `LayersPanel.swift`, before each mutation call (`addLayer`, `duplicateActiveLayer`, `removeLayer`, `move`, `setActive`, `setName`), add:

```swift
if state.selection != nil {
    state.commitMarquee()
}
```

If this duplication grows, hoist into an `EditorState.commitFloatingSelectionIfAny()` helper.

- [ ] **Step 2: Build**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... build
```

- [ ] **Step 3: Test manually**

Start a marquee selection, drag it, then switch active layer in the panel — the floating selection should commit (cut+paste at the drag offset on the original active layer) before the active layer changes.

- [ ] **Step 4: Commit**

```bash
git add DrawBit/Views/Editor/LayersPanel.swift
git commit -m "fix(layers): commit floating marquee before layer mutations"
```

- [ ] **Step 5: Skip**

---

### Task 3.4: UI smoke test for Stage 3

**Files:**
- Modify: `DrawBitUITests/LayersPanelUITests.swift`

- [ ] **Step 1: Add a flow test**

Append:

```swift
func testAddDrawDeleteUndoFlow() {
    let app = XCUIApplication()
    app.launchArguments = ["-UITest-reset"]
    app.launch()
    app.buttons["+ NEW"].firstMatch.tap()
    app.buttons["32 × 32"].firstMatch.tap()
    app.buttons["LAYERS"].tap()
    // Add a second layer
    app.buttons["plus"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Layer 2"].waitForExistence(timeout: 2))
    // Dismiss panel
    app.buttons["LAYERS"].tap()
    // Draw on the active (Layer 2)
    let canvas = app.otherElements["Canvas"].firstMatch
    canvas.tap()
    // Reopen panel
    app.buttons["LAYERS"].tap()
    // Delete active (empty if it wasn't drawn on visibly; but we tapped — handle confirmation if shown)
    app.buttons["trash"].firstMatch.tap()
    if app.buttons["Delete"].exists { app.buttons["Delete"].tap() }
    XCTAssertFalse(app.staticTexts["Layer 2"].exists)
}
```

If `Canvas` accessibility identifier isn't set, add `.accessibilityIdentifier("Canvas")` to the `CanvasView` root.

- [ ] **Step 2: Run**

```bash
xcodebuild ... test -only-testing:DrawBitUITests/LayersPanelUITests/testAddDrawDeleteUndoFlow
```
Expected: PASS.

- [ ] **Step 3: Manual on-device pass**

- Add 2-3 layers. Draw on each. Reorder. Undo each operation in turn. State matches expectation.
- Cap test: keep adding layers — at 16, `+` greys out.
- Delete-the-last: with one layer, `×` is disabled.

- [ ] **Step 4: Tag and merge**

```bash
git tag stage-3-add-delete-reorder
git checkout main
git merge --no-ff layers -m "merge: layers stage 3 — add/delete/reorder"
git push origin main
git checkout layers
```

- [ ] **Step 5: Skip**

---

## Stage 4 — Visibility + lock

### Task 4.1: Visibility toggle from the row

**Files:**
- Modify: `DrawBit/Views/Editor/LayerRow.swift`
- Modify: `DrawBit/Views/Editor/LayersPanel.swift`

- [ ] **Step 1: Add `onToggleVisible` callback to LayerRow**

```swift
let onToggleVisible: () -> Void
// ...
Button { onToggleVisible() } label: {
    Image(systemName: layer.isVisible ? "eye" : "eye.slash")
        .foregroundStyle(.white.opacity(layer.isVisible ? 0.85 : 0.45))
}
.buttonStyle(.plain)
```

- [ ] **Step 2: Wire in LayersPanel**

In `LayersPanel`'s `LayerRow(...)` call:

```swift
onToggleVisible: {
    if state.selection != nil { state.commitMarquee() }
    state.beginStructuralSnapshot()
    state.frame.setVisible(id: layer.id, to: !layer.isVisible)
    state.commitStructuralChange()
}
```

- [ ] **Step 3: Build, smoke, commit**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... build
git add DrawBit/Views/Editor/LayerRow.swift DrawBit/Views/Editor/LayersPanel.swift
git commit -m "feat(layers): visibility toggle from panel"
```

- [ ] **Step 4: Skip**

- [ ] **Step 5: Skip**

---

### Task 4.2: Lock toggle + lock guard in `EditorView`

**Files:**
- Modify: `DrawBit/Views/Editor/LayerRow.swift`
- Modify: `DrawBit/Views/Editor/LayersPanel.swift`
- Modify: `DrawBit/Views/Editor/EditorView.swift`

- [ ] **Step 1: Add `onToggleLocked` callback to LayerRow**

Mirror the visibility wiring with a padlock button.

- [ ] **Step 2: Wire in LayersPanel**

```swift
onToggleLocked: {
    if state.selection != nil { state.commitMarquee() }
    state.beginStructuralSnapshot()
    state.frame.setLocked(id: layer.id, to: !layer.isLocked)
    state.commitStructuralChange()
}
```

- [ ] **Step 3: Confirm lock guard in `applyDrawPoint`**

The guard was added in Task 1.12 already. Verify it's still there:

```swift
if state.activeLayerIsLocked && (state.tool == .pencil || state.tool == .eraser
                                  || state.tool == .fill || state.tool == .marquee) {
    triggerLockPulse(layerID: state.frame.activeLayerID)
    return
}
```

Also guard `handleTap` and marquee define entry.

- [ ] **Step 4: Add a `triggerLockPulse` mechanism**

In `EditorState`, add a `@Published`-equivalent ephemeral signal:

```swift
var lockPulseLayerID: UUID? = nil
```

In `EditorView`:

```swift
private func triggerLockPulse(state: EditorState, layerID: UUID) {
    state.lockPulseLayerID = layerID
    Task {
        try? await Task.sleep(nanoseconds: 400_000_000)
        if state.lockPulseLayerID == layerID {
            state.lockPulseLayerID = nil
        }
    }
}
```

In `LayerRow`, observe `lockPulseLayerID` (passed in as a binding) and animate a brief red border when it matches.

- [ ] **Step 5: Build, smoke, commit**

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild ... build
git add DrawBit/Views/Editor/
git commit -m "feat(layers): lock toggle, lock guard, lock-pulse animation"
```

---

### Task 4.3: UI smoke test for Stage 4

**Files:**
- Modify: `DrawBitUITests/LayersPanelUITests.swift`

- [ ] **Step 1: Add visibility + lock test**

```swift
func testVisibilityAndLock() {
    let app = XCUIApplication()
    app.launchArguments = ["-UITest-reset"]
    app.launch()
    app.buttons["+ NEW"].firstMatch.tap()
    app.buttons["32 × 32"].firstMatch.tap()
    app.buttons["LAYERS"].tap()
    // Toggle visibility
    app.buttons["eye"].firstMatch.tap()
    XCTAssertTrue(app.buttons["eye.slash"].firstMatch.exists)
    // Toggle lock
    app.buttons["lock.open"].firstMatch.tap()
    XCTAssertTrue(app.buttons["lock.fill"].firstMatch.exists)
}
```

- [ ] **Step 2: Run**

```bash
xcodebuild ... test -only-testing:DrawBitUITests/LayersPanelUITests/testVisibilityAndLock
```

- [ ] **Step 3: Manual on-device check**

- Hide a layer that has pixels — canvas updates. Show again — pixels reappear unchanged.
- Lock a layer, attempt to draw — no pixels appear, the row pulses.
- Lock the active layer mid-drag — current stroke is no-op'd (or cancels cleanly).

- [ ] **Step 4: Tag and merge**

```bash
git tag stage-4-visibility-lock
git checkout main
git merge --no-ff layers -m "merge: layers stage 4 — visibility + lock"
git push origin main
```

- [ ] **Step 5: Cleanup — delete `v1ExportPNG` reference impl**

The non-regression test's reference v1 implementation can stay if you want belt-and-suspenders, but it's also fine to remove it now that all stages have shipped:

```bash
git checkout main
# edit DrawBitTests/Rendering/SingleLayerNonRegressionTests.swift, delete the v1ExportPNG helper and its callsite, replacing with assertions that PNGExporter.export(frame:) for a single-layer frame produces non-empty PNG bytes.
```

If kept, leave a comment in the file explaining what the v1 reference is for.

---

## Plan complete. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration with checkpoints. Best for a multi-day implementation where you want low-context-bleed reviews after each task.

2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints for review.

**Which approach?**
