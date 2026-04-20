# Bitme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a minimal, native iPadOS pixel-art creator with 4 canvas sizes, local SwiftData storage, Procreate-style free-transform canvas, and export-via-share-sheet.

**Architecture:** Pure-Swift drawing/rendering modules (no UI deps, fully TDD'd) sit under a thin SwiftUI view layer. SwiftData owns persistence, wrapped by a `PieceRepository`. An `@Observable EditorState` holds per-session editor state (tool, color, undo). Gestures route finger/Pencil input to either the draw path (Bresenham + coalesced touches) or a two-finger transform gesture (pan + pinch + rotate). All pixel rendering is nearest-neighbor, sRGB, AA-disabled, at device scale.

**Tech Stack:** Swift 5.10, SwiftUI, SwiftData, CoreGraphics, UIKit (for coalesced touches + Pencil availability), XCTest, Xcode 26 / iPadOS 17+, xcodegen for reproducible project generation.

**Spec:** [docs/superpowers/specs/2026-04-19-bitme-design.md](../specs/2026-04-19-bitme-design.md)

**Working dir:** `/Users/iliasrafailidis/bitme`

---

## Phase 0 — Project scaffold

### Task 0.1: Install xcodegen and write project spec

**Files:**
- Create: `project.yml`

- [ ] **Step 1: Install xcodegen**

Run: `brew install xcodegen`
Expected: exits 0; `xcodegen --version` prints a version.

- [ ] **Step 2: Write `project.yml`**

```yaml
name: Bitme
options:
  bundleIdPrefix: com.iamilias
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.10"
    DEVELOPMENT_TEAM: ""
    ENABLE_USER_SCRIPT_SANDBOXING: "NO"
targets:
  Bitme:
    type: application
    platform: iOS
    sources:
      - path: Bitme
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "2"
        PRODUCT_BUNDLE_IDENTIFIER: com.iamilias.bitme
        GENERATE_INFOPLIST_FILE: "YES"
        INFOPLIST_KEY_UILaunchScreen_Generation: "YES"
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: "YES"
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad: "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortraitUpsideDown"
        INFOPLIST_KEY_UIRequiresFullScreen: "NO"
        INFOPLIST_KEY_CFBundleDisplayName: Bitme
  BitmeTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: BitmeTests
    dependencies:
      - target: Bitme
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "2"
        GENERATE_INFOPLIST_FILE: "YES"
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Bitme.app/Bitme"
  BitmeUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: BitmeUITests
    dependencies:
      - target: Bitme
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "2"
        GENERATE_INFOPLIST_FILE: "YES"
        TEST_TARGET_NAME: Bitme
```

- [ ] **Step 3: Create the three source-root folders so xcodegen doesn't fail**

Run:
```bash
mkdir -p Bitme BitmeTests BitmeUITests
touch Bitme/.gitkeep BitmeTests/.gitkeep BitmeUITests/.gitkeep
```

- [ ] **Step 4: Commit**

```bash
git add project.yml Bitme/.gitkeep BitmeTests/.gitkeep BitmeUITests/.gitkeep
git commit -m "chore: add xcodegen project spec and source roots"
```

---

### Task 0.2: Generate the Xcode project and verify it builds

**Files:**
- Create: `Bitme/BitmeApp.swift`
- Create: `BitmeTests/SmokeTest.swift`
- Modify: `.gitignore` (add `Bitme.xcodeproj/`)

- [ ] **Step 1: Write a minimal `BitmeApp.swift`**

File: `Bitme/BitmeApp.swift`
```swift
import SwiftUI

@main
struct BitmeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Bitme")
                .font(.largeTitle)
        }
    }
}
```

Run: `rm Bitme/.gitkeep`

- [ ] **Step 2: Write a smoke unit test so the test target builds**

File: `BitmeTests/SmokeTest.swift`
```swift
import XCTest

final class SmokeTest: XCTestCase {
    func testSmoke() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

Run: `rm BitmeTests/.gitkeep`

- [ ] **Step 3: Add `Bitme.xcodeproj/` to `.gitignore`**

Modify the existing `# Xcode` block in `.gitignore` — add a new line:
```
Bitme.xcodeproj/
```

- [ ] **Step 4: Generate the project**

Run: `xcodegen generate`
Expected: prints `Loaded project:` and `Created project at Bitme.xcodeproj`.

- [ ] **Step 5: Build for iPad Pro (13-inch) simulator**

Run:
```bash
xcodebuild -project Bitme.xcodeproj -scheme Bitme -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -configuration Debug build | tail -20
```
Expected: `** BUILD SUCCEEDED **`. If the destination name is not found, list available simulators with `xcrun simctl list devices available | grep iPad` and pick an iPad simulator.

- [ ] **Step 6: Run unit tests to confirm the test target is wired**

Run:
```bash
xcodebuild -project Bitme.xcodeproj -scheme Bitme -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Bitme BitmeTests BitmeUITests .gitignore
git rm -f --ignore-unmatch Bitme/.gitkeep BitmeTests/.gitkeep BitmeUITests/.gitkeep 2>/dev/null || true
git commit -m "chore: scaffold SwiftUI app target and smoke test"
```

---

## Phase 1 — Data models

### Task 1.1: CanvasSize enum

**Files:**
- Create: `Bitme/Models/CanvasSize.swift`
- Create: `BitmeTests/Models/CanvasSizeTests.swift`

- [ ] **Step 1: Write the failing test**

File: `BitmeTests/Models/CanvasSizeTests.swift`
```swift
import XCTest
@testable import Bitme

final class CanvasSizeTests: XCTestCase {
    func testAllCasesExist() {
        XCTAssertEqual(CanvasSize.allCases, [.s16, .s32, .s64, .s128])
    }

    func testDimensionMatchesRaw() {
        XCTAssertEqual(CanvasSize.s16.dimension, 16)
        XCTAssertEqual(CanvasSize.s32.dimension, 32)
        XCTAssertEqual(CanvasSize.s64.dimension, 64)
        XCTAssertEqual(CanvasSize.s128.dimension, 128)
    }

    func testPixelCountMatchesDimensionSquared() {
        XCTAssertEqual(CanvasSize.s16.pixelCount, 256)
        XCTAssertEqual(CanvasSize.s128.pixelCount, 16_384)
    }

    func testByteCountIsPixelsTimesFour() {
        XCTAssertEqual(CanvasSize.s32.byteCount, 4 * 32 * 32)
    }
}
```

- [ ] **Step 2: Run — expect failure**

Run test: it fails because `CanvasSize` doesn't exist.

- [ ] **Step 3: Implement**

File: `Bitme/Models/CanvasSize.swift`
```swift
import Foundation

enum CanvasSize: Int, CaseIterable, Codable, Identifiable {
    case s16 = 16
    case s32 = 32
    case s64 = 64
    case s128 = 128

    var id: Int { rawValue }
    var dimension: Int { rawValue }
    var pixelCount: Int { dimension * dimension }
    var byteCount: Int { pixelCount * 4 }

    var displayName: String { "\(dimension) × \(dimension)" }
}
```

- [ ] **Step 4: Regenerate project, run tests — expect pass**

Run: `xcodegen generate && xcodebuild -project Bitme.xcodeproj -scheme Bitme -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Bitme/Models/CanvasSize.swift BitmeTests/Models/CanvasSizeTests.swift
git commit -m "feat(models): add CanvasSize enum with dimension/byte helpers"
```

---

### Task 1.2: Tool enum

**Files:**
- Create: `Bitme/Models/Tool.swift`
- Create: `BitmeTests/Models/ToolTests.swift`

- [ ] **Step 1: Write the failing test**

File: `BitmeTests/Models/ToolTests.swift`
```swift
import XCTest
@testable import Bitme

final class ToolTests: XCTestCase {
    func testAllCases() {
        XCTAssertEqual(Tool.allCases, [.pencil, .eraser, .fill, .eyedropper])
    }

    func testSFSymbolNames() {
        XCTAssertEqual(Tool.pencil.sfSymbol, "pencil")
        XCTAssertEqual(Tool.eraser.sfSymbol, "eraser")
        XCTAssertEqual(Tool.fill.sfSymbol, "drop.fill")
        XCTAssertEqual(Tool.eyedropper.sfSymbol, "eyedropper")
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Models/Tool.swift`
```swift
import Foundation

enum Tool: String, CaseIterable, Codable {
    case pencil
    case eraser
    case fill
    case eyedropper

    var sfSymbol: String {
        switch self {
        case .pencil: "pencil"
        case .eraser: "eraser"
        case .fill: "drop.fill"
        case .eyedropper: "eyedropper"
        }
    }

    var displayName: String {
        switch self {
        case .pencil: "Pencil"
        case .eraser: "Eraser"
        case .fill: "Fill"
        case .eyedropper: "Pick"
        }
    }
}
```

- [ ] **Step 4: Regenerate + test — expect pass.**

Run: `xcodegen generate && xcodebuild test -project Bitme.xcodeproj -scheme Bitme -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' | tail -5`

- [ ] **Step 5: Commit**

```bash
git add Bitme/Models/Tool.swift BitmeTests/Models/ToolTests.swift
git commit -m "feat(models): add Tool enum with SF Symbol mapping"
```

---

### Task 1.3: Piece SwiftData model

**Files:**
- Create: `Bitme/Models/Piece.swift`
- Create: `BitmeTests/Models/PieceTests.swift`

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Models/PieceTests.swift`
```swift
import XCTest
import SwiftData
@testable import Bitme

final class PieceTests: XCTestCase {
    func testNewPieceIsAllTransparent() {
        let piece = Piece(size: .s16)
        XCTAssertEqual(piece.pixels.count, CanvasSize.s16.byteCount)
        // All bytes zero means fully transparent RGBA.
        XCTAssertTrue(piece.pixels.allSatisfy { $0 == 0 })
    }

    func testDefaultNameFallsBackToGenerated() {
        let piece = Piece(size: .s32)
        piece.name = nil
        XCTAssertTrue(piece.effectiveName.contains("32 × 32"))
    }

    func testExplicitNameUsedWhenSet() {
        let piece = Piece(size: .s32)
        piece.name = "Hero sprite"
        XCTAssertEqual(piece.effectiveName, "Hero sprite")
    }

    func testSizeEnumPreserved() {
        let piece = Piece(size: .s128)
        XCTAssertEqual(piece.size, .s128)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Models/Piece.swift`
```swift
import Foundation
import SwiftData

@Model
final class Piece {
    @Attribute(.unique) var id: UUID
    var name: String?
    var sizeRaw: Int
    var pixels: Data
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
        self.pixels = Data(count: size.byteCount) // zeroed = transparent
        self.thumbnail = Data()
        self.createdAt = now
        self.updatedAt = now
    }
}
```

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Models/Piece.swift BitmeTests/Models/PieceTests.swift
git commit -m "feat(models): add Piece SwiftData model"
```

---

### Task 1.4: AppSettings singleton model

**Files:**
- Create: `Bitme/Models/AppSettings.swift`
- Create: `BitmeTests/Models/AppSettingsTests.swift`

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Models/AppSettingsTests.swift`
```swift
import XCTest
@testable import Bitme

final class AppSettingsTests: XCTestCase {
    func testPrependKeepsUnique() {
        let s = AppSettings()
        s.addRecentColor("#FF0000")
        s.addRecentColor("#00FF00")
        s.addRecentColor("#FF0000")  // should bubble to front, not dupe
        XCTAssertEqual(s.recentColors, ["#FF0000", "#00FF00"])
    }

    func testCapAt16() {
        let s = AppSettings()
        for i in 0..<20 {
            s.addRecentColor(String(format: "#%06X", i))
        }
        XCTAssertEqual(s.recentColors.count, 16)
        XCTAssertEqual(s.recentColors.first, "#000013")   // most recent (i=19)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Models/AppSettings.swift`
```swift
import Foundation
import SwiftData

@Model
final class AppSettings {
    var recentColors: [String]
    var lastUsedToolRaw: String

    var lastUsedTool: Tool {
        get { Tool(rawValue: lastUsedToolRaw) ?? .pencil }
        set { lastUsedToolRaw = newValue.rawValue }
    }

    init() {
        self.recentColors = []
        self.lastUsedToolRaw = Tool.pencil.rawValue
    }

    func addRecentColor(_ hex: String, limit: Int = 16) {
        var next = recentColors.filter { $0.caseInsensitiveCompare(hex) != .orderedSame }
        next.insert(hex, at: 0)
        if next.count > limit { next.removeLast(next.count - limit) }
        recentColors = next
    }
}
```

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Models/AppSettings.swift BitmeTests/Models/AppSettingsTests.swift
git commit -m "feat(models): add AppSettings singleton with recent colors"
```

---

## Phase 2 — Pure drawing logic (TDD)

### Task 2.1: PixelGrid wrapper

**Files:**
- Create: `Bitme/Drawing/PixelGrid.swift`
- Create: `BitmeTests/Drawing/PixelGridTests.swift`

`PixelGrid` is a value type that wraps `Data` + `CanvasSize` and exposes safe pixel read/write at integer coordinates. All higher-level tools operate on `PixelGrid`.

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Drawing/PixelGridTests.swift`
```swift
import XCTest
@testable import Bitme

final class PixelGridTests: XCTestCase {
    func testNewGridIsTransparent() {
        let grid = PixelGrid(size: .s16)
        XCTAssertEqual(grid.pixel(x: 0, y: 0), .transparent)
        XCTAssertEqual(grid.pixel(x: 15, y: 15), .transparent)
    }

    func testSetAndGetPixel() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 5, y: 7, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        XCTAssertEqual(grid.pixel(x: 5, y: 7), RGBA(r: 255, g: 0, b: 0, a: 255))
        XCTAssertEqual(grid.pixel(x: 5, y: 8), .transparent)
    }

    func testOutOfBoundsIsNoOp() {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: -1, y: 0, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        grid.setPixel(x: 16, y: 0, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        XCTAssertTrue(grid.data.allSatisfy { $0 == 0 })
    }

    func testContainsReturnsFalseOutside() {
        let grid = PixelGrid(size: .s16)
        XCTAssertFalse(grid.contains(x: -1, y: 0))
        XCTAssertFalse(grid.contains(x: 0, y: 16))
        XCTAssertTrue(grid.contains(x: 15, y: 15))
    }

    func testRoundTripData() {
        var grid = PixelGrid(size: .s32)
        grid.setPixel(x: 10, y: 20, color: RGBA(r: 1, g: 2, b: 3, a: 4))
        let grid2 = PixelGrid(data: grid.data, size: .s32)
        XCTAssertEqual(grid2.pixel(x: 10, y: 20), RGBA(r: 1, g: 2, b: 3, a: 4))
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Drawing/PixelGrid.swift`
```swift
import Foundation

struct RGBA: Equatable, Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    static let transparent = RGBA(r: 0, g: 0, b: 0, a: 0)
}

struct PixelGrid: Equatable {
    private(set) var data: Data
    let size: CanvasSize

    init(size: CanvasSize) {
        self.size = size
        self.data = Data(count: size.byteCount)
    }

    init(data: Data, size: CanvasSize) {
        precondition(data.count == size.byteCount, "data length must equal size.byteCount")
        self.data = data
        self.size = size
    }

    var dimension: Int { size.dimension }

    func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < dimension && y < dimension
    }

    func pixel(x: Int, y: Int) -> RGBA {
        guard contains(x: x, y: y) else { return .transparent }
        let i = (y * dimension + x) * 4
        return RGBA(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3])
    }

    mutating func setPixel(x: Int, y: Int, color: RGBA) {
        guard contains(x: x, y: y) else { return }
        let i = (y * dimension + x) * 4
        data[i] = color.r
        data[i + 1] = color.g
        data[i + 2] = color.b
        data[i + 3] = color.a
    }
}
```

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Drawing/PixelGrid.swift BitmeTests/Drawing/PixelGridTests.swift
git commit -m "feat(drawing): add PixelGrid value type with safe pixel r/w"
```

---

### Task 2.2: Bresenham line

**Files:**
- Create: `Bitme/Drawing/BresenhamLine.swift`
- Create: `BitmeTests/Drawing/BresenhamLineTests.swift`

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Drawing/BresenhamLineTests.swift`
```swift
import XCTest
@testable import Bitme

final class BresenhamLineTests: XCTestCase {
    func testSinglePoint() {
        XCTAssertEqual(bresenhamLine(from: (3, 4), to: (3, 4)), [(3, 4)])
    }

    func testHorizontal() {
        XCTAssertEqual(
            bresenhamLine(from: (0, 0), to: (3, 0)),
            [(0, 0), (1, 0), (2, 0), (3, 0)]
        )
    }

    func testVertical() {
        XCTAssertEqual(
            bresenhamLine(from: (0, 0), to: (0, 3)),
            [(0, 0), (0, 1), (0, 2), (0, 3)]
        )
    }

    func testDiagonal() {
        XCTAssertEqual(
            bresenhamLine(from: (0, 0), to: (3, 3)),
            [(0, 0), (1, 1), (2, 2), (3, 3)]
        )
    }

    func testReverseDirection() {
        XCTAssertEqual(
            bresenhamLine(from: (3, 3), to: (0, 0)),
            [(3, 3), (2, 2), (1, 1), (0, 0)]
        )
    }

    func testSteepLineHasNoGaps() {
        let pts = bresenhamLine(from: (0, 0), to: (2, 10))
        // Every y in 0...10 should appear exactly once.
        let ys = Set(pts.map(\.1))
        XCTAssertEqual(ys, Set(0...10))
    }
}

// helper for tuple equality
private func XCTAssertEqual(_ lhs: [(Int, Int)], _ rhs: [(Int, Int)], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
    for (a, b) in zip(lhs, rhs) {
        XCTAssertEqual(a.0, b.0, file: file, line: line)
        XCTAssertEqual(a.1, b.1, file: file, line: line)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Drawing/BresenhamLine.swift`
```swift
import Foundation

/// Classic Bresenham's line algorithm. Returns every integer point from `from` to `to` inclusive.
func bresenhamLine(from: (Int, Int), to: (Int, Int)) -> [(Int, Int)] {
    var (x0, y0) = from
    let (x1, y1) = to
    let dx = abs(x1 - x0)
    let dy = -abs(y1 - y0)
    let sx = x0 < x1 ? 1 : -1
    let sy = y0 < y1 ? 1 : -1
    var err = dx + dy
    var points: [(Int, Int)] = []
    while true {
        points.append((x0, y0))
        if x0 == x1 && y0 == y1 { break }
        let e2 = 2 * err
        if e2 >= dy { err += dy; x0 += sx }
        if e2 <= dx { err += dx; y0 += sy }
    }
    return points
}
```

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Drawing/BresenhamLine.swift BitmeTests/Drawing/BresenhamLineTests.swift
git commit -m "feat(drawing): add Bresenham line interpolation"
```

---

### Task 2.3: Pencil tool

**Files:**
- Create: `Bitme/Drawing/Pencil.swift`
- Create: `BitmeTests/Drawing/PencilTests.swift`

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Drawing/PencilTests.swift`
```swift
import XCTest
@testable import Bitme

final class PencilTests: XCTestCase {
    func testPaintSinglePixel() {
        var grid = PixelGrid(size: .s16)
        Pencil.paint(on: &grid, at: (5, 7), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        XCTAssertEqual(grid.pixel(x: 5, y: 7), RGBA(r: 255, g: 0, b: 0, a: 255))
    }

    func testPaintLineFillsEveryPixel() {
        var grid = PixelGrid(size: .s16)
        Pencil.paintLine(on: &grid, from: (0, 0), to: (3, 3), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        for i in 0...3 {
            XCTAssertEqual(grid.pixel(x: i, y: i), RGBA(r: 255, g: 0, b: 0, a: 255), "pixel (\(i),\(i))")
        }
    }

    func testPaintOutOfBoundsIsNoOp() {
        var grid = PixelGrid(size: .s16)
        Pencil.paint(on: &grid, at: (-1, 5), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        Pencil.paintLine(on: &grid, from: (-5, 0), to: (20, 0), color: RGBA(r: 0, g: 255, b: 0, a: 255))
        // in-bounds pixels along y=0 should be painted
        for x in 0..<16 {
            XCTAssertEqual(grid.pixel(x: x, y: 0), RGBA(r: 0, g: 255, b: 0, a: 255))
        }
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Drawing/Pencil.swift`
```swift
import Foundation

enum Pencil {
    static func paint(on grid: inout PixelGrid, at point: (Int, Int), color: RGBA) {
        grid.setPixel(x: point.0, y: point.1, color: color)
    }

    static func paintLine(on grid: inout PixelGrid, from: (Int, Int), to: (Int, Int), color: RGBA) {
        for p in bresenhamLine(from: from, to: to) {
            grid.setPixel(x: p.0, y: p.1, color: color)
        }
    }
}
```

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Drawing/Pencil.swift BitmeTests/Drawing/PencilTests.swift
git commit -m "feat(drawing): add Pencil tool with Bresenham line painting"
```

---

### Task 2.4: Eraser

**Files:**
- Create: `Bitme/Drawing/Eraser.swift`
- Create: `BitmeTests/Drawing/EraserTests.swift`

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Drawing/EraserTests.swift`
```swift
import XCTest
@testable import Bitme

final class EraserTests: XCTestCase {
    func testErasePointSetsAlphaZero() {
        var grid = PixelGrid(size: .s16)
        Pencil.paint(on: &grid, at: (5, 5), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        Eraser.erase(on: &grid, at: (5, 5))
        XCTAssertEqual(grid.pixel(x: 5, y: 5), .transparent)
    }

    func testEraseLineClearsEveryPixel() {
        var grid = PixelGrid(size: .s16)
        Pencil.paintLine(on: &grid, from: (0, 0), to: (4, 0), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        Eraser.eraseLine(on: &grid, from: (0, 0), to: (4, 0))
        for x in 0...4 {
            XCTAssertEqual(grid.pixel(x: x, y: 0), .transparent)
        }
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Drawing/Eraser.swift`
```swift
import Foundation

enum Eraser {
    static func erase(on grid: inout PixelGrid, at point: (Int, Int)) {
        grid.setPixel(x: point.0, y: point.1, color: .transparent)
    }

    static func eraseLine(on grid: inout PixelGrid, from: (Int, Int), to: (Int, Int)) {
        for p in bresenhamLine(from: from, to: to) {
            grid.setPixel(x: p.0, y: p.1, color: .transparent)
        }
    }
}
```

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Drawing/Eraser.swift BitmeTests/Drawing/EraserTests.swift
git commit -m "feat(drawing): add Eraser tool"
```

---

### Task 2.5: Flood fill

**Files:**
- Create: `Bitme/Drawing/Fill.swift`
- Create: `BitmeTests/Drawing/FillTests.swift`

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Drawing/FillTests.swift`
```swift
import XCTest
@testable import Bitme

final class FillTests: XCTestCase {
    func testFillEmptyCanvasFillsAll() {
        var grid = PixelGrid(size: .s16)
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        Fill.fill(on: &grid, at: (0, 0), with: red)
        for y in 0..<16 {
            for x in 0..<16 {
                XCTAssertEqual(grid.pixel(x: x, y: y), red, "(\(x),\(y))")
            }
        }
    }

    func testFillDoesNotCrossDifferentColor() {
        var grid = PixelGrid(size: .s16)
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
        // draw a vertical barrier at x=8
        for y in 0..<16 { grid.setPixel(x: 8, y: y, color: blue) }
        Fill.fill(on: &grid, at: (0, 0), with: red)
        // left side red, right side untouched (transparent)
        XCTAssertEqual(grid.pixel(x: 0, y: 0), red)
        XCTAssertEqual(grid.pixel(x: 7, y: 7), red)
        XCTAssertEqual(grid.pixel(x: 8, y: 7), blue)
        XCTAssertEqual(grid.pixel(x: 9, y: 7), .transparent)
    }

    func testFillSameColorIsNoOp() {
        var grid = PixelGrid(size: .s16)
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        for y in 0..<16 { for x in 0..<16 { grid.setPixel(x: x, y: y, color: red) } }
        Fill.fill(on: &grid, at: (3, 3), with: red)
        XCTAssertEqual(grid.pixel(x: 3, y: 3), red)  // unchanged, did not infinite-loop
    }

    func testFillStartingOutOfBoundsIsNoOp() {
        var grid = PixelGrid(size: .s16)
        Fill.fill(on: &grid, at: (-1, -1), with: RGBA(r: 1, g: 2, b: 3, a: 255))
        XCTAssertTrue(grid.data.allSatisfy { $0 == 0 })
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Drawing/Fill.swift`
```swift
import Foundation

enum Fill {
    /// 4-connected flood fill. Uses exact RGBA equality as the "same color" test, so transparent
    /// and opaque regions are distinct.
    static func fill(on grid: inout PixelGrid, at start: (Int, Int), with replacement: RGBA) {
        guard grid.contains(x: start.0, y: start.1) else { return }
        let target = grid.pixel(x: start.0, y: start.1)
        if target == replacement { return }
        let dim = grid.dimension
        var stack: [(Int, Int)] = [start]
        while let (x, y) = stack.popLast() {
            guard x >= 0, y >= 0, x < dim, y < dim else { continue }
            if grid.pixel(x: x, y: y) != target { continue }
            grid.setPixel(x: x, y: y, color: replacement)
            stack.append((x + 1, y))
            stack.append((x - 1, y))
            stack.append((x, y + 1))
            stack.append((x, y - 1))
        }
    }
}
```

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Drawing/Fill.swift BitmeTests/Drawing/FillTests.swift
git commit -m "feat(drawing): add 4-connected flood fill"
```

---

### Task 2.6: Eyedropper

**Files:**
- Create: `Bitme/Drawing/Eyedropper.swift`
- Create: `BitmeTests/Drawing/EyedropperTests.swift`

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Drawing/EyedropperTests.swift`
```swift
import XCTest
@testable import Bitme

final class EyedropperTests: XCTestCase {
    func testPicksOpaqueColor() {
        var grid = PixelGrid(size: .s16)
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        grid.setPixel(x: 4, y: 4, color: red)
        XCTAssertEqual(Eyedropper.pick(from: grid, at: (4, 4)), red)
    }

    func testTransparentSampleReturnsNil() {
        let grid = PixelGrid(size: .s16)
        XCTAssertNil(Eyedropper.pick(from: grid, at: (0, 0)))
    }

    func testOutOfBoundsReturnsNil() {
        let grid = PixelGrid(size: .s16)
        XCTAssertNil(Eyedropper.pick(from: grid, at: (-1, 0)))
        XCTAssertNil(Eyedropper.pick(from: grid, at: (0, 16)))
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Drawing/Eyedropper.swift`
```swift
import Foundation

enum Eyedropper {
    /// Returns the color at `point`, or nil if the sample is fully transparent or out of bounds.
    /// Per spec: picking transparent is a no-op at the caller, not a new color selection.
    static func pick(from grid: PixelGrid, at point: (Int, Int)) -> RGBA? {
        guard grid.contains(x: point.0, y: point.1) else { return nil }
        let color = grid.pixel(x: point.0, y: point.1)
        return color.a == 0 ? nil : color
    }
}
```

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Drawing/Eyedropper.swift BitmeTests/Drawing/EyedropperTests.swift
git commit -m "feat(drawing): add eyedropper (nil on transparent / OOB)"
```

---

## Phase 3 — Rendering

### Task 3.1: `pixelsToCGImage`

**Files:**
- Create: `Bitme/Rendering/PixelsToCGImage.swift`
- Create: `BitmeTests/Rendering/PixelsToCGImageTests.swift`

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Rendering/PixelsToCGImageTests.swift`
```swift
import XCTest
import CoreGraphics
@testable import Bitme

final class PixelsToCGImageTests: XCTestCase {
    func testImageDimensionsMatchCanvas() throws {
        var grid = PixelGrid(size: .s32)
        grid.setPixel(x: 0, y: 0, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        let image = try XCTUnwrap(pixelsToCGImage(grid))
        XCTAssertEqual(image.width, 32)
        XCTAssertEqual(image.height, 32)
    }

    func testImageIsSRGB() throws {
        let grid = PixelGrid(size: .s16)
        let image = try XCTUnwrap(pixelsToCGImage(grid))
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.sRGB)
    }

    func testRoundTripSinglePixel() throws {
        var grid = PixelGrid(size: .s16)
        grid.setPixel(x: 3, y: 4, color: RGBA(r: 200, g: 100, b: 50, a: 255))
        let image = try XCTUnwrap(pixelsToCGImage(grid))

        // sample via a 1x1 bitmap context
        var out = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(
            data: &out, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(image, in: CGRect(x: -3, y: -(16 - 1 - 4), width: 16, height: 16))
        // expect ~ (200,100,50,255) premultiplied-identity for alpha=255
        XCTAssertEqual(out[0], 200)
        XCTAssertEqual(out[1], 100)
        XCTAssertEqual(out[2], 50)
        XCTAssertEqual(out[3], 255)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Rendering/PixelsToCGImage.swift`
```swift
import CoreGraphics
import Foundation

/// Wraps a PixelGrid's raw RGBA bytes in a CGImage. Uses sRGB explicitly (NEVER deviceRGB) so
/// rendering and export are consistent across iPad models including P3 displays.
func pixelsToCGImage(_ grid: PixelGrid) -> CGImage? {
    let dim = grid.dimension
    let bytesPerRow = dim * 4

    guard let provider = CGDataProvider(data: grid.data as CFData) else { return nil }
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
        shouldInterpolate: false,   // nearest-neighbor flag baked into the image
        intent: .defaultIntent
    )
}
```

> **Note on premultiplied vs straight alpha:** `CGImage` on iOS requires premultiplied alpha for RGBA-order 32bpp. Our pixel data uses straight alpha (alpha = 255 for opaque, so premultiplied = straight). This is correct as long as we never use partial alpha — which the spec explicitly restricts (no pressure sensitivity, eraser sets alpha = 0 exactly). Tests lock this invariant in.

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Rendering/PixelsToCGImage.swift BitmeTests/Rendering/PixelsToCGImageTests.swift
git commit -m "feat(render): Data -> CGImage in sRGB, shouldInterpolate:false"
```

---

### Task 3.2: Thumbnail renderer

**Files:**
- Create: `Bitme/Rendering/ThumbnailRenderer.swift`
- Create: `BitmeTests/Rendering/ThumbnailRendererTests.swift`

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Rendering/ThumbnailRendererTests.swift`
```swift
import XCTest
import ImageIO
@testable import Bitme

final class ThumbnailRendererTests: XCTestCase {
    func testThumbnailIsPNGAtTargetSize() throws {
        var grid = PixelGrid(size: .s32)
        grid.setPixel(x: 0, y: 0, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        let data = try XCTUnwrap(ThumbnailRenderer.render(grid: grid, targetEdge: 128))

        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let type = CGImageSourceGetType(src) as String?
        XCTAssertEqual(type, "public.png")

        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(image.width, 128)
        XCTAssertEqual(image.height, 128)
    }

    func testThumbnailNonIntegerScaleStillProducesOutput() throws {
        let grid = PixelGrid(size: .s128)
        let data = try XCTUnwrap(ThumbnailRenderer.render(grid: grid, targetEdge: 120))
        XCTAssertGreaterThan(data.count, 0)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Rendering/ThumbnailRenderer.swift`
```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ThumbnailRenderer {
    static func render(grid: PixelGrid, targetEdge: Int) -> Data? {
        guard let source = pixelsToCGImage(grid) else { return nil }
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

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Rendering/ThumbnailRenderer.swift BitmeTests/Rendering/ThumbnailRendererTests.swift
git commit -m "feat(render): PNG thumbnail at target edge with NN and AA off"
```

---

### Task 3.3: PNG exporter

**Files:**
- Create: `Bitme/Rendering/PNGExporter.swift`
- Create: `BitmeTests/Rendering/PNGExporterTests.swift`

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Rendering/PNGExporterTests.swift`
```swift
import XCTest
import ImageIO
@testable import Bitme

final class PNGExporterTests: XCTestCase {
    func testExportAt1x() throws {
        let grid = PixelGrid(size: .s16)
        let data = try XCTUnwrap(PNGExporter.export(grid: grid, scale: 1))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(image.height, 16)
    }

    func testExportAt16xProducesIntegerScaledOutput() throws {
        let grid = PixelGrid(size: .s16)
        let data = try XCTUnwrap(PNGExporter.export(grid: grid, scale: 16))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(image.width, 256)
        XCTAssertEqual(image.height, 256)
    }

    func testExportRejectsNonIntegerOrZeroScale() {
        let grid = PixelGrid(size: .s16)
        XCTAssertNil(PNGExporter.export(grid: grid, scale: 0))
        XCTAssertNil(PNGExporter.export(grid: grid, scale: -1))
    }

    func testExportPreservesExactPixelsAtIntegerScale() throws {
        var grid = PixelGrid(size: .s16)
        let red = RGBA(r: 200, g: 50, b: 10, a: 255)
        grid.setPixel(x: 0, y: 0, color: red)
        let data = try XCTUnwrap(PNGExporter.export(grid: grid, scale: 4))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 64)
        // sample top-left 4x4 block should all be (200,50,10,255)
        var out = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(
            data: &out, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        // top-left of source maps to y near 64 in flipped space; inspect (2,62)
        ctx.draw(image, in: CGRect(x: -2, y: -62, width: 64, height: 64))
        XCTAssertEqual(out[0], 200)
        XCTAssertEqual(out[1], 50)
        XCTAssertEqual(out[2], 10)
        XCTAssertEqual(out[3], 255)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Rendering/PNGExporter.swift`
```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PNGExporter {
    static func export(grid: PixelGrid, scale: Int) -> Data? {
        guard scale >= 1 else { return nil }
        guard let source = pixelsToCGImage(grid) else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let outEdge = grid.dimension * scale
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

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Rendering/PNGExporter.swift BitmeTests/Rendering/PNGExporterTests.swift
git commit -m "feat(render): PNG exporter with integer scale, sRGB, NN, no AA"
```

---

## Phase 4 — Persistence

### Task 4.1: PieceRepository

**Files:**
- Create: `Bitme/Persistence/PieceRepository.swift`
- Create: `BitmeTests/Persistence/PieceRepositoryTests.swift`

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/Persistence/PieceRepositoryTests.swift`
```swift
import XCTest
import SwiftData
@testable import Bitme

final class PieceRepositoryTests: XCTestCase {
    var container: ModelContainer!
    var repo: PieceRepository!

    override func setUpWithError() throws {
        let schema = Schema([Piece.self, AppSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        repo = PieceRepository(context: ModelContext(container))
    }

    func testCreatePieceReturnsAllTransparent() throws {
        let piece = try repo.createPiece(size: .s32)
        XCTAssertEqual(piece.pixels.count, CanvasSize.s32.byteCount)
        XCTAssertTrue(piece.pixels.allSatisfy { $0 == 0 })
    }

    func testSaveUpdatesPixelsAndThumbnail() throws {
        let piece = try repo.createPiece(size: .s16)
        var grid = PixelGrid(data: piece.pixels, size: piece.size)
        Pencil.paint(on: &grid, at: (0, 0), color: RGBA(r: 255, g: 0, b: 0, a: 255))
        try repo.save(piece: piece, pixels: grid.data)
        XCTAssertEqual(piece.pixels, grid.data)
        XCTAssertGreaterThan(piece.thumbnail.count, 0)
    }

    func testDuplicateCopiesPixelsAndAppendsCopy() throws {
        let original = try repo.createPiece(size: .s16)
        original.name = "Hero"
        var grid = PixelGrid(data: original.pixels, size: .s16)
        Pencil.paint(on: &grid, at: (1, 1), color: RGBA(r: 9, g: 9, b: 9, a: 255))
        try repo.save(piece: original, pixels: grid.data)

        let dup = try repo.duplicate(piece: original)
        XCTAssertNotEqual(dup.id, original.id)
        XCTAssertEqual(dup.pixels, original.pixels)
        XCTAssertEqual(dup.name, "Hero copy")
    }

    func testDeleteRemovesPiece() throws {
        let piece = try repo.createPiece(size: .s16)
        try repo.delete(piece: piece)
        let remaining = try repo.allPieces()
        XCTAssertFalse(remaining.contains(where: { $0.id == piece.id }))
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Persistence/PieceRepository.swift`
```swift
import Foundation
import SwiftData

@MainActor
final class PieceRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func allPieces() throws -> [Piece] {
        var descriptor = FetchDescriptor<Piece>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor)
    }

    func createPiece(size: CanvasSize) throws -> Piece {
        let piece = Piece(size: size)
        context.insert(piece)
        try context.save()
        return piece
    }

    func save(piece: Piece, pixels: Data) throws {
        precondition(pixels.count == piece.size.byteCount)
        piece.pixels = pixels
        piece.thumbnail = ThumbnailRenderer.render(
            grid: PixelGrid(data: pixels, size: piece.size),
            targetEdge: 256
        ) ?? Data()
        piece.updatedAt = Date()
        try context.save()
    }

    func rename(piece: Piece, to name: String?) throws {
        piece.name = (name?.isEmpty ?? true) ? nil : name
        piece.updatedAt = Date()
        try context.save()
    }

    func duplicate(piece: Piece) throws -> Piece {
        let copy = Piece(size: piece.size)
        copy.pixels = piece.pixels
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

    func delete(piece: Piece) throws {
        context.delete(piece)
        try context.save()
    }

    func appSettings() throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try context.fetch(descriptor).first { return existing }
        let created = AppSettings()
        context.insert(created)
        try context.save()
        return created
    }
}
```

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Persistence/PieceRepository.swift BitmeTests/Persistence/PieceRepositoryTests.swift
git commit -m "feat(persistence): PieceRepository (CRUD + thumbnail regen on save)"
```

---

## Phase 5 — Editor session state

### Task 5.1: EditorState

**Files:**
- Create: `Bitme/State/EditorState.swift`
- Create: `BitmeTests/State/EditorStateTests.swift`

`EditorState` is the in-memory editor-session truth: current tool, current color, transform (translation/scale/rotation), undo/redo stacks, and the live `PixelGrid`. It does NOT touch SwiftData — that's the repository's job. The `EditorView` owns one `EditorState` for the life of the editing session.

- [ ] **Step 1: Write failing tests**

File: `BitmeTests/State/EditorStateTests.swift`
```swift
import XCTest
@testable import Bitme

final class EditorStateTests: XCTestCase {
    func testInitialStateFromPiece() {
        let piece = Piece(size: .s32)
        let state = EditorState(piece: piece)
        XCTAssertEqual(state.grid.size, .s32)
        XCTAssertEqual(state.tool, .pencil)
        XCTAssertEqual(state.color, RGBA(r: 0, g: 0, b: 0, a: 255))
        XCTAssertFalse(state.canUndo)
        XCTAssertFalse(state.canRedo)
    }

    func testCommitStrokePushesUndo() {
        let state = EditorState(piece: Piece(size: .s16))
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 1, y: 1, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        state.commitStroke()
        XCTAssertTrue(state.canUndo)
        XCTAssertFalse(state.canRedo)
    }

    func testUndoRestoresPrevious() {
        let state = EditorState(piece: Piece(size: .s16))
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 1, y: 1, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        state.commitStroke()
        state.undo()
        XCTAssertEqual(state.grid.pixel(x: 1, y: 1), .transparent)
        XCTAssertTrue(state.canRedo)
    }

    func testRedoReapplies() {
        let state = EditorState(piece: Piece(size: .s16))
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 1, y: 1, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        state.commitStroke()
        state.undo()
        state.redo()
        XCTAssertEqual(state.grid.pixel(x: 1, y: 1), RGBA(r: 255, g: 0, b: 0, a: 255))
    }

    func testNewStrokeAfterUndoClearsRedoStack() {
        let state = EditorState(piece: Piece(size: .s16))
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 1, y: 1, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        state.commitStroke()
        state.undo()
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 5, y: 5, color: RGBA(r: 0, g: 255, b: 0, a: 255))
        state.commitStroke()
        XCTAssertFalse(state.canRedo)
    }

    func testUndoStackCappedAt50() {
        let state = EditorState(piece: Piece(size: .s16))
        for i in 0..<60 {
            state.beginStrokeSnapshot()
            state.grid.setPixel(x: i % 16, y: 0, color: RGBA(r: 1, g: 1, b: 1, a: 255))
            state.commitStroke()
        }
        // pop 50 times and verify canUndo goes false at the cap
        for _ in 0..<50 { state.undo() }
        XCTAssertFalse(state.canUndo)
    }

    func testCancelInProgressStrokeDiscardsChanges() {
        let state = EditorState(piece: Piece(size: .s16))
        state.beginStrokeSnapshot()
        state.grid.setPixel(x: 1, y: 1, color: RGBA(r: 255, g: 0, b: 0, a: 255))
        state.cancelStroke()
        XCTAssertEqual(state.grid.pixel(x: 1, y: 1), .transparent)
        XCTAssertFalse(state.canUndo)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/State/EditorState.swift`
```swift
import Foundation
import Observation

@Observable
final class EditorState {
    let pieceID: UUID
    var grid: PixelGrid
    var tool: Tool = .pencil
    var color: RGBA = RGBA(r: 0, g: 0, b: 0, a: 255)

    // View transform (rotation in radians). Rotation is view-only, not persisted with the piece.
    var translation: CGSize = .zero
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0

    private var undoStack: [Data] = []
    private var redoStack: [Data] = []
    private var preStrokeSnapshot: Data?

    private let undoLimit = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(piece: Piece) {
        self.pieceID = piece.id
        self.grid = PixelGrid(data: piece.pixels, size: piece.size)
    }

    func beginStrokeSnapshot() {
        preStrokeSnapshot = grid.data
    }

    func commitStroke() {
        guard let snap = preStrokeSnapshot else { return }
        undoStack.append(snap)
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
        redoStack.removeAll()
        preStrokeSnapshot = nil
    }

    func cancelStroke() {
        if let snap = preStrokeSnapshot {
            grid = PixelGrid(data: snap, size: grid.size)
        }
        preStrokeSnapshot = nil
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(grid.data)
        grid = PixelGrid(data: previous, size: grid.size)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(grid.data)
        grid = PixelGrid(data: next, size: grid.size)
    }
}
```

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/State/EditorState.swift BitmeTests/State/EditorStateTests.swift
git commit -m "feat(state): EditorState with undo/redo (cap 50) and stroke cancel"
```

---

## Phase 6 — Gallery UI

### Task 6.1: App shell wired to SwiftData + empty GalleryView

**Files:**
- Modify: `Bitme/BitmeApp.swift`
- Create: `Bitme/Views/Gallery/GalleryView.swift`

- [ ] **Step 1: Wire the ModelContainer and root view**

File: `Bitme/BitmeApp.swift`
```swift
import SwiftUI
import SwiftData

@main
struct BitmeApp: App {
    var body: some Scene {
        WindowGroup {
            GalleryView()
        }
        .modelContainer(for: [Piece.self, AppSettings.self])
    }
}
```

- [ ] **Step 2: Create a minimal GalleryView**

File: `Bitme/Views/Gallery/GalleryView.swift`
```swift
import SwiftUI
import SwiftData

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Piece.updatedAt, order: .reverse) private var pieces: [Piece]
    @State private var showingNewSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if pieces.isEmpty {
                    ContentUnavailableView(
                        "No pieces yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Tap + New to create your first canvas.")
                    )
                } else {
                    Text("\(pieces.count) pieces")
                        .font(.title2)
                }
            }
            .navigationTitle("Pieces")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewSheet = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewSheet) {
                Text("New piece sheet (stub)")
                    .presentationDetents([.medium])
            }
        }
    }
}
```

- [ ] **Step 3: Regenerate + build + run smoke test**

```bash
xcodegen generate
xcodebuild test -project Bitme.xcodeproj -scheme Bitme -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' | tail -5
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Launch in simulator manually (optional sanity)**

Run:
```bash
xcrun simctl list devices available | grep -i "iPad Pro 13" | head -1
# note the device UUID, then:
# xcrun simctl boot <UUID>
# open -a Simulator
# xcodebuild -project Bitme.xcodeproj -scheme Bitme -destination 'platform=iOS Simulator,id=<UUID>' build
# xcrun simctl install <UUID> <path-to-.app>
# xcrun simctl launch <UUID> com.iamilias.bitme
```
Expected: app launches, shows "No pieces yet" empty state, + button in top-right opens the stub sheet.

- [ ] **Step 5: Commit**

```bash
git add Bitme/BitmeApp.swift Bitme/Views/Gallery/GalleryView.swift
git commit -m "feat(gallery): app shell with empty-state gallery and + button"
```

---

### Task 6.2: PieceThumbnailView and gallery grid

**Files:**
- Create: `Bitme/Views/Gallery/PieceThumbnailView.swift`
- Modify: `Bitme/Views/Gallery/GalleryView.swift`

- [ ] **Step 1: Create the thumbnail view**

File: `Bitme/Views/Gallery/PieceThumbnailView.swift`
```swift
import SwiftUI
import UIKit

struct PieceThumbnailView: View {
    let piece: Piece

    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(1, contentMode: .fit)
            } else {
                CheckerboardView()
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
    }

    private var thumbnailImage: UIImage? {
        guard !piece.thumbnail.isEmpty else { return nil }
        return UIImage(data: piece.thumbnail)
    }
}

struct CheckerboardView: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 8
            for y in stride(from: 0, to: size.height, by: tile) {
                for x in stride(from: 0, to: size.width, by: tile) {
                    let isDark = (Int(x / tile) + Int(y / tile)) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: tile, height: tile)),
                        with: .color(isDark ? Color(white: 0.88) : Color.white)
                    )
                }
            }
        }
    }
}
```

- [ ] **Step 2: Update GalleryView to render a grid**

File: `Bitme/Views/Gallery/GalleryView.swift`
```swift
import SwiftUI
import SwiftData

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Piece.updatedAt, order: .reverse) private var pieces: [Piece]
    @State private var showingNewSheet = false

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if pieces.isEmpty {
                    ContentUnavailableView(
                        "No pieces yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Tap + New to create your first canvas.")
                    )
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(pieces) { piece in
                            PieceThumbnailView(piece: piece)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Pieces")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewSheet = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewSheet) {
                Text("New piece sheet (stub)")
                    .presentationDetents([.medium])
            }
        }
    }
}
```

- [ ] **Step 3: Regenerate + build — expect success**

```bash
xcodegen generate
xcodebuild build -project Bitme.xcodeproj -scheme Bitme -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Bitme/Views/Gallery/PieceThumbnailView.swift Bitme/Views/Gallery/GalleryView.swift
git commit -m "feat(gallery): thumbnail view + adaptive grid layout"
```

---

### Task 6.3: NewPieceSheet (size picker that creates a piece)

**Files:**
- Create: `Bitme/Views/Gallery/NewPieceSheet.swift`
- Modify: `Bitme/Views/Gallery/GalleryView.swift`

- [ ] **Step 1: Create the size-picker sheet**

File: `Bitme/Views/Gallery/NewPieceSheet.swift`
```swift
import SwiftUI

struct NewPieceSheet: View {
    let onCreate: (CanvasSize) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(CanvasSize.allCases) { size in
                Button {
                    onCreate(size)
                    dismiss()
                } label: {
                    HStack {
                        Text(size.displayName)
                            .font(.title3)
                        Spacer()
                        Text("\(size.pixelCount) pixels")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("New piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Wire it from the gallery**

Update `Bitme/Views/Gallery/GalleryView.swift` — replace the `.sheet` contents and add a selection state for the created piece:

```swift
import SwiftUI
import SwiftData

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Piece.updatedAt, order: .reverse) private var pieces: [Piece]
    @State private var showingNewSheet = false
    @State private var selectedPiece: Piece?

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if pieces.isEmpty {
                    ContentUnavailableView(
                        "No pieces yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Tap + New to create your first canvas.")
                    )
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(pieces) { piece in
                            PieceThumbnailView(piece: piece)
                                .onTapGesture { selectedPiece = piece }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Pieces")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewSheet = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewSheet) {
                NewPieceSheet { size in
                    do {
                        let repo = PieceRepository(context: modelContext)
                        let piece = try repo.createPiece(size: size)
                        selectedPiece = piece
                    } catch {
                        // v1: swallow; surface via alert later if needed
                    }
                }
                .presentationDetents([.medium])
            }
            .navigationDestination(item: $selectedPiece) { piece in
                Text("Editor stub for \(piece.effectiveName)")
                    .navigationTitle(piece.effectiveName)
            }
        }
    }
}
```

> Note: `Piece` is `@Model`, and `@Model` classes conform to `Identifiable` and `Hashable` already for navigation.

- [ ] **Step 3: Regenerate + build**

- [ ] **Step 4: Commit**

```bash
git add Bitme/Views/Gallery/NewPieceSheet.swift Bitme/Views/Gallery/GalleryView.swift
git commit -m "feat(gallery): new-piece sheet + navigation stub to editor"
```

---

### Task 6.4: Long-press context menu (rename / duplicate / delete)

**Files:**
- Modify: `Bitme/Views/Gallery/GalleryView.swift`

- [ ] **Step 1: Add rename/duplicate/delete actions via context menu + confirmation**

Replace `ForEach(pieces) { piece in … }` body in `GalleryView`:

```swift
ForEach(pieces) { piece in
    PieceThumbnailView(piece: piece)
        .onTapGesture { selectedPiece = piece }
        .contextMenu {
            Button("Rename") { renameTarget = piece; renameDraft = piece.name ?? "" }
            Button("Duplicate") { duplicate(piece) }
            Divider()
            Button("Delete", role: .destructive) { deleteTarget = piece }
        }
}
```

Add to the struct:

```swift
@State private var renameTarget: Piece?
@State private var renameDraft: String = ""
@State private var deleteTarget: Piece?
```

Attach modifiers at the top of the `NavigationStack { … }` body's trailing edge (immediately before the closing `}` of the `NavigationStack` modifier chain):

```swift
.alert(
    "Rename piece",
    isPresented: Binding(
        get: { renameTarget != nil },
        set: { if !$0 { renameTarget = nil } }
    )
) {
    TextField("Name", text: $renameDraft)
    Button("Save") {
        if let target = renameTarget {
            let repo = PieceRepository(context: modelContext)
            try? repo.rename(piece: target, to: renameDraft)
        }
        renameTarget = nil
    }
    Button("Cancel", role: .cancel) { renameTarget = nil }
}
.confirmationDialog(
    "Delete this piece?",
    isPresented: Binding(
        get: { deleteTarget != nil },
        set: { if !$0 { deleteTarget = nil } }
    ),
    titleVisibility: .visible
) {
    Button("Delete", role: .destructive) {
        if let target = deleteTarget {
            let repo = PieceRepository(context: modelContext)
            try? repo.delete(piece: target)
        }
        deleteTarget = nil
    }
    Button("Cancel", role: .cancel) { deleteTarget = nil }
} message: {
    Text("This cannot be undone.")
}
```

Add the helper:

```swift
private func duplicate(_ piece: Piece) {
    let repo = PieceRepository(context: modelContext)
    _ = try? repo.duplicate(piece: piece)
}
```

- [ ] **Step 2: Regenerate + build**

- [ ] **Step 3: Manual sim check**

Create a piece, long-press it, confirm: Rename (opens alert with text field), Duplicate (new item appears at top), Delete (confirmation dialog, then removal).

- [ ] **Step 4: Commit**

```bash
git add Bitme/Views/Gallery/GalleryView.swift
git commit -m "feat(gallery): long-press rename / duplicate / delete"
```

---

## Phase 7 — Editor UI (canvas + gestures)

### Task 7.1: EditorView scaffold

**Files:**
- Create: `Bitme/Views/Editor/EditorView.swift`
- Modify: `Bitme/Views/Gallery/GalleryView.swift` (navigate to real editor)

- [ ] **Step 1: Create EditorView scaffold with top bar and placeholder canvas area**

File: `Bitme/Views/Editor/EditorView.swift`
```swift
import SwiftUI
import SwiftData

struct EditorView: View {
    let piece: Piece
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var state: EditorState

    init(piece: Piece) {
        self.piece = piece
        self._state = State(initialValue: EditorState(piece: piece))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ZStack {
                Color(white: 0.10)
                    .ignoresSafeArea(edges: [.leading, .trailing])
                Text("Canvas goes here")
                    .foregroundStyle(.white.opacity(0.4))
            }
            Divider()
            Rectangle()
                .fill(Color(white: 0.09))
                .frame(height: 88)
                .overlay(Text("Tools + colors").foregroundStyle(.white.opacity(0.5)))
        }
        .background(Color(white: 0.10).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label("Gallery", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            Spacer()
            Text(piece.size.displayName)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            HStack(spacing: 18) {
                Button {
                    state.undo()
                } label: { Image(systemName: "arrow.left") }
                    .disabled(!state.canUndo)
                Button {
                    state.redo()
                } label: { Image(systemName: "arrow.right") }
                    .disabled(!state.canRedo)
                Button("Share") {
                    // wired later
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
```

- [ ] **Step 2: Replace the navigation destination in GalleryView**

In `GalleryView`, change:
```swift
.navigationDestination(item: $selectedPiece) { piece in
    Text("Editor stub for \(piece.effectiveName)")
        .navigationTitle(piece.effectiveName)
}
```
to:
```swift
.navigationDestination(item: $selectedPiece) { piece in
    EditorView(piece: piece)
}
```

- [ ] **Step 3: Regenerate + build**

- [ ] **Step 4: Commit**

```bash
git add Bitme/Views/Editor/EditorView.swift Bitme/Views/Gallery/GalleryView.swift
git commit -m "feat(editor): scaffold with top bar (back / size / undo-redo / share)"
```

---

### Task 7.2: CanvasView — static NN render

**Files:**
- Create: `Bitme/Views/Editor/CanvasView.swift`
- Modify: `Bitme/Views/Editor/EditorView.swift`

`CanvasView` renders the `PixelGrid` as a crisp pixelated image at a given transform. No gestures yet.

- [ ] **Step 1: Create CanvasView**

File: `Bitme/Views/Editor/CanvasView.swift`
```swift
import SwiftUI
import UIKit

struct CanvasView: View {
    @Bindable var state: EditorState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                canvasImage
                    .frame(width: baseEdge(in: geo), height: baseEdge(in: geo))
                    .scaleEffect(state.scale)
                    .rotationEffect(.radians(state.rotation))
                    .offset(state.translation)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .clipped()
        }
    }

    private var canvasImage: some View {
        let dim = state.grid.dimension
        return Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            context.withCGContext { cgContext in
                cgContext.interpolationQuality = .none
                cgContext.setShouldAntialias(false)
                if let image = pixelsToCGImage(state.grid) {
                    cgContext.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(dim), height: CGFloat(dim)))
                }
            }
        }
        .frame(width: CGFloat(dim), height: CGFloat(dim))
        .drawingGroup(opaque: false, colorMode: .nonLinear)
    }

    private func baseEdge(in geo: GeometryProxy) -> CGFloat {
        // fit canvas square inside available area at scale 1
        let min = Swift.min(geo.size.width, geo.size.height) * 0.85
        let dim = CGFloat(state.grid.dimension)
        let perPixel = floor(min / dim)
        return max(perPixel, 1) * dim
    }
}
```

- [ ] **Step 2: Swap placeholder for real CanvasView in EditorView**

In `EditorView`, replace the `ZStack` that contains "Canvas goes here" with:

```swift
ZStack {
    Color(white: 0.10).ignoresSafeArea(edges: [.leading, .trailing])
    CanvasView(state: state)
}
```

- [ ] **Step 3: Regenerate + build**

Run `xcodebuild build` and verify success.

- [ ] **Step 4: Manual sim check**

Create a 16×16 piece → opens editor → see a dark background with a checkerboard-sized square in the middle. (Empty pixels render transparent, which on the dark surface is invisible; that's fine — next task adds the checkerboard behind the canvas bitmap.)

- [ ] **Step 5: Commit**

```bash
git add Bitme/Views/Editor/CanvasView.swift Bitme/Views/Editor/EditorView.swift
git commit -m "feat(editor): CanvasView with NN, no-AA, device-scale rendering"
```

---

### Task 7.3: Transparency checkerboard under the canvas

**Files:**
- Modify: `Bitme/Views/Editor/CanvasView.swift`

- [ ] **Step 1: Draw a checkerboard behind the pixel image inside the Canvas**

Replace the `canvasImage` computed property:

```swift
private var canvasImage: some View {
    let dim = state.grid.dimension
    return Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
        context.withCGContext { cgContext in
            cgContext.interpolationQuality = .none
            cgContext.setShouldAntialias(false)

            // checkerboard background (2 canvas-pixel tiles)
            let tile: CGFloat = 2
            for y in stride(from: 0.0, to: CGFloat(dim), by: tile) {
                for x in stride(from: 0.0, to: CGFloat(dim), by: tile) {
                    let isDark = (Int(x / tile) + Int(y / tile)) % 2 == 0
                    cgContext.setFillColor(UIColor(white: isDark ? 0.72 : 0.88, alpha: 1).cgColor)
                    cgContext.fill(CGRect(x: x, y: CGFloat(dim) - y - tile, width: tile, height: tile))
                }
            }

            if let image = pixelsToCGImage(state.grid) {
                cgContext.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(dim), height: CGFloat(dim)))
            }
        }
    }
    .frame(width: CGFloat(dim), height: CGFloat(dim))
    .drawingGroup(opaque: false, colorMode: .nonLinear)
}
```

- [ ] **Step 2: Build + sim check**

A checkerboard should now be visible inside the canvas area. Transparent pixels reveal the checker, opaque pixels cover it.

- [ ] **Step 3: Commit**

```bash
git add Bitme/Views/Editor/CanvasView.swift
git commit -m "feat(editor): checkerboard background behind canvas pixels"
```

---

### Task 7.4: PencilAvailability observer

**Files:**
- Create: `Bitme/Gestures/PencilAvailability.swift`
- Create: `BitmeTests/Gestures/PencilAvailabilityTests.swift`

Observes whether an Apple Pencil is available so the gesture layer can switch input modes.

- [ ] **Step 1: Write tests**

File: `BitmeTests/Gestures/PencilAvailabilityTests.swift`
```swift
import XCTest
@testable import Bitme

final class PencilAvailabilityTests: XCTestCase {
    func testDefaultIsNotAvailable() {
        let p = PencilAvailability()
        XCTAssertFalse(p.isPencilAvailable)
    }

    func testSettingTrueFlips() {
        let p = PencilAvailability()
        p.isPencilAvailable = true
        XCTAssertTrue(p.isPencilAvailable)
    }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement**

File: `Bitme/Gestures/PencilAvailability.swift`
```swift
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@Observable
final class PencilAvailability {
    var isPencilAvailable: Bool

    init() {
        #if canImport(UIKit)
        self.isPencilAvailable = UIPencilInteraction.prefersPencilOnlyDrawing
        #else
        self.isPencilAvailable = false
        #endif
    }

    #if canImport(UIKit)
    func updateFromTouch(_ touch: UITouch) {
        if touch.type == .pencil {
            isPencilAvailable = true
        }
    }
    #endif
}
```

> Note: iPadOS doesn't expose a direct "is Pencil connected" boolean. The practical signal is: we've just seen a touch of type `.pencil`. We flip the flag on first Pencil touch; in practice a user tapping the canvas with the Pencil establishes the mode within one touch.

- [ ] **Step 4: Regenerate + test — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add Bitme/Gestures/PencilAvailability.swift BitmeTests/Gestures/PencilAvailabilityTests.swift
git commit -m "feat(gestures): PencilAvailability observable driven by touch type"
```

---

### Task 7.5: CanvasHostView — UIKit-hosted input layer

**Files:**
- Create: `Bitme/Gestures/CanvasHostView.swift`
- Modify: `Bitme/Views/Editor/CanvasView.swift`

Input-heavy gesture handling (coalesced touches, Pencil vs finger) is cleaner in a `UIView` subclass than in SwiftUI. Wrap it via `UIViewRepresentable`.

- [ ] **Step 1: Create the UIView-backed host**

File: `Bitme/Gestures/CanvasHostView.swift`
```swift
import SwiftUI
import UIKit

struct CanvasHostView: UIViewRepresentable {
    @Bindable var state: EditorState
    var pencilAvailability: PencilAvailability
    var onStrokePoint: (Int, Int) -> Void
    var onStrokeBegin: () -> Void
    var onStrokeEnd: () -> Void
    var onStrokeCancel: () -> Void
    var onTap: (Int, Int) -> Void       // for single taps (first-pixel on tap)

    func makeUIView(context: Context) -> CanvasInputView {
        let v = CanvasInputView()
        v.configure(state: state, pencilAvailability: pencilAvailability)
        v.onStrokePoint = onStrokePoint
        v.onStrokeBegin = onStrokeBegin
        v.onStrokeEnd = onStrokeEnd
        v.onStrokeCancel = onStrokeCancel
        v.onTap = onTap
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: CanvasInputView, context: Context) {
        uiView.configure(state: state, pencilAvailability: pencilAvailability)
    }
}

final class CanvasInputView: UIView {
    var state: EditorState?
    var pencilAvailability: PencilAvailability?
    var onStrokePoint: ((Int, Int) -> Void)?
    var onStrokeBegin: (() -> Void)?
    var onStrokeEnd: (() -> Void)?
    var onStrokeCancel: (() -> Void)?
    var onTap: ((Int, Int) -> Void)?

    private var strokeInProgress = false
    private var lastPixel: (Int, Int)?

    func configure(state: EditorState, pencilAvailability: PencilAvailability) {
        self.state = state
        self.pencilAvailability = pencilAvailability
        isMultipleTouchEnabled = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state else { return }
        // Pencil-aware: if any pencil touch present, only accept pencil for drawing.
        if let pencil = touches.first(where: { $0.type == .pencil }) {
            pencilAvailability?.updateFromTouch(pencil)
            beginStrokeIfDrawable(touch: pencil)
            return
        }
        if pencilAvailability?.isPencilAvailable == true {
            // finger touch while pencil-mode is active → single-finger pans; do not draw.
            return
        }
        if let touch = touches.first {
            beginStrokeIfDrawable(touch: touch)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard strokeInProgress, let state, let event else { return }
        let drawingTouches = touches.filter { shouldDraw(with: $0) }
        for touch in drawingTouches {
            let coalesced = event.coalescedTouches(for: touch) ?? [touch]
            for t in coalesced {
                if let p = pixelCoord(for: t) {
                    if let last = lastPixel {
                        for pt in bresenhamLine(from: last, to: p) {
                            onStrokePoint?(pt.0, pt.1)
                        }
                    } else {
                        onStrokePoint?(p.0, p.1)
                    }
                    lastPixel = p
                }
            }
        }
        _ = state  // keep reference
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard strokeInProgress else { return }
        // If this was a tap (no move), emit onTap for the starting pixel.
        if lastPixel == nil, let first = touches.first, let p = pixelCoord(for: first) {
            onTap?(p.0, p.1)
            strokeInProgress = false
            lastPixel = nil
            return
        }
        strokeInProgress = false
        lastPixel = nil
        onStrokeEnd?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard strokeInProgress else { return }
        strokeInProgress = false
        lastPixel = nil
        onStrokeCancel?()
    }

    private func shouldDraw(with touch: UITouch) -> Bool {
        if pencilAvailability?.isPencilAvailable == true {
            return touch.type == .pencil
        }
        return true
    }

    private func beginStrokeIfDrawable(touch: UITouch) {
        guard shouldDraw(with: touch) else { return }
        strokeInProgress = true
        lastPixel = nil
        onStrokeBegin?()
    }

    /// Convert a UITouch location to a pixel coordinate on the underlying grid, accounting for
    /// the current editor transform (translation, scale, rotation).
    private func pixelCoord(for touch: UITouch) -> (Int, Int)? {
        guard let state else { return nil }
        let dim = CGFloat(state.grid.dimension)
        let size = bounds.size
        let perPixel = Swift.min(size.width, size.height) * 0.85 / dim
        let canvasEdge = floor(perPixel) * dim

        let p = touch.location(in: self)
        // translate so canvas center is at origin, then apply inverse of the view transform
        let centered = CGPoint(x: p.x - size.width / 2 - state.translation.width,
                               y: p.y - size.height / 2 - state.translation.height)
        let cos = Foundation.cos(-state.rotation)
        let sin = Foundation.sin(-state.rotation)
        let rotated = CGPoint(x: centered.x * cos - centered.y * sin,
                              y: centered.x * sin + centered.y * cos)
        let scaled = CGPoint(x: rotated.x / state.scale,
                             y: rotated.y / state.scale)
        // now scaled is in canvas-local coords centered at origin; map to pixel
        let px = floor((scaled.x + canvasEdge / 2) / (canvasEdge / dim))
        let py = floor((scaled.y + canvasEdge / 2) / (canvasEdge / dim))
        let ix = Int(px)
        let iy = Int(py)
        guard ix >= 0, iy >= 0, ix < Int(dim), iy < Int(dim) else { return nil }
        return (ix, iy)
    }
}
```

- [ ] **Step 2: Add CanvasHostView on top of the render**

In `Bitme/Views/Editor/CanvasView.swift`, replace the whole body to overlay the input layer:

```swift
import SwiftUI
import UIKit

struct CanvasView: View {
    @Bindable var state: EditorState
    let pencilAvailability: PencilAvailability

    var onStrokePoint: (Int, Int) -> Void = { _, _ in }
    var onStrokeBegin: () -> Void = {}
    var onStrokeEnd: () -> Void = {}
    var onStrokeCancel: () -> Void = {}
    var onTap: (Int, Int) -> Void = { _, _ in }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                canvasImage
                    .frame(width: baseEdge(in: geo), height: baseEdge(in: geo))
                    .scaleEffect(state.scale)
                    .rotationEffect(.radians(state.rotation))
                    .offset(state.translation)
                CanvasHostView(
                    state: state,
                    pencilAvailability: pencilAvailability,
                    onStrokePoint: onStrokePoint,
                    onStrokeBegin: onStrokeBegin,
                    onStrokeEnd: onStrokeEnd,
                    onStrokeCancel: onStrokeCancel,
                    onTap: onTap
                )
            }
            .contentShape(Rectangle())
            .clipped()
        }
    }

    private var canvasImage: some View {
        let dim = state.grid.dimension
        return Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            context.withCGContext { cgContext in
                cgContext.interpolationQuality = .none
                cgContext.setShouldAntialias(false)

                let tile: CGFloat = 2
                for y in stride(from: 0.0, to: CGFloat(dim), by: tile) {
                    for x in stride(from: 0.0, to: CGFloat(dim), by: tile) {
                        let isDark = (Int(x / tile) + Int(y / tile)) % 2 == 0
                        cgContext.setFillColor(UIColor(white: isDark ? 0.72 : 0.88, alpha: 1).cgColor)
                        cgContext.fill(CGRect(x: x, y: CGFloat(dim) - y - tile, width: tile, height: tile))
                    }
                }

                if let image = pixelsToCGImage(state.grid) {
                    cgContext.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(dim), height: CGFloat(dim)))
                }
            }
        }
        .frame(width: CGFloat(dim), height: CGFloat(dim))
        .drawingGroup(opaque: false, colorMode: .nonLinear)
    }

    private func baseEdge(in geo: GeometryProxy) -> CGFloat {
        let m = Swift.min(geo.size.width, geo.size.height) * 0.85
        let dim = CGFloat(state.grid.dimension)
        let perPixel = floor(m / dim)
        return max(perPixel, 1) * dim
    }
}
```

- [ ] **Step 3: Wire EditorView to drive drawing through state**

Update the `ZStack` in `EditorView` that hosts the canvas:

```swift
ZStack {
    Color(white: 0.10).ignoresSafeArea(edges: [.leading, .trailing])
    CanvasView(
        state: state,
        pencilAvailability: pencilAvailability,
        onStrokePoint: { x, y in applyDrawPoint(x: x, y: y) },
        onStrokeBegin: { state.beginStrokeSnapshot() },
        onStrokeEnd: { commitStrokeAndSave() },
        onStrokeCancel: { state.cancelStroke() },
        onTap: { x, y in
            state.beginStrokeSnapshot()
            applyDrawPoint(x: x, y: y)
            commitStrokeAndSave()
        }
    )
}
```

And add to `EditorView`:

```swift
@State private var pencilAvailability = PencilAvailability()

private func applyDrawPoint(x: Int, y: Int) {
    switch state.tool {
    case .pencil:
        Pencil.paint(on: &state.grid, at: (x, y), color: state.color)
    case .eraser:
        Eraser.erase(on: &state.grid, at: (x, y))
    case .fill:
        Fill.fill(on: &state.grid, at: (x, y), with: state.color)
    case .eyedropper:
        if let picked = Eyedropper.pick(from: state.grid, at: (x, y)) {
            state.color = picked
        }
    }
}

private func commitStrokeAndSave() {
    state.commitStroke()
    let repo = PieceRepository(context: modelContext)
    try? repo.save(piece: piece, pixels: state.grid.data)
}
```

- [ ] **Step 4: Regenerate + build + sim**

Draw pencil on a 16×16 canvas with a finger (no Pencil). Expect: black dots appear where you tap.

- [ ] **Step 5: Commit**

```bash
git add Bitme/Gestures/CanvasHostView.swift Bitme/Views/Editor/CanvasView.swift Bitme/Views/Editor/EditorView.swift
git commit -m "feat(editor): input layer with coalesced touches + tap-to-paint"
```

---

### Task 7.6: Two-finger transform gesture (pan + pinch + rotate)

**Files:**
- Modify: `Bitme/Gestures/CanvasHostView.swift`

- [ ] **Step 1: Add a `UIGestureRecognizer` combo for pan + pinch + rotate on two fingers**

Add inside `CanvasInputView.configure`:
```swift
if gestureRecognizers?.isEmpty ?? true {
    let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    pan.minimumNumberOfTouches = 2
    pan.maximumNumberOfTouches = 2
    addGestureRecognizer(pan)
    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    addGestureRecognizer(pinch)
    let rot = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
    addGestureRecognizer(rot)
    [pan, pinch, rot].forEach { $0.delegate = self }
}
```

Add handlers + delegate conformance to `CanvasInputView`:
```swift
@objc private func handlePan(_ g: UIPanGestureRecognizer) {
    guard let state else { return }
    let t = g.translation(in: self)
    state.translation = CGSize(
        width: state.translation.width + t.width,
        height: state.translation.height + t.height
    )
    g.setTranslation(.zero, in: self)
    if g.state == .began { cancelStrokeIfAny() }
}

@objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
    guard let state else { return }
    let newScale = max(0.25, min(40, state.scale * g.scale))
    state.scale = newScale
    g.scale = 1
    if g.state == .began { cancelStrokeIfAny() }
}

@objc private func handleRotation(_ g: UIRotationGestureRecognizer) {
    guard let state else { return }
    var next = state.rotation + g.rotation
    // snap to 0 within 4° (≈0.0698 rad)
    if abs(next) < 0.0698 { next = 0 }
    state.rotation = next
    g.rotation = 0
    if g.state == .began { cancelStrokeIfAny() }
}

private func cancelStrokeIfAny() {
    guard strokeInProgress else { return }
    strokeInProgress = false
    lastPixel = nil
    onStrokeCancel?()
}
```

Extend CanvasInputView:
```swift
extension CanvasInputView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true  // pan + pinch + rotate all work together
    }
}
```

- [ ] **Step 2: Sim check**

Two-finger drag → canvas pans. Pinch → scales (bounded to [0.25, 40]). Two-finger rotate → rotates; rotating near upright snaps to 0.

- [ ] **Step 3: Commit**

```bash
git add Bitme/Gestures/CanvasHostView.swift
git commit -m "feat(editor): two-finger pan + pinch + rotate with snap-to-0"
```

---

### Task 7.7: Two-finger double-tap to reset transform

**Files:**
- Modify: `Bitme/Gestures/CanvasHostView.swift`

- [ ] **Step 1: Add a two-finger double-tap recognizer**

Inside `configure`, also add:
```swift
let reset = UITapGestureRecognizer(target: self, action: #selector(handleReset(_:)))
reset.numberOfTapsRequired = 2
reset.numberOfTouchesRequired = 2
addGestureRecognizer(reset)
```

Add handler:
```swift
@objc private func handleReset(_ g: UITapGestureRecognizer) {
    guard let state else { return }
    state.translation = .zero
    state.scale = 1.0
    state.rotation = 0.0
}
```

- [ ] **Step 2: Sim check**

After transforming the canvas, two-finger double-tap → snaps back to centered, upright, 1×.

- [ ] **Step 3: Commit**

```bash
git add Bitme/Gestures/CanvasHostView.swift
git commit -m "feat(editor): two-finger double-tap resets transform"
```

---

### Task 7.8: Grid overlay at ≥4× zoom

**Files:**
- Modify: `Bitme/Views/Editor/CanvasView.swift`

- [ ] **Step 1: Draw hairline grid lines inside the Canvas when `state.scale >= 4`**

Inside `canvasImage`'s CGContext closure, AFTER drawing the image, append:
```swift
if state.scale >= 4 {
    // 1 device pixel regardless of zoom
    let screenScale = UIScreen.main.scale
    cgContext.setStrokeColor(UIColor(white: 0.0, alpha: 0.35).cgColor)
    let hairline: CGFloat = (1.0 / screenScale) / state.scale
    cgContext.setLineWidth(hairline)
    let dim = state.grid.dimension
    for i in 1..<dim {
        let p = CGFloat(i)
        cgContext.move(to: CGPoint(x: p, y: 0))
        cgContext.addLine(to: CGPoint(x: p, y: CGFloat(dim)))
        cgContext.move(to: CGPoint(x: 0, y: p))
        cgContext.addLine(to: CGPoint(x: CGFloat(dim), y: p))
    }
    cgContext.strokePath()
}
```

> Note: a future optimization could pre-generate the grid path once per size; at 128×128 with 127 grid lines per axis the per-frame stroke is still cheap on a modern iPad.

- [ ] **Step 2: Sim check**

Zoom in past ~4× and confirm a thin grid becomes visible between pixels. Zoom out and it disappears.

- [ ] **Step 3: Commit**

```bash
git add Bitme/Views/Editor/CanvasView.swift
git commit -m "feat(editor): hairline grid overlay at >=4x zoom"
```

---

## Phase 8 — Editor chrome (tools + colors + share)

### Task 8.1: ToolBar

**Files:**
- Create: `Bitme/Views/Editor/ToolBar.swift`
- Modify: `Bitme/Views/Editor/EditorView.swift`

- [ ] **Step 1: Create the tool bar**

File: `Bitme/Views/Editor/ToolBar.swift`
```swift
import SwiftUI

struct ToolBar: View {
    @Bindable var state: EditorState

    var body: some View {
        HStack(spacing: 22) {
            ForEach(Tool.allCases, id: \.self) { tool in
                Button {
                    state.tool = tool
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tool.sfSymbol)
                            .font(.system(size: 20, weight: .regular))
                        Text(tool.displayName)
                            .font(.caption2)
                    }
                    .foregroundStyle(state.tool == tool ? Color.white : Color.white.opacity(0.55))
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 2: Wire in EditorView**

Replace the bottom Rectangle overlay in `EditorView` with:
```swift
HStack(spacing: 20) {
    ToolBar(state: state)
    Divider().frame(height: 36).overlay(Color.white.opacity(0.15))
    // colors strip next task
    Spacer()
}
.padding(.horizontal, 18)
.padding(.vertical, 10)
.frame(height: 72)
.background(Color(white: 0.09))
```

- [ ] **Step 3: Commit**

```bash
git add Bitme/Views/Editor/ToolBar.swift Bitme/Views/Editor/EditorView.swift
git commit -m "feat(editor): ToolBar view with selected-tool highlight"
```

---

### Task 8.2: RecentColorsStrip

**Files:**
- Create: `Bitme/Views/Editor/RecentColorsStrip.swift`
- Modify: `Bitme/Views/Editor/EditorView.swift`

- [ ] **Step 1: Create the strip**

File: `Bitme/Views/Editor/RecentColorsStrip.swift`
```swift
import SwiftUI

struct RecentColorsStrip: View {
    @Binding var selectedColor: RGBA
    @Binding var recentHex: [String]
    var onRequestColorPicker: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(recentHex, id: \.self) { hex in
                    SwatchButton(
                        hex: hex,
                        isSelected: selectedColor == RGBA(hex: hex),
                        action: {
                            if let c = RGBA(hex: hex) { selectedColor = c }
                        }
                    )
                }
                Button(action: onRequestColorPicker) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.25), style: .init(lineWidth: 1, dash: [2, 2])))
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct SwatchButton: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let color = Color(rgba: RGBA(hex: hex) ?? .transparent)
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color, lineWidth: isSelected ? 3 : 0)
                        .padding(-2)
                )
        }
        .buttonStyle(.plain)
    }
}

extension RGBA {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let n = UInt32(s, radix: 16) else { return nil }
        self = RGBA(
            r: UInt8((n >> 16) & 0xFF),
            g: UInt8((n >> 8) & 0xFF),
            b: UInt8(n & 0xFF),
            a: 255
        )
    }
    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

extension Color {
    init(rgba: RGBA) {
        self.init(
            .sRGB,
            red: Double(rgba.r) / 255.0,
            green: Double(rgba.g) / 255.0,
            blue: Double(rgba.b) / 255.0,
            opacity: Double(rgba.a) / 255.0
        )
    }
}
```

- [ ] **Step 2: Wire it into EditorView**

Add state + load/save of AppSettings in `EditorView`:
```swift
@State private var recentHex: [String] = []
@State private var showingSystemColorPicker = false
@State private var pickerColor = Color.black
```

On appear, hydrate from settings:
```swift
.onAppear {
    let repo = PieceRepository(context: modelContext)
    if let settings = try? repo.appSettings() {
        recentHex = settings.recentColors
    }
}
```

In the bottom bar, replace the `Spacer()` with:
```swift
RecentColorsStrip(
    selectedColor: $state.color,
    recentHex: $recentHex,
    onRequestColorPicker: { showingSystemColorPicker = true }
)
```

Append the color-picker sheet:
```swift
.sheet(isPresented: $showingSystemColorPicker) {
    VStack {
        ColorPicker("Pick a color", selection: $pickerColor, supportsOpacity: false)
            .padding()
        Button("Use") {
            if let cgColor = pickerColor.cgColor, let rgba = RGBA(cgColor: cgColor) {
                state.color = rgba
                addRecent(rgba.hex)
            }
            showingSystemColorPicker = false
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
    .presentationDetents([.medium])
}
```

Add helpers:
```swift
private func addRecent(_ hex: String) {
    let repo = PieceRepository(context: modelContext)
    if let settings = try? repo.appSettings() {
        settings.addRecentColor(hex)
        recentHex = settings.recentColors
        try? modelContext.save()
    }
}
```

Extend RGBA with CGColor init (put next to the hex extension):
```swift
extension RGBA {
    init?(cgColor: CGColor) {
        guard let components = cgColor.components, components.count >= 3 else { return nil }
        self = RGBA(
            r: UInt8((components[0] * 255).rounded().clamped(0, 255)),
            g: UInt8((components[1] * 255).rounded().clamped(0, 255)),
            b: UInt8((components[2] * 255).rounded().clamped(0, 255)),
            a: 255
        )
    }
}
private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { min(max(self, lo), hi) }
}
```

Also: whenever a pencil stroke commits, add the current color to recents. In `commitStrokeAndSave()`:
```swift
addRecent(state.color.hex)
```

- [ ] **Step 3: Build + sim check**

Open editor, tap + on strip, pick a color, confirm. Swatch appears in strip with selected outline. Tap another — selected highlight moves.

- [ ] **Step 4: Commit**

```bash
git add Bitme/Views/Editor/RecentColorsStrip.swift Bitme/Views/Editor/EditorView.swift
git commit -m "feat(editor): recent-colors strip with rectangle swatches and system picker"
```

---

## Phase 9 — Export / share

### Task 9.1: Share sheet with scale picker

**Files:**
- Create: `Bitme/Views/Editor/ShareSheet.swift`
- Modify: `Bitme/Views/Editor/EditorView.swift`

- [ ] **Step 1: Create the share sheet**

File: `Bitme/Views/Editor/ShareSheet.swift`
```swift
import SwiftUI
import UIKit

struct ShareSheet: View {
    let piece: Piece
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScale: Int

    init(piece: Piece) {
        self.piece = piece
        self._selectedScale = State(initialValue: Self.defaultScale(for: piece.size))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scale") {
                    Picker("Scale", selection: $selectedScale) {
                        ForEach([1, 2, 4, 8, 16], id: \.self) { s in
                            let edge = piece.size.dimension * s
                            Text("\(s)× · \(edge) × \(edge)").tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section {
                    Button("Share") { share() }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private static func defaultScale(for size: CanvasSize) -> Int {
        switch size {
        case .s16: 16
        case .s32: 16
        case .s64: 8
        case .s128: 4
        }
    }

    private func share() {
        let grid = PixelGrid(data: piece.pixels, size: piece.size)
        guard let data = PNGExporter.export(grid: grid, scale: selectedScale) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(piece.effectiveName)-\(selectedScale)x.png")
        try? data.write(to: url)
        // hand off to system share sheet
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.activeWindow?.rootViewController?.present(vc, animated: true)
        dismiss()
    }
}

private extension UIApplication {
    var activeWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }
}
```

- [ ] **Step 2: Wire it from EditorView's Share button**

In EditorView add:
```swift
@State private var showingShareSheet = false
```

Change the Share button in `topBar`:
```swift
Button("Share") { showingShareSheet = true }
```

Append modifier:
```swift
.sheet(isPresented: $showingShareSheet) {
    ShareSheet(piece: piece)
        .presentationDetents([.medium])
}
```

- [ ] **Step 3: Sim check**

Draw something on a 32×32 → Share → pick 16× (512×512) → PNG opens in the share sheet, can AirDrop/Save to Photos.

- [ ] **Step 4: Commit**

```bash
git add Bitme/Views/Editor/ShareSheet.swift Bitme/Views/Editor/EditorView.swift
git commit -m "feat(export): share sheet with per-size default scale and integer options"
```

---

## Phase 10 — Happy-path UI test

### Task 10.1: End-to-end test

**Files:**
- Create: `BitmeUITests/HappyPathTests/DrawAndSaveTest.swift`
- Modify: `Bitme/Views/Gallery/PieceThumbnailView.swift` (add accessibility identifiers)

- [ ] **Step 1: Add accessibility identifiers**

In `PieceThumbnailView`, add:
```swift
.accessibilityIdentifier("PieceThumbnail")
```

In `NewPieceSheet`'s per-row Button:
```swift
.accessibilityIdentifier("NewPiece-\(size.rawValue)")
```

In `GalleryView` toolbar + button:
```swift
Button { showingNewSheet = true } label: { Label("New", systemImage: "plus") }
    .accessibilityIdentifier("NewButton")
```

- [ ] **Step 2: Write the test**

File: `BitmeUITests/HappyPathTests/DrawAndSaveTest.swift`
```swift
import XCTest

final class DrawAndSaveTest: XCTestCase {
    func testCreatePieceDrawAndReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset"]
        app.launch()

        // 1. create
        app.buttons["NewButton"].tap()
        app.buttons["NewPiece-32"].tap()

        // 2. the editor is up — tap in the middle to paint (finger == pencil in sim)
        let window = app.windows.firstMatch
        let center = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.tap()

        // 3. navigate back to gallery
        app.buttons["Gallery"].tap()

        // 4. thumbnail should be present
        XCTAssertTrue(app.otherElements["PieceThumbnail"].waitForExistence(timeout: 2))
    }
}
```

- [ ] **Step 3: Handle the launch argument (wipe in-memory store during UI tests)**

In `BitmeApp`:
```swift
var body: some Scene {
    WindowGroup {
        GalleryView()
    }
    .modelContainer(
        for: [Piece.self, AppSettings.self],
        inMemory: ProcessInfo.processInfo.arguments.contains("-UITest-reset")
    )
}
```

- [ ] **Step 4: Regenerate + run UI test**

```bash
xcodegen generate
xcodebuild test -project Bitme.xcodeproj -scheme Bitme -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:BitmeUITests | tail -10
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add BitmeUITests/HappyPathTests/DrawAndSaveTest.swift Bitme/Views/Gallery/PieceThumbnailView.swift Bitme/Views/Gallery/GalleryView.swift Bitme/Views/Gallery/NewPieceSheet.swift Bitme/BitmeApp.swift
git commit -m "test(ui): happy-path create/draw/reopen flow"
```

---

## Verification checklist

After all tasks, verify the full app on-device / sim manually:

- [ ] Create a 16×16, 32×32, 64×64, 128×128 piece — each opens in the editor with a checkered transparent canvas.
- [ ] Pencil draws with finger on empty canvas.
- [ ] Two-finger pan / pinch / rotate works; rotation snaps to 0° near upright; scale bounded to 0.25× – 40×.
- [ ] Two-finger double-tap resets transform.
- [ ] Drawing mid-transform is cancelled cleanly (no partial strokes in undo).
- [ ] Eraser sets pixels to exact transparent (checker visible through).
- [ ] Fill bucket fills connected regions only; works on transparent regions; same-color fill is a no-op.
- [ ] Eyedropper picks opaque pixels; picking transparent is a no-op (current color unchanged).
- [ ] Recent colors strip updates when stroke commits; + opens system color picker; selected swatch shows same-color halo.
- [ ] Undo / Redo arrows function; tapping into editor resets history (no cross-session undo).
- [ ] Long-press in gallery → Rename / Duplicate / Delete (with destructive confirmation).
- [ ] Share → picks default scale per canvas size; export PNG is integer-scaled and crisp (nearest-neighbor) in other apps.
- [ ] Grid overlay appears at ≥4× zoom, stays hairline-thin regardless of deeper zoom.
- [ ] Pencil connected → finger pans, Pencil draws. Pencil disconnected → finger draws.
- [ ] Backgrounding the app mid-edit → reopening shows all committed strokes persisted.

---

## Self-review notes (plan author)

**Spec coverage** — mapped each spec section:
- Purpose + non-goals → addressed by scope of tasks and explicit out-of-scope in spec.
- Platform & scope → Task 0.1 (project.yml deployment target, iPad-only).
- Canvas sizes → Task 1.1 + 6.3.
- Screens → Phase 6 (gallery) + Phase 7-9 (editor).
- Tools → Tasks 2.3 / 2.4 / 2.5 / 2.6 + Task 8.1 (tool bar).
- Color picking → Task 8.2 + `AppSettings` (Task 1.4).
- Canvas transform & gestures → Tasks 7.6 / 7.7.
- Background / transparency → Tasks 1.3 (all-zero bytes) + 7.3 (checker).
- Grid overlay → Task 7.8.
- Export / share → Task 9.1.
- Data model & storage → Tasks 1.3 / 1.4 / 4.1.
- Module layout → Directory structure enforced by task file paths.
- Fidelity guarantees → Task 3.1 (sRGB), 3.3 (sRGB export + NN), 7.5 (coalesced touches + Bresenham + first-pixel-on-tap), 7.8 (hairline grid), CanvasView NN + AA off (Task 7.2).
- Edge cases → Cancel mid-stroke (Task 7.6 `cancelStrokeIfAny`), delete confirm (Task 6.4), eyedropper no-op on transparent (Task 2.6), fill OOB no-op (Task 2.5), transform bounds (Task 7.6), backgrounding persistence (Task 7.5 save in `commitStrokeAndSave`).
- Testing strategy → Phase 2/3/4 unit tests + Task 10.1 UI test.

**Placeholder scan** — no "TBD", "TODO", or "implement later" in steps. One deliberate forward-reference: Task 7.5 places an EmptyView in `canvasImage` with a "keep previous impl" note — the engineer must copy the real body from Task 7.3. This is called out in the step text.

**Type consistency** — spot checks:
- `PixelGrid` — created Task 2.1, used everywhere with the same `pixel(x:y:)` / `setPixel(x:y:color:)` / `data` / `size` / `dimension` signatures.
- `RGBA` — same four-byte struct everywhere; `.transparent` constant defined once.
- `pixelsToCGImage(_ grid: PixelGrid)` — same signature in all call sites.
- `PieceRepository` — `createPiece(size:)`, `save(piece:pixels:)`, `rename(piece:to:)`, `duplicate(piece:)`, `delete(piece:)`, `allPieces()`, `appSettings()` — same names used in Task 6.1+.
- `Tool` cases — `.pencil`, `.eraser`, `.fill`, `.eyedropper` — stable across ToolBar and `applyDrawPoint` switch.
- `CanvasHostView`'s callback set (`onStrokeBegin`, `onStrokeEnd`, `onStrokeCancel`, `onStrokePoint`, `onTap`) — used identically in `CanvasView` and EditorView wiring.

No inconsistencies found.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-19-bitme-implementation.md`.

Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints.

Which approach?
