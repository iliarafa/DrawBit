# Time-lapse / Process Replay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record the composited canvas after each committed action, persist it with the drawing, and export a short MP4 "watch it paint itself" clip from the share sheet.

**Architecture:** Pure-logic recorder + codecs in `Drawing/`; a new AVFoundation `MP4Exporter` in `Rendering/`; capture hooks in `EditorState`; one additive optional column on `Piece` (lightweight migration); a `FILM` format in the existing share sheet with an animated preview.

**Tech Stack:** Swift, SwiftUI, SwiftData, CoreGraphics, ImageIO, **AVFoundation/CoreVideo/CoreMedia** (new, for `MP4Exporter`), XCTest, xcodegen.

## Global Constraints

- **Pure-logic imports:** `Drawing/` and `Rendering/` import only Foundation / CoreGraphics / ImageIO / UniformTypeIdentifiers — **plus, for `MP4Exporter` only, AVFoundation / CoreVideo / CoreMedia.** No SwiftUI / SwiftData / UIKit anywhere in these layers.
- **sRGB always:** every CG color space is `CGColorSpace(name: CGColorSpace.sRGB)`, never `deviceRGB`.
- **Nearest-neighbor always:** every CGContext sets `interpolationQuality = .none` and `setShouldAntialias(false)`.
- **Straight alpha 0/255:** composited buffers have alpha exactly 0 or 255. The MP4 matte is fully opaque; video has no alpha.
- **Single live schema:** `timelapseData` is an additive **optional** column → inferred lightweight migration. Do **NOT** add a `DrawBitSchemaV2`.
- **PieceRepository is the only SwiftData seam.** Views never touch `ModelContext` for the new column except the one property read in `EditorView.init` (mirrors `setReference`).
- **Reference photo stays display-only:** the recorder snapshots `Compositor.composite(...)` (layers only) — never the reference photo.
- **Constants (single source, all reversible taste calls):** `Timelapse.maxStoredKeyframes = 240`, `Timelapse.targetClipFrames = 120`, `Timelapse.clipFPS = 24`, `MP4Exporter.defaultMatte = RGBA(r: 26, g: 26, b: 26, a: 255)`, hold last = `1.2`s, `FILM` label, min-frames-to-enable = `2`.
- **Build/test env:** simulator `iPad Pro 13-inch (M5)`. After adding/renaming any `.swift`, regenerate: `rm -rf DrawBit.xcodeproj && xcodegen generate`. After a regen that adds a new **app-target** file, also `rm -rf ~/Library/Developer/Xcode/DerivedData/DrawBit-*` before building (test-target files need only the regen).
- `DrawBit.xcodeproj` is gitignored — never `git add` it.

**Reusable commands:**

```bash
REGEN='rm -rf DrawBit.xcodeproj && xcodegen generate'
DERIVED='rm -rf ~/Library/Developer/Xcode/DerivedData/DrawBit-*'
TEST() { xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:"$1" 2>&1 | tail -25; }
```

---

### Task 1: KeyframeCodec (lossless zlib compress/decompress)

**Files:**
- Create: `DrawBit/Drawing/KeyframeCodec.swift`
- Test: `DrawBitTests/Drawing/KeyframeCodecTests.swift`

**Interfaces:**
- Produces: `enum KeyframeCodec { static func compress(_ rgba: Data) -> Data?; static func decompress(_ blob: Data) -> Data? }`

- [ ] **Step 1: Write the failing test**

```swift
// DrawBitTests/Drawing/KeyframeCodecTests.swift
import XCTest
@testable import DrawBit

final class KeyframeCodecTests: XCTestCase {
    func testRoundTripIsLossless() throws {
        // A canvas-shaped buffer with runs (compresses well) plus some variation.
        var rgba = Data(count: 32 * 32 * 4)
        for i in stride(from: 0, to: rgba.count, by: 4) where (i / 4) % 7 == 0 {
            rgba[i] = 200; rgba[i + 1] = 40; rgba[i + 2] = 90; rgba[i + 3] = 255
        }
        let blob = try XCTUnwrap(KeyframeCodec.compress(rgba))
        XCTAssertLessThan(blob.count, rgba.count, "pixel-art buffer should shrink")
        let back = try XCTUnwrap(KeyframeCodec.decompress(blob))
        XCTAssertEqual(back, rgba, "decompress must reproduce bytes exactly")
    }

    func testDecompressGarbageReturnsNil() {
        XCTAssertNil(KeyframeCodec.decompress(Data([0x01, 0x02, 0x03, 0x04])))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `TEST DrawBitTests/KeyframeCodecTests` (after `eval $REGEN`)
Expected: FAIL — compile error "cannot find 'KeyframeCodec' in scope".

- [ ] **Step 3: Write minimal implementation**

```swift
// DrawBit/Drawing/KeyframeCodec.swift
import Foundation

/// Lossless zlib (de)compression for a single composited RGBA canvas buffer.
/// Pixel art is mostly flat runs, so zlib shrinks a canvas to a few KB while
/// staying bit-exact — the time-lapse must never blur a pixel.
enum KeyframeCodec {
    static func compress(_ rgba: Data) -> Data? {
        try? (rgba as NSData).compressed(using: .zlib) as Data
    }

    static func decompress(_ blob: Data) -> Data? {
        try? (blob as NSData).decompressed(using: .zlib) as Data
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval $REGEN && eval $DERIVED && TEST DrawBitTests/KeyframeCodecTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/KeyframeCodec.swift DrawBitTests/Drawing/KeyframeCodecTests.swift
git commit -m "feat(timelapse): KeyframeCodec — lossless zlib canvas (de)compression"
```

---

### Task 2: Timelapse namespace (constants + even downsample)

**Files:**
- Create: `DrawBit/Drawing/Timelapse.swift`
- Test: `DrawBitTests/Drawing/TimelapseSampleTests.swift`

**Interfaces:**
- Produces: `enum Timelapse { static let maxStoredKeyframes = 240; static let targetClipFrames = 120; static let clipFPS = 24; static func sample<T>(_ items: [T], to target: Int) -> [T] }`

- [ ] **Step 1: Write the failing test**

```swift
// DrawBitTests/Drawing/TimelapseSampleTests.swift
import XCTest
@testable import DrawBit

final class TimelapseSampleTests: XCTestCase {
    func testPassthroughWhenAtOrUnderTarget() {
        let xs = Array(0..<50)
        XCTAssertEqual(Timelapse.sample(xs, to: 120), xs)
        XCTAssertEqual(Timelapse.sample(xs, to: 50), xs)
    }

    func testDownsamplePreservesEndsAndCount() {
        let xs = Array(0..<1000)
        let out = Timelapse.sample(xs, to: 120)
        XCTAssertEqual(out.count, 120)
        XCTAssertEqual(out.first, 0, "keeps first frame")
        XCTAssertEqual(out.last, 999, "keeps last frame")
        XCTAssertEqual(out, out.sorted(), "monotonic — order preserved")
    }

    func testEmptyAndTinyInputs() {
        XCTAssertEqual(Timelapse.sample([Int](), to: 120), [])
        XCTAssertEqual(Timelapse.sample([7], to: 120), [7])
        XCTAssertEqual(Timelapse.sample([1, 2], to: 1), [1], "target 1 → first only")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval $REGEN && TEST DrawBitTests/TimelapseSampleTests`
Expected: FAIL — "cannot find 'Timelapse' in scope".

- [ ] **Step 3: Write minimal implementation**

```swift
// DrawBit/Drawing/Timelapse.swift
import Foundation

/// Shared constants + the even-downsample used by both the export preview and
/// the MP4 encoder. Pure; no UI, no persistence.
enum Timelapse {
    /// Cap on stored keyframes. Even, so the "> cap" thin trigger lands on an odd
    /// count and `stride(by: 2)` keeps BOTH ends. See `TimelapseRecording`.
    static let maxStoredKeyframes = 240
    /// Max frames in an exported clip (before the held tail). 120 @ 24fps ≈ 5s.
    static let targetClipFrames = 120
    /// Playback rate of the exported clip.
    static let clipFPS = 24

    /// Evenly pick at most `target` items across `items`, always preserving the
    /// first and last. Passthrough when already small enough. Order preserved.
    static func sample<T>(_ items: [T], to target: Int) -> [T] {
        guard target >= 1 else { return [] }
        guard items.count > target else { return items }
        if target == 1 { return [items[0]] }
        let n = items.count
        return (0..<target).map { i in
            let idx = Int((Double(i) * Double(n - 1) / Double(target - 1)).rounded())
            return items[idx]
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval $REGEN && eval $DERIVED && TEST DrawBitTests/TimelapseSampleTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/Timelapse.swift DrawBitTests/Drawing/TimelapseSampleTests.swift
git commit -m "feat(timelapse): Timelapse constants + even downsample helper"
```

---

### Task 3: TimelapseRecording (append / dedupe / thin)

**Files:**
- Create: `DrawBit/Drawing/TimelapseRecording.swift`
- Test: `DrawBitTests/Drawing/TimelapseRecordingTests.swift`

**Interfaces:**
- Consumes: `Timelapse.maxStoredKeyframes`
- Produces: `struct TimelapseRecording { init(frames: [Data] = []); private(set) var frames: [Data]; mutating func append(_ blob: Data) }`

- [ ] **Step 1: Write the failing test**

```swift
// DrawBitTests/Drawing/TimelapseRecordingTests.swift
import XCTest
@testable import DrawBit

final class TimelapseRecordingTests: XCTestCase {
    private func blob(_ n: Int) -> Data { Data([UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF)]) }

    func testAppendAddsFrames() {
        var r = TimelapseRecording()
        r.append(blob(1)); r.append(blob(2))
        XCTAssertEqual(r.frames.count, 2)
    }

    func testConsecutiveDuplicateIsSkipped() {
        var r = TimelapseRecording()
        r.append(blob(1)); r.append(blob(1)); r.append(blob(2))
        XCTAssertEqual(r.frames.count, 2)
    }

    func testThinningCapsAndKeepsBothEnds() {
        var r = TimelapseRecording()
        // Append cap+1 DISTINCT frames → triggers exactly one halving.
        let count = Timelapse.maxStoredKeyframes + 1   // 241 (odd)
        for i in 0..<count { r.append(blob(i)) }
        XCTAssertLessThanOrEqual(r.frames.count, Timelapse.maxStoredKeyframes)
        XCTAssertEqual(r.frames.count, 121, "241 halved by stride-2 → 121")
        XCTAssertEqual(r.frames.first, blob(0), "keeps first")
        XCTAssertEqual(r.frames.last, blob(count - 1), "keeps last")
    }

    func testNeverExceedsCapOverLongRun() {
        var r = TimelapseRecording()
        for i in 0..<2000 { r.append(blob(i)) }
        XCTAssertLessThanOrEqual(r.frames.count, Timelapse.maxStoredKeyframes)
        XCTAssertEqual(r.frames.first, blob(0), "first survives every halving")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval $REGEN && TEST DrawBitTests/TimelapseRecordingTests`
Expected: FAIL — "cannot find 'TimelapseRecording' in scope".

- [ ] **Step 3: Write minimal implementation**

```swift
// DrawBit/Drawing/TimelapseRecording.swift
import Foundation

/// The growing list of compressed canvas keyframes for one drawing's time-lapse.
/// Value type; pure. Storage/compression happen outside (KeyframeCodec) — this
/// only owns the accumulation rules.
struct TimelapseRecording {
    private(set) var frames: [Data]

    init(frames: [Data] = []) { self.frames = frames }

    /// Append a compressed keyframe. Skips a no-op step (identical to the last
    /// frame). When the list exceeds the cap it halves by keeping every other
    /// frame — even coverage across the WHOLE session, both ends preserved
    /// (the cap is even so the trigger count is odd and `stride(by: 2)` includes
    /// the final index).
    mutating func append(_ blob: Data) {
        if blob == frames.last { return }
        frames.append(blob)
        if frames.count > Timelapse.maxStoredKeyframes {
            frames = stride(from: 0, to: frames.count, by: 2).map { frames[$0] }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval $REGEN && eval $DERIVED && TEST DrawBitTests/TimelapseRecordingTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/TimelapseRecording.swift DrawBitTests/Drawing/TimelapseRecordingTests.swift
git commit -m "feat(timelapse): TimelapseRecording — dedupe + even-halving thinning"
```

---

### Task 4: TimelapseCodec (storage container)

**Files:**
- Create: `DrawBit/Drawing/TimelapseCodec.swift`
- Test: `DrawBitTests/Drawing/TimelapseCodecTests.swift`

**Interfaces:**
- Produces: `enum TimelapseCodec { static func encode(_ frames: [Data]) -> Data; static func decode(_ data: Data) -> [Data]? }`

- [ ] **Step 1: Write the failing test**

```swift
// DrawBitTests/Drawing/TimelapseCodecTests.swift
import XCTest
@testable import DrawBit

final class TimelapseCodecTests: XCTestCase {
    func testRoundTrip() throws {
        let frames = [Data([1, 2, 3]), Data([]), Data([9, 9, 9, 9, 9])]
        let encoded = TimelapseCodec.encode(frames)
        let decoded = try XCTUnwrap(TimelapseCodec.decode(encoded))
        XCTAssertEqual(decoded, frames)
    }

    func testEmpty() throws {
        let decoded = try XCTUnwrap(TimelapseCodec.decode(TimelapseCodec.encode([])))
        XCTAssertEqual(decoded, [])
    }

    func testBadMagicReturnsNil() {
        XCTAssertNil(TimelapseCodec.decode(Data([0x00, 0x01, 0x02, 0x03, 0x04])))
    }

    func testTruncatedReturnsNil() {
        var d = TimelapseCodec.encode([Data([1, 2, 3, 4, 5])])
        d.removeLast(3)               // chop the payload
        XCTAssertNil(TimelapseCodec.decode(d))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval $REGEN && TEST DrawBitTests/TimelapseCodecTests`
Expected: FAIL — "cannot find 'TimelapseCodec' in scope".

- [ ] **Step 3: Write minimal implementation**

```swift
// DrawBit/Drawing/TimelapseCodec.swift
import Foundation

/// Binary container for a time-lapse recording (a list of already-zlib-compressed
/// keyframe blobs). Mirrors FrameCodec's style.
///
/// Layout (big-endian):
///   4 bytes  ASCII "DBTL" magic
///   1 byte   version (1)
///   4 bytes  frame count (UInt32)
///   per frame: 4 bytes blob length (UInt32) + N bytes blob
enum TimelapseCodec {
    static let magic: [UInt8] = Array("DBTL".utf8)
    static let version: UInt8 = 1

    static func encode(_ frames: [Data]) -> Data {
        var out = Data()
        out.append(contentsOf: magic)
        out.append(version)
        appendU32(UInt32(frames.count), to: &out)
        for f in frames {
            appendU32(UInt32(f.count), to: &out)
            out.append(f)
        }
        return out
    }

    static func decode(_ data: Data) -> [Data]? {
        var i = data.startIndex
        func remaining() -> Int { data.endIndex - i }
        guard remaining() >= magic.count + 1 + 4 else { return nil }
        guard Array(data[i..<i + magic.count]) == magic else { return nil }
        i += magic.count
        guard data[i] == version else { return nil }
        i += 1
        let count = readU32(data, &i)
        var frames: [Data] = []
        frames.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard remaining() >= 4 else { return nil }
            let len = Int(readU32(data, &i))
            guard remaining() >= len else { return nil }
            frames.append(data.subdata(in: i..<i + len))
            i += len
        }
        return frames
    }

    private static func appendU32(_ v: UInt32, to out: inout Data) {
        out.append(UInt8((v >> 24) & 0xFF)); out.append(UInt8((v >> 16) & 0xFF))
        out.append(UInt8((v >> 8) & 0xFF));  out.append(UInt8(v & 0xFF))
    }

    private static func readU32(_ data: Data, _ i: inout Data.Index) -> UInt32 {
        let v = (UInt32(data[i]) << 24) | (UInt32(data[i + 1]) << 16)
              | (UInt32(data[i + 2]) << 8) | UInt32(data[i + 3])
        i += 4
        return v
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval $REGEN && eval $DERIVED && TEST DrawBitTests/TimelapseCodecTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Drawing/TimelapseCodec.swift DrawBitTests/Drawing/TimelapseCodecTests.swift
git commit -m "feat(timelapse): TimelapseCodec — DBTL storage container"
```

---

### Task 5: MP4Exporter (AVFoundation video)

**Files:**
- Create: `DrawBit/Rendering/MP4Exporter.swift`
- Test: `DrawBitTests/Rendering/MP4ExporterTests.swift`

**Interfaces:**
- Consumes: `CanvasSize`, `RGBA`, `CompositedBuffer`, `bufferToCGImage(_:)`.
- Produces: `enum MP4Exporter { static let defaultMatte: RGBA; static func export(keyframes: [Data], size: CanvasSize, scale: Int, fps: Int, matte: RGBA = defaultMatte, holdLastSeconds: Double = 1.2, to url: URL) throws }`

**Notes for the implementer:**
- Orientation: this codebase's verified rule is that a top-left `CGImage` drawn into a `CGContext(data:)` bitmap lands **top-down in memory** — the same convention `CVPixelBuffer` wants — so **do NOT add a vertical flip** (see the 2026-06-29 handoff gotcha). We compose each frame into an offscreen sRGB context exactly like `GIFExporter` (matte fill + nearest-neighbor scale + `makeImage()`), then blit that `CGImage` straight into the pixel buffer's BGRA context.
- H.264 needs even width/height → round output dims up to even; any 1px pad is matte.

- [ ] **Step 1: Write the failing test**

```swift
// DrawBitTests/Rendering/MP4ExporterTests.swift
import XCTest
import AVFoundation
@testable import DrawBit

final class MP4ExporterTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mp4test-\(UUID().uuidString).mp4")
    }

    /// A solid-color opaque canvas.
    private func solid(_ size: CanvasSize, r: UInt8, g: UInt8, b: UInt8) -> Data {
        var d = Data(count: size.byteCount)
        for i in stride(from: 0, to: d.count, by: 4) {
            d[i] = r; d[i + 1] = g; d[i + 2] = b; d[i + 3] = 255
        }
        return d
    }

    func testProducesValidMovieWithExpectedTrackAndDuration() throws {
        let size = CanvasSize(width: 16, height: 16)
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = (0..<5).map { _ in solid(size, r: 40, g: 160, b: 90) }

        try MP4Exporter.export(keyframes: frames, size: size, scale: 8, fps: 10,
                               holdLastSeconds: 1.0, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertGreaterThan((attrs[.size] as? Int) ?? 0, 0)

        let asset = AVURLAsset(url: url)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        XCTAssertEqual(track.naturalSize, CGSize(width: 128, height: 128)) // 16*8, even
        // 5 frames @10fps = 0.4s of motion + 1.0s hold ≈ 1.4s.
        XCTAssertEqual(asset.duration.seconds, 1.4, accuracy: 0.25)
    }

    func testTransparentAreasBecomeMatte() throws {
        let size = CanvasSize(width: 8, height: 8)
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // Fully transparent keyframe → whole frame should be the matte.
        let clear = Data(count: size.byteCount)

        try MP4Exporter.export(keyframes: [clear, clear], size: size, scale: 16, fps: 4,
                               holdLastSeconds: 0, to: url)

        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .positiveInfinity
        let cg = try gen.copyCGImage(at: .zero, actualTime: nil)
        let px = Self.centerPixel(cg)
        // H.264 is lossy — allow slack. Matte is (26,26,26).
        XCTAssertEqual(Int(px.r), 26, accuracy: 16)
        XCTAssertEqual(Int(px.g), 26, accuracy: 16)
        XCTAssertEqual(Int(px.b), 26, accuracy: 16)
    }

    func testGuards() {
        let size = CanvasSize(width: 8, height: 8)
        let url = tempURL()
        XCTAssertThrowsError(try MP4Exporter.export(keyframes: [], size: size, scale: 1, fps: 1, to: url))
        XCTAssertThrowsError(try MP4Exporter.export(keyframes: [Data(count: size.byteCount)], size: size, scale: 0, fps: 1, to: url))
        XCTAssertThrowsError(try MP4Exporter.export(keyframes: [Data(count: size.byteCount)], size: size, scale: 1, fps: 0, to: url))
    }

    private static func centerPixel(_ cg: CGImage) -> (r: UInt8, g: UInt8, b: UInt8) {
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let o = ((h / 2) * w + (w / 2)) * 4
        return (buf[o], buf[o + 1], buf[o + 2])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval $REGEN && TEST DrawBitTests/MP4ExporterTests`
Expected: FAIL — "cannot find 'MP4Exporter' in scope".

- [ ] **Step 3: Write minimal implementation**

```swift
// DrawBit/Rendering/MP4Exporter.swift
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// Encodes a list of composited RGBA keyframes into an H.264 `.mp4` time-lapse.
///
/// sRGB + nearest-neighbor throughout (matches every other export path). MP4 has
/// no alpha, so transparent pixels are painted onto an opaque `matte`. The final
/// frame is held for `holdLastSeconds` so the finished art lingers.
enum MP4Exporter {
    static let defaultMatte = RGBA(r: 26, g: 26, b: 26, a: 255)

    enum ExportError: Error { case badInput, setup, writeFailed }

    static func export(keyframes: [Data], size: CanvasSize, scale: Int, fps: Int,
                       matte: RGBA = defaultMatte, holdLastSeconds: Double = 1.2,
                       to url: URL) throws {
        guard !keyframes.isEmpty, scale >= 1, fps >= 1 else { throw ExportError.badInput }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw ExportError.setup }

        let artW = size.width * scale
        let artH = size.height * scale
        let outW = artW + (artW % 2)     // H.264 needs even dims
        let outH = artH + (artH % 2)

        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw ExportError.setup
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outW,
            AVVideoHeightKey: outH,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outW,
                kCVPixelBufferHeightKey as String: outH,
            ])
        guard writer.canAdd(input) else { throw ExportError.setup }
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.setup }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw ExportError.setup }

        // Presentation order: every keyframe once, then the last held.
        let hold = max(0, Int((holdLastSeconds * Double(fps)).rounded()))
        var order = Array(keyframes.indices)
        if let last = order.last { order.append(contentsOf: Array(repeating: last, count: hold)) }

        let timescale: CMTimeScale = 600
        for (present, kf) in order.enumerated() {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }

            guard let frameImage = composeFrame(rgba: keyframes[kf], size: size,
                                                artW: artW, artH: artH, outW: outW, outH: outH,
                                                matte: matte, colorSpace: colorSpace),
                  let pb = pixelBuffer(from: frameImage, outW: outW, outH: outH,
                                       pool: pool, colorSpace: colorSpace)
            else { throw ExportError.writeFailed }

            let t = CMTime(value: CMTimeValue(Double(present) / Double(fps) * Double(timescale)),
                           timescale: timescale)
            guard adaptor.append(pb, withPresentationTime: t) else { throw ExportError.writeFailed }
        }
        input.markAsFinished()
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()
        guard writer.status == .completed else { throw ExportError.writeFailed }
    }

    /// Matte-filled, nearest-neighbor-scaled frame as a CGImage (GIFExporter style).
    private static func composeFrame(rgba: Data, size: CanvasSize,
                                     artW: Int, artH: Int, outW: Int, outH: Int,
                                     matte: RGBA, colorSpace: CGColorSpace) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: outW, height: outH,
                                  bitsPerComponent: 8, bytesPerRow: outW * 4, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.setFillColor(red: CGFloat(matte.r) / 255, green: CGFloat(matte.g) / 255,
                         blue: CGFloat(matte.b) / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
        if let cg = bufferToCGImage(CompositedBuffer(data: rgba, size: size)) {
            ctx.draw(cg, in: CGRect(x: 0, y: outH - artH, width: artW, height: artH))
        }
        return ctx.makeImage()
    }

    /// Blit a CGImage into a pooled BGRA pixel buffer (no flip — CGContext(data:)
    /// is top-down here, matching CVPixelBuffer).
    private static func pixelBuffer(from image: CGImage, outW: Int, outH: Int,
                                    pool: CVPixelBufferPool, colorSpace: CGColorSpace) -> CVPixelBuffer? {
        var pbOut: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut) == kCVReturnSuccess,
              let pb = pbOut else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb),
              let ctx = CGContext(data: base, width: outW, height: outH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                            | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        return pb
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval $REGEN && eval $DERIVED && TEST DrawBitTests/MP4ExporterTests`
Expected: PASS (3 tests). If `testTransparentAreasBecomeMatte` is off by orientation, the failure will show art/matte in the wrong half — but the compose path mirrors GIFExporter, which is verified-correct, so it should pass. If the matte tolerance is tight for your encoder, widen to ±20 (H.264 quantization), not a code change.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Rendering/MP4Exporter.swift DrawBitTests/Rendering/MP4ExporterTests.swift
git commit -m "feat(timelapse): MP4Exporter — H.264 clip with matte + held tail"
```

---

### Task 6: EditorState capture hooks

**Files:**
- Modify: `DrawBit/State/EditorState.swift` (add recorder + hooks into the three commit methods)
- Test: `DrawBitTests/State/EditorStateTimelapseTests.swift`

**Interfaces:**
- Consumes: `TimelapseRecording`, `KeyframeCodec`, `TimelapseCodec`, `Compositor`.
- Produces on `EditorState`: `var timelapseFrameCount: Int`, `func recordKeyframe()`, `func loadTimelapse(_ blob: Data?)`, `func encodedTimelapse() -> Data?`.

- [ ] **Step 1: Write the failing test**

```swift
// DrawBitTests/State/EditorStateTimelapseTests.swift
import XCTest
@testable import DrawBit

@MainActor
final class EditorStateTimelapseTests: XCTestCase {
    private func makeState() -> EditorState {
        let size = CanvasSize(width: 16, height: 16)
        let layer = Layer(name: "L1", pixels: Data(count: size.byteCount))
        let frame = Frame(layers: [layer], activeLayerID: layer.id)
        return EditorState(pieceID: UUID(), size: size, frames: [frame],
                           activeFrameIndex: 0, fps: 12)
    }

    private func drawOneDot(_ s: EditorState, at p: (Int, Int)) {
        s.beginStrokeSnapshot()
        s.stampBrush(.pencil, at: p)
        s.commitStroke()
    }

    func testCommitStrokeRecordsAKeyframe() {
        let s = makeState()
        s.color = RGBA(r: 255, g: 0, b: 0, a: 255)
        XCTAssertEqual(s.timelapseFrameCount, 0)
        drawOneDot(s, at: (1, 1))
        XCTAssertEqual(s.timelapseFrameCount, 1)
        drawOneDot(s, at: (2, 2))
        XCTAssertEqual(s.timelapseFrameCount, 2)
    }

    func testNoOpCommitIsDeduped() {
        let s = makeState()
        s.color = RGBA(r: 255, g: 0, b: 0, a: 255)
        drawOneDot(s, at: (1, 1))
        // Commit again with no pixel change (snapshot then immediately commit).
        s.beginStrokeSnapshot(); s.commitStroke()
        XCTAssertEqual(s.timelapseFrameCount, 1, "identical canvas is not re-recorded")
    }

    func testUndoDoesNotRecordButFinalizeDoes() {
        let s = makeState()
        s.color = RGBA(r: 255, g: 0, b: 0, a: 255)
        drawOneDot(s, at: (1, 1))
        drawOneDot(s, at: (2, 2))
        XCTAssertEqual(s.timelapseFrameCount, 2)
        s.undo()
        XCTAssertEqual(s.timelapseFrameCount, 2, "undo alone does not record")
        s.recordKeyframe()   // finalize on close/share
        XCTAssertEqual(s.timelapseFrameCount, 3, "post-undo canvas differs → recorded")
    }

    func testEncodeLoadRoundTrip() {
        let s = makeState()
        s.color = RGBA(r: 9, g: 9, b: 9, a: 255)
        drawOneDot(s, at: (3, 3))
        let blob = s.encodedTimelapse()
        XCTAssertNotNil(blob)

        let s2 = makeState()
        s2.loadTimelapse(blob)
        XCTAssertEqual(s2.timelapseFrameCount, 1)
        XCTAssertNil(makeState().encodedTimelapse(), "empty recording encodes to nil")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval $REGEN && TEST DrawBitTests/EditorStateTimelapseTests`
Expected: FAIL — "value of type 'EditorState' has no member 'timelapseFrameCount'".

- [ ] **Step 3: Write minimal implementation**

In `DrawBit/State/EditorState.swift`, add the stored recorder near the other undo state (after `private var pixelPerfectBuffer = PixelPerfectStroke()`):

```swift
    /// Session recorder for the time-lapse. Not observed — no view reads it in a
    /// body, so mutating it per stroke triggers no re-render. Persisted separately.
    @ObservationIgnored private var timelapse = TimelapseRecording()

    var timelapseFrameCount: Int { timelapse.frames.count }
```

Add these methods (e.g. in the "Drawing-stroke undo" MARK region):

```swift
    /// Snapshot the composited canvas (layers only — never the reference photo) and
    /// append it to the recording. Deduped/thinned inside `TimelapseRecording`.
    /// Called at every commit point, and again on close/share to finalize.
    func recordKeyframe() {
        let buffer = Compositor.composite(frame, size: size)
        if let blob = KeyframeCodec.compress(buffer.data) {
            timelapse.append(blob)
        }
    }

    /// Restore a persisted recording when a piece is reopened. nil / corrupt → empty.
    func loadTimelapse(_ blob: Data?) {
        let frames = blob.flatMap { TimelapseCodec.decode($0) } ?? []
        timelapse = TimelapseRecording(frames: frames)
    }

    /// Encoded recording for persistence, or nil when nothing has been recorded.
    func encodedTimelapse() -> Data? {
        timelapse.frames.isEmpty ? nil : TimelapseCodec.encode(timelapse.frames)
    }
```

Then call `recordKeyframe()` at the end of the three commit methods:

- In `commitStroke()` — add `recordKeyframe()` as the last line (after `pixelPerfectBuffer.reset()`).
- In `commitStructuralChange()` — add `recordKeyframe()` as the last line (after `preStructuralSnapshot = nil`).
- In `commitSequenceChange()` — add `recordKeyframe()` as the last line (after `preSequenceSnapshot = nil`).

- [ ] **Step 4: Run test to verify it passes**

Run: `eval $REGEN && eval $DERIVED && TEST DrawBitTests/EditorStateTimelapseTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the existing EditorState/undo tests to confirm no regression**

Run: `TEST DrawBitTests` (full unit suite; slower). Expected: PASS. (If time-limited, at least run any `*EditorState*`/`*Undo*`/`*Marquee*` classes.)

- [ ] **Step 6: Commit**

```bash
git add DrawBit/State/EditorState.swift DrawBitTests/State/EditorStateTimelapseTests.swift
git commit -m "feat(timelapse): record a keyframe at each EditorState commit point"
```

---

### Task 7: Piece column + repository + migration

**Files:**
- Modify: `DrawBit/Models/Piece.swift` (add `timelapseData`)
- Modify: `DrawBit/Persistence/PieceRepository.swift` (add `saveTimelapse`, copy in `duplicate`)
- Test: `DrawBitTests/Persistence/PieceRepositoryTimelapseTests.swift`
- Test: `DrawBitTests/Persistence/TimelapseUpgradeMigrationTests.swift`

**Interfaces:**
- Produces: `Piece.timelapseData: Data?`; `PieceRepository.saveTimelapse(piece:blob:) throws`.

- [ ] **Step 1: Write the failing tests**

```swift
// DrawBitTests/Persistence/PieceRepositoryTimelapseTests.swift
import XCTest
import SwiftData
@testable import DrawBit

@MainActor
final class PieceRepositoryTimelapseTests: XCTestCase {
    private func repo() throws -> (PieceRepository, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Piece.self, AppSettings.self, configurations: config)
        let ctx = ModelContext(container)
        return (PieceRepository(context: ctx), ctx)
    }

    func testSaveAndReloadTimelapse() throws {
        let (r, _) = try repo()
        let piece = try r.createPiece(size: CanvasSize(width: 16, height: 16))
        XCTAssertNil(piece.timelapseData)
        let blob = TimelapseCodec.encode([Data([1, 2, 3]), Data([4, 5, 6])])
        try r.saveTimelapse(piece: piece, blob: blob)
        XCTAssertEqual(piece.timelapseData, blob)
    }

    func testDuplicateCopiesTimelapse() throws {
        let (r, _) = try repo()
        let piece = try r.createPiece(size: CanvasSize(width: 16, height: 16))
        let blob = TimelapseCodec.encode([Data([9, 9])])
        try r.saveTimelapse(piece: piece, blob: blob)
        let copy = try r.duplicate(piece: piece)
        XCTAssertEqual(copy.timelapseData, blob)
    }
}
```

```swift
// DrawBitTests/Persistence/TimelapseUpgradeMigrationTests.swift
import XCTest
import SwiftData
@testable import DrawBit

/// A store written by the CURRENT shipped build (reference fields present, but NO
/// `timelapseData`) must open under the updated live model and gain the optional
/// column via inferred lightweight migration — no crash, existing data intact.
@MainActor
final class TimelapseUpgradeMigrationTests: XCTestCase {
    enum PreTimelapseSchema: VersionedSchema {
        static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
        static var models: [any PersistentModel.Type] { [Piece.self, AppSettings.self] }

        @Model final class Piece {
            @Attribute(.unique) var id: UUID
            var name: String?
            var sizeRaw: Int
            var heightRaw: Int = 0
            @Attribute(.externalStorage, originalName: "pixels") var frameData: Data
            var thumbnail: Data
            var createdAt: Date
            var updatedAt: Date
            @Attribute(.externalStorage) var referenceImageData: Data?
            var referenceOpacity: Double = 0.35
            init(id: UUID, sizeRaw: Int, frameData: Data, thumbnail: Data,
                 createdAt: Date, updatedAt: Date) {
                self.id = id; self.name = nil; self.sizeRaw = sizeRaw
                self.frameData = frameData; self.thumbnail = thumbnail
                self.createdAt = createdAt; self.updatedAt = updatedAt
            }
        }
        @Model final class AppSettings {
            var recentColors: [String]
            var lastUsedToolRaw: String
            init() { self.recentColors = []; self.lastUsedToolRaw = "pencil" }
        }
    }

    func testUpgradeFromPreTimelapseStoreDefaultsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drawbit-tl-\(UUID().uuidString).store")
        defer {
            let base = url.deletingLastPathComponent()
            for ext in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(
                    at: base.appendingPathComponent(url.lastPathComponent + ext))
            }
        }
        let pieceID = UUID()
        let frameBlob: Data = {
            let layer = Layer(name: "Layer 1", pixels: Data(count: CanvasSize.s16.byteCount))
            let frame = Frame(layers: [layer], activeLayerID: layer.id)
            return FrameCodec.encodeSequence(frames: [frame], activeFrameIndex: 0,
                                             fps: FrameCodec.defaultFPS)
        }()

        do {
            let schema = Schema(versionedSchema: PreTimelapseSchema.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = ModelContext(container)
            let p = PreTimelapseSchema.Piece(id: pieceID, sizeRaw: 16, frameData: frameBlob,
                                             thumbnail: Data(), createdAt: Date(), updatedAt: Date())
            ctx.insert(p)
            try ctx.save()
        }

        // Reopen under the CURRENT production schema + plan.
        let schema = Schema(versionedSchema: DrawBitSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema,
                                           migrationPlan: DrawBitMigrationPlan.self,
                                           configurations: [config])
        let ctx = ModelContext(container)
        let pieces = try ctx.fetch(FetchDescriptor<Piece>())
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces.first?.id, pieceID)
        XCTAssertNil(pieces.first?.timelapseData, "new optional column defaults nil")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `eval $REGEN && TEST DrawBitTests/PieceRepositoryTimelapseTests`
Expected: FAIL — "value of type 'Piece' has no member 'timelapseData'".

- [ ] **Step 3: Write minimal implementation**

In `DrawBit/Models/Piece.swift`, after the reference fields (`referenceOpacity`), add:

```swift
    /// Optional saved time-lapse recording (a `TimelapseCodec` blob: a list of
    /// zlib-compressed composited keyframes). Display/export-only; never part of
    /// `frameData`. External storage keeps the row light. Additive optional column
    /// → inferred lightweight migration (no new schema; see `DrawBitSchema.swift`).
    @Attribute(.externalStorage) var timelapseData: Data?
```

In `DrawBit/Persistence/PieceRepository.swift`, add after `saveReference`:

```swift
    // MARK: - Time-lapse

    /// Persists the time-lapse recording blob (nil clears it). The blob is produced
    /// by `EditorState.encodedTimelapse()`.
    func saveTimelapse(piece: Piece, blob: Data?) throws {
        piece.timelapseData = blob
        piece.updatedAt = Date()
        try context.save()
    }
```

In `duplicate(piece:)`, alongside `copy.referenceImageData = piece.referenceImageData`, add:

```swift
        copy.timelapseData = piece.timelapseData
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `eval $REGEN && eval $DERIVED && TEST DrawBitTests/PieceRepositoryTimelapseTests && TEST DrawBitTests/TimelapseUpgradeMigrationTests`
Expected: PASS.

- [ ] **Step 5: Run the existing persistence/migration suites (guard the schema)**

Run: `TEST DrawBitTests/MigrationTests && TEST DrawBitTests/ReferenceUpgradeMigrationTests && TEST DrawBitTests/PieceRepositoryTests`
Expected: PASS — proves the additive column didn't break the store.

- [ ] **Step 6: Commit**

```bash
git add DrawBit/Models/Piece.swift DrawBit/Persistence/PieceRepository.swift DrawBitTests/Persistence/PieceRepositoryTimelapseTests.swift DrawBitTests/Persistence/TimelapseUpgradeMigrationTests.swift
git commit -m "feat(timelapse): Piece.timelapseData column + repository save + migration test"
```

---

### Task 8: ExportSizeBudget `.film` case

**Files:**
- Modify: `DrawBit/Views/Editor/ExportSizeBudget.swift`
- Test: `DrawBitTests/Views/Editor/ExportSizeBudgetTests.swift` (add cases; create the file if it doesn't exist)

**Interfaces:**
- Produces: `ExportSizeBudget.Format.film`.

- [ ] **Step 1: Write the failing test**

Add to (or create) `DrawBitTests/Views/Editor/ExportSizeBudgetTests.swift`:

```swift
import XCTest
@testable import DrawBit

final class ExportSizeBudgetFilmTests: XCTestCase {
    func testFilmBoundedByContextEdgeNotByteCap() {
        // 120 frames that would blow the animated byte cap for GIF are fine for film
        // (the writer streams frame-by-frame — only the per-frame context is bounded).
        let over = ExportSizeBudget.isOverBudget(
            format: .film, canvasWidth: 256, canvasHeight: 256, scale: 8, frameCount: 120)
        XCTAssertFalse(over, "512px-ish film frames are within budget regardless of count")
    }

    func testFilmOverBudgetOnlyWhenEdgeTooLarge() {
        let over = ExportSizeBudget.isOverBudget(
            format: .film, canvasWidth: 256, canvasHeight: 256, scale: 40, frameCount: 10)
        XCTAssertTrue(over, "256*40 = 10240 > maxContextEdge → too big")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `eval $REGEN && TEST DrawBitTests/ExportSizeBudgetFilmTests`
Expected: FAIL — "type 'ExportSizeBudget.Format' has no member 'film'".

- [ ] **Step 3: Write minimal implementation**

In `DrawBit/Views/Editor/ExportSizeBudget.swift`:

- Extend the enum: `enum Format { case png, gif, apng, spriteSheet, film }`
- In `outputDimensions`, add `.film` to the single-cell branch:

```swift
        case .png, .gif, .apng, .film:
            return (cellW, cellH)
```

- In `isOverBudget`, add `.film` to the "no accumulation cap" branch:

```swift
        case .png, .spriteSheet, .film:
            return false
```

- [ ] **Step 4: Run test to verify it passes**

Run: `eval $REGEN && eval $DERIVED && TEST DrawBitTests/ExportSizeBudgetFilmTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Views/Editor/ExportSizeBudget.swift DrawBitTests/Views/Editor/ExportSizeBudgetTests.swift
git commit -m "feat(timelapse): ExportSizeBudget .film — bounded by context edge only"
```

---

### Task 9: EditorView wiring (load on open, save on close & share)

**Files:**
- Modify: `DrawBit/Views/Editor/EditorView.swift`

**Interfaces:**
- Consumes: `EditorState.loadTimelapse`, `recordKeyframe`, `encodedTimelapse`; `PieceRepository.saveTimelapse`.

This task is UI wiring — its gate is "the full unit suite still passes and the app builds", since the view isn't unit-tested directly.

- [ ] **Step 1: Load the recording on open**

In `EditorView.init`, right after `editorState.setReference(imageData: piece.referenceImageData)`, add:

```swift
        editorState.loadTimelapse(piece.timelapseData)
```

- [ ] **Step 2: Add a save helper**

Next to `saveReference()` (around line 575), add:

```swift
    private func saveTimelapse() {
        guard !loadFailed else { return }
        state.recordKeyframe()          // finalize: ensure the clip ends on the real canvas
        let repo = PieceRepository(context: modelContext)
        try? repo.saveTimelapse(piece: piece, blob: state.encodedTimelapse())
    }
```

- [ ] **Step 3: Persist on close**

In `.onDisappear` (after `saveCurrentFrame()` near line 238), add:

```swift
            saveTimelapse()
```

- [ ] **Step 4: Persist before opening the share sheet**

Find where the share sheet is opened (the button that sets `showingShareSheet = true`). Immediately before setting it true, call `saveTimelapse()` so the sheet (which re-reads `piece.timelapseData`) sees this session's steps. If the open is wrapped in `commitFloatingMarqueeAndPersist()`, add `saveTimelapse()` right after it. Concretely, locate the handler and make it:

```swift
        commitFloatingMarqueeAndPersist()   // if already present
        saveTimelapse()
        showingShareSheet = true
```

(If there is no `commitFloatingMarqueeAndPersist()` at that call site, just add `saveTimelapse()` immediately before `showingShareSheet = true`.)

- [ ] **Step 5: Build + full unit suite**

Run: `eval $REGEN && eval $DERIVED && xcodebuild -project DrawBit.xcodeproj -scheme DrawBit -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build 2>&1 | tail -5`
Then: `TEST DrawBitTests`
Expected: BUILD SUCCEEDED; unit tests PASS.

- [ ] **Step 6: Commit**

```bash
git add DrawBit/Views/Editor/EditorView.swift
git commit -m "feat(timelapse): EditorView loads on open, finalizes+saves on close & share"
```

---

### Task 10: Share sheet FILM tile + preview + MP4 export

**Files:**
- Modify: `DrawBit/Views/Editor/ShareSheet.swift`
- Modify: `DrawBit/Views/Editor/ExportPreview.swift`
- Test (UI, light): `DrawBitUITests/ShareSheetFilmUITests.swift`

**Interfaces:**
- Consumes: `TimelapseCodec.decode`, `KeyframeCodec.decompress`, `Timelapse.sample`, `Timelapse.clipFPS`, `MP4Exporter.export`.

- [ ] **Step 1: Add the `film` format case**

In `ShareSheet.ExportFormat`:

```swift
    enum ExportFormat: String, CaseIterable, Identifiable {
        case png
        case gif
        case apng
        case spriteSheet
        case film
        var id: String { rawValue }

        var label: String {
            switch self {
            case .png:         "PNG"
            case .gif:         "GIF"
            case .apng:        "APNG"
            case .spriteSheet: "Sprite"
            case .film:        "FILM"
            }
        }

        var fileExtension: String {
            switch self {
            case .png:         "png"
            case .gif:         "gif"
            case .apng:        "apng"
            case .spriteSheet: "png"
            case .film:        "mp4"
            }
        }

        var budgetKind: ExportSizeBudget.Format {
            switch self {
            case .png:         .png
            case .gif:         .gif
            case .apng:        .apng
            case .spriteSheet: .spriteSheet
            case .film:        .film
            }
        }
    }
```

- [ ] **Step 2: Load the recording + gate the tile**

Add state near the other `@State` vars in `ShareSheet`:

```swift
    /// Sampled, decompressed time-lapse keyframes (RGBA canvases). Empty = nothing to film.
    @State private var filmRGBA: [Data] = []
```

Extend `loadFramesIfNeeded()` (rename callers stay the same) to also load the film:

```swift
    private func loadFramesIfNeeded() {
        guard frames.isEmpty else { return }
        let repo = PieceRepository(context: modelContext)
        if let loaded = try? repo.loadFrames(piece: piece) {
            frames = loaded.frames
            activeIndex = loaded.activeFrameIndex
            fps = loaded.fps
        }
        let compressed = piece.timelapseData.flatMap { TimelapseCodec.decode($0) } ?? []
        filmRGBA = Timelapse.sample(compressed, to: Timelapse.targetClipFrames)
            .compactMap { KeyframeCodec.decompress($0) }
    }
```

Add a min-frames constant and a per-format disable check on the FORMAT tile. In `formatTile(format:)`, compute:

```swift
    private static let minFilmFrames = 2

    private func formatTile(format f: ExportFormat) -> some View {
        let isSelected = f == selectedFormat
        let disabled = f == .film && filmRGBA.count < Self.minFilmFrames
        return Button {
            selectedFormat = f
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isSelected ? 0.10 : 0.04))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.15),
                            lineWidth: isSelected ? 2 : 0.5)
                VStack(spacing: 2) {
                    Text(f.label)
                        .font(.pixel(14))
                        .foregroundStyle(.white.opacity(disabled ? 0.3 : 1))
                        .lineLimit(1)
                    if disabled {
                        Text("KEEP DRAWING")
                            .font(.pixel(7))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("ShareSheet.format.\(f.rawValue)")
    }
```

Change the FORMAT grid to 5 columns:

```swift
            section(title: "FORMAT", columns: 5) {
                ForEach(ExportFormat.allCases) { formatTile(format: $0) }
            }
```

- [ ] **Step 3: Feed the preview the film frames**

Wrap each film RGBA canvas as a one-layer `Frame` and pass film frames + `clipFPS` to `ExportPreview` when `.film` is selected. Add a computed helper and update the `ExportPreview(...)` call:

```swift
    /// Film keyframes wrapped as single-layer Frames so ExportPreview renders them
    /// with the existing pipeline.
    private var filmFrames: [Frame] {
        filmRGBA.map { rgba in
            let l = Layer(name: "", pixels: rgba)
            return Frame(layers: [l], activeLayerID: l.id)
        }
    }

    private var previewFrames: [Frame] { selectedFormat == .film ? filmFrames : frames }
    private var previewFPS: Int { selectedFormat == .film ? Timelapse.clipFPS : fps }
```

Update the `ExportPreview(...)` usage in `body`:

```swift
            ExportPreview(
                frames: previewFrames,
                activeIndex: selectedFormat == .film ? 0 : activeIndex,
                size: piece.size,
                fps: previewFPS,
                format: selectedFormat,
                outputWidth: outputWidth,
                outputHeight: outputHeight
            )
```

In `ExportPreview.swift`, treat `.film` as animated + give it a badge:

```swift
    private var isAnimated: Bool { format == .gif || format == .apng || format == .film }
```

```swift
        case .gif, .apng, .film:
            let secs = Double(max(1, frames.count)) / Double(safeFPS)
            return "\(format.label) · \(String(format: "%.1f", secs))s"
```

(The `.task(id: frames.count)` render already keys off the frame array, so switching to/from FILM re-renders the preview images.)

- [ ] **Step 4: Export branch**

In `share()`, add the `.film` case to the exporter switch inside the detached task:

```swift
            case .film:
                let ok = ((try? MP4Exporter.export(
                    keyframes: filmRGBA, size: size, scale: scale, fps: Timelapse.clipFPS,
                    to: url)) != nil)
                if !ok { return nil }
                return url
```

Because `MP4Exporter` writes straight to `url` (rather than returning `Data`), restructure the switch so `.film` returns the URL directly while the other cases keep the `data`→`write` path. Minimal shape:

```swift
        let writtenURL: URL? = await Task.detached(priority: .userInitiated) {
            switch format {
            case .film:
                do {
                    try MP4Exporter.export(keyframes: filmRGBA, size: size, scale: scale,
                                           fps: Timelapse.clipFPS, to: url)
                    return url
                } catch { return nil }
            default:
                let data: Data?
                switch format {
                case .png:         data = PNGExporter.export(frame: activeFrame, size: size, scale: scale)
                case .gif:         data = try? GIFExporter.export(frames: allFrames, size: size, scale: scale, fps: exportFPS)
                case .apng:        data = try? APNGExporter.export(frames: allFrames, size: size, scale: scale, fps: exportFPS)
                case .spriteSheet: data = SpriteSheetExporter.export(frames: allFrames, size: size, scale: scale)
                case .film:        data = nil   // handled above
                }
                guard let data else { return nil }
                do { try data.write(to: url); return url } catch { return nil }
            }
        }.value
```

Note: `filmRGBA` is a `@State` array captured by the detached closure — capture it into a local first (`let film = filmRGBA`) before the `Task.detached` to avoid capturing `self`, mirroring how `allFrames`/`size`/`scale` are already lifted into locals.

- [ ] **Step 5: Light UI test**

```swift
// DrawBitUITests/ShareSheetFilmUITests.swift
import XCTest

final class ShareSheetFilmUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFilmTileDisabledOnFreshDrawEnabledAfterDrawing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset"]
        app.launch()

        // Open a new draw and reach the editor. (Reuse whatever the other UI tests
        // do to create + open a piece; this project's GalleryView flow.)
        // Then open the share sheet and assert the FILM tile exists.
        // NOTE: keep this test to a presence/enabled check; do NOT drive the system
        // share popover (UIActivityViewController isn't automatable here).
        // See existing ShareSheet UI tests for the navigation helpers to reuse.
    }
}
```

Fill the body by mirroring the navigation in the existing share-sheet UI test(s) (search `DrawBitUITests` for `ShareSheet.format` or `EXPORT`). Assert: on a fresh draw, `app.buttons["ShareSheet.format.film"]` exists and `isEnabled == false`; after tapping the canvas once and reopening, it becomes enabled. If the existing UI-test navigation helpers don't make this cheap, keep only the "tile exists" assertion — the enable/disable logic is already covered by the format-tile code path and can be left to manual QA.

- [ ] **Step 6: Build, run unit + the new UI test**

Run: `eval $REGEN && eval $DERIVED && xcodebuild ... build`
Then: `TEST DrawBitTests` and `TEST DrawBitUITests/ShareSheetFilmUITests`
Expected: BUILD SUCCEEDED; unit PASS; UI test PASS (or reduced to a presence check).

- [ ] **Step 7: Commit**

```bash
git add DrawBit/Views/Editor/ShareSheet.swift DrawBit/Views/Editor/ExportPreview.swift DrawBitUITests/ShareSheetFilmUITests.swift
git commit -m "feat(timelapse): FILM export tile + animated preview + MP4 share"
```

---

### Task 11: Docs, full verification, handoff

**Files:**
- Modify: `CLAUDE.md`
- Create: `docs/superpowers/handoffs/2026-07-01-timelapse.md`
- Update: auto-memory (`project_timelapse.md` + `MEMORY.md` pointer)

- [ ] **Step 1: Update CLAUDE.md**

- In the "Pure-logic rule" bullet, note the `MP4Exporter` AVFoundation/CoreVideo/CoreMedia exception.
- Add a non-obvious-invariant bullet: the time-lapse recorder snapshots `Compositor.composite` (layers only, never the reference photo); it is persisted in the additive optional `Piece.timelapseData` column (lightweight migration, no V2 schema); exported as MP4 with an opaque matte (no alpha).

- [ ] **Step 2: Full unit + UI suite**

Run:
```bash
eval $REGEN && eval $DERIVED
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test 2>&1 | tail -30
```
Expected: all unit + UI tests PASS.

- [ ] **Step 3: Device compile-check (no signing)**

Run:
```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED (confirms AVFoundation links for device).

- [ ] **Step 4: Write the handoff + memory**

Handoff doc summarizing what shipped, the taste calls (matte, FILM label, pacing) and where their constants live, the known simplifications (multi-frame; force-quit loses un-persisted session growth), and the reversible-decision pointers. Add a `project_timelapse.md` memory + one-line `MEMORY.md` pointer.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/superpowers/handoffs/2026-07-01-timelapse.md
git commit -m "docs(timelapse): CLAUDE.md invariants + handoff"
```

---

## Self-Review

**Spec coverage:**
- Experience (export + preview) → Tasks 9, 10. ✓
- Capture per action + thin → Tasks 2, 3, 6. ✓
- Persistence with the drawing → Tasks 4, 7, 9. ✓
- MP4 format → Task 5, 10. ✓
- Matte / FILM label / pacing constants → Tasks 2 (constants), 5 (matte), 10 (label). ✓
- Dedupe / forward-only + finalize → Tasks 3, 6. ✓
- Migration (additive column) → Task 7. ✓
- Budget case → Task 8. ✓
- Too-few-steps disable → Task 10. ✓
- CLAUDE.md invariant updates → Task 11. ✓

**Placeholder scan:** UI-test body (Task 10 Step 5) intentionally defers to existing navigation helpers — flagged as reducible to a presence check, not a silent gap. All code steps carry real code.

**Type consistency:** `KeyframeCodec.compress/decompress`, `TimelapseCodec.encode/decode`, `TimelapseRecording(frames:)/.frames/.append`, `Timelapse.sample/.maxStoredKeyframes/.targetClipFrames/.clipFPS`, `MP4Exporter.export(keyframes:size:scale:fps:matte:holdLastSeconds:to:)`, `EditorState.recordKeyframe/loadTimelapse/encodedTimelapse/timelapseFrameCount`, `Piece.timelapseData`, `PieceRepository.saveTimelapse(piece:blob:)`, `ExportSizeBudget.Format.film`, `ShareSheet.ExportFormat.film` — consistent across tasks.
