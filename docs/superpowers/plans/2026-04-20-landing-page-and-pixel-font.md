# Landing Page and App-Wide Pixel Font Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an arcade-style landing screen (black bg, "BITME" title, blinking "PRESS START") as the app's root, plus apply Press Start 2P across chrome text (titles, buttons, labels). Alerts and text-field input stay in the system font.

**Architecture:** A new `RootView` holds `@State var screen: Screen` and switches between `LandingView` and `GalleryView`. The gallery's `NavigationStack` (and its Editor pushes / sheets / alerts) stays intact. Press Start 2P is bundled as a `.ttf`, registered via generated Info.plist (`INFOPLIST_KEY_UIAppFonts` in `project.yml`), and consumed through a `Font.pixel(_:)` helper applied at each call site. No global appearance swizzling.

**Tech Stack:** SwiftUI, SwiftData, UIKit (existing). XcodeGen for project generation. XCTest for unit + UI tests.

**Spec:** [docs/superpowers/specs/2026-04-20-landing-page-and-pixel-font-design.md](../specs/2026-04-20-landing-page-and-pixel-font-design.md)

**Global conventions** (repeat per task — engineer may read out of order):
- Project file is generated. After creating/renaming/moving any `.swift` or resource file, regenerate with: `rm -rf DrawBit.xcodeproj && xcodegen generate`
- Build/test target device: `'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'`. Substitute another iPad from `xcrun simctl list devices available | grep -i iPad` if that simulator is not installed.

---

## Task 1: Bundle Press Start 2P font and verify it registers

**Files:**
- Create: `DrawBit/Resources/Fonts/PressStart2P-Regular.ttf`
- Create: `DrawBit/Resources/Fonts/OFL.txt`
- Modify: `project.yml`
- Create: `DrawBitTests/Views/PixelFontTests.swift`

The font is Google Fonts' Press Start 2P under SIL OFL 1.1. The `.ttf` file is bundled into the app, and the OFL license text travels alongside it (OFL redistribution requirement).

- [ ] **Step 1: Create the fonts directory**

Run:

```bash
mkdir -p DrawBit/Resources/Fonts
```

- [ ] **Step 2: Download the font and license**

Run:

```bash
curl -fL -o DrawBit/Resources/Fonts/PressStart2P-Regular.ttf \
  https://github.com/google/fonts/raw/main/ofl/pressstart2p/PressStart2P-Regular.ttf
curl -fL -o DrawBit/Resources/Fonts/OFL.txt \
  https://github.com/google/fonts/raw/main/ofl/pressstart2p/OFL.txt
```

Expected: two files created. Verify:

```bash
ls -la DrawBit/Resources/Fonts/
```

The `.ttf` should be ~26 KB; `OFL.txt` ~4–5 KB.

- [ ] **Step 3: Register the font in `project.yml`**

Edit `project.yml` and add `INFOPLIST_KEY_UIAppFonts: "PressStart2P-Regular.ttf"` to the `DrawBit` target's `settings.base` block, directly under the existing `INFOPLIST_KEY_CFBundleDisplayName: DrawBit` line. The block should look like this afterwards:

```yaml
  DrawBit:
    type: application
    platform: iOS
    sources:
      - path: DrawBit
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "2"
        PRODUCT_BUNDLE_IDENTIFIER: com.iamilias.drawbit
        GENERATE_INFOPLIST_FILE: "YES"
        INFOPLIST_KEY_UILaunchScreen_Generation: "YES"
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: "YES"
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad: "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortraitUpsideDown"
        INFOPLIST_KEY_UIRequiresFullScreen: "NO"
        INFOPLIST_KEY_CFBundleDisplayName: DrawBit
        INFOPLIST_KEY_UIAppFonts: "PressStart2P-Regular.ttf"
```

- [ ] **Step 4: Regenerate the Xcode project**

Run:

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
```

Expected: output ending with `✅ Created project at /Users/iliasrafailidis/drawbit/DrawBit.xcodeproj`.

- [ ] **Step 5: Write the failing font-registration test**

Create `DrawBitTests/Views/PixelFontTests.swift` with:

```swift
import XCTest
import UIKit
@testable import DrawBit

final class PixelFontTests: XCTestCase {
    func testPressStart2PIsRegistered() {
        XCTAssertNotNil(
            UIFont(name: "PressStart2P-Regular", size: 12),
            "PressStart2P-Regular must be registered via Info.plist's UIAppFonts. Check project.yml INFOPLIST_KEY_UIAppFonts and that DrawBit/Resources/Fonts/PressStart2P-Regular.ttf exists."
        )
    }
}
```

- [ ] **Step 6: Regenerate and run the test**

Run:

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitTests/PixelFontTests/testPressStart2PIsRegistered
```

Expected: `Test Suite 'PixelFontTests' passed`. If it fails: the `.ttf` is missing, the `UIAppFonts` key is not wired, or the PostScript name differs (confirm with `fc-query DrawBit/Resources/Fonts/PressStart2P-Regular.ttf | grep postscriptname`; should be `PressStart2P-Regular`).

- [ ] **Step 7: Commit**

```bash
git add DrawBit/Resources/Fonts/ project.yml DrawBitTests/Views/PixelFontTests.swift
git commit -m "feat(chrome): bundle Press Start 2P font

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Add `Font.pixel(_:)` helper

**Files:**
- Create: `DrawBit/Views/Support/PixelFont.swift`

- [ ] **Step 1: Create the helper**

Create `DrawBit/Views/Support/PixelFont.swift` with:

```swift
import SwiftUI

extension Font {
    /// App-wide display font. Use for chrome text (titles, buttons, labels).
    /// Not for text-field input or alerts — those stay on the system font for legibility.
    static func pixel(_ size: CGFloat) -> Font {
        .custom("PressStart2P-Regular", size: size)
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run:

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Support/PixelFont.swift
git commit -m "feat(chrome): add Font.pixel helper

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Create `LandingView`

**Files:**
- Create: `DrawBit/Views/Landing/LandingView.swift`

- [ ] **Step 1: Write the view**

Create `DrawBit/Views/Landing/LandingView.swift` with:

```swift
import SwiftUI

struct LandingView: View {
    var onStart: () -> Void

    @State private var pressStartVisible: Bool = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 48) {
                Text("BITME")
                    .font(.pixel(72))
                    .foregroundStyle(.white)
                Text("PRESS START")
                    .font(.pixel(18))
                    .foregroundStyle(.white)
                    .opacity(pressStartVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pressStartVisible)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onStart() }
        .statusBarHidden(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("LandingStart")
        .onAppear { pressStartVisible.toggle() }
    }
}

#Preview {
    LandingView(onStart: {})
}
```

Note: `pressStartVisible` starts `true`, toggles to `false` on appear, and `.animation(...repeatForever(autoreverses: true))` drives the blink.

- [ ] **Step 2: Regenerate and build**

Run:

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Landing/LandingView.swift
git commit -m "feat(landing): add arcade-style landing view

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Add `RootView` and switch app root; preserve existing UI test

**Files:**
- Create: `DrawBit/Views/Support/RootView.swift`
- Modify: `DrawBit/DrawBitApp.swift`
- Modify: `DrawBitUITests/HappyPathTests/DrawAndSaveTest.swift`

`RootView` owns the landing/gallery switch and passes an `onHome` closure down to `GalleryView` (wiring for that closure comes in Task 5). A launch argument `-UITest-skipLanding` starts on the gallery so existing UI tests don't need to tap past landing.

- [ ] **Step 1: Create `RootView`**

Create `DrawBit/Views/Support/RootView.swift` with:

```swift
import SwiftUI

enum RootScreen { case landing, gallery }

struct RootView: View {
    @State private var screen: RootScreen

    init() {
        let skip = ProcessInfo.processInfo.arguments.contains("-UITest-skipLanding")
        _screen = State(initialValue: skip ? .gallery : .landing)
    }

    var body: some View {
        switch screen {
        case .landing:
            LandingView(onStart: { screen = .gallery })
        case .gallery:
            GalleryView(onHome: { screen = .landing })
        }
    }
}
```

- [ ] **Step 2: Update `DrawBitApp` to use `RootView`**

Edit `DrawBit/DrawBitApp.swift`. Replace `GalleryView()` with `RootView()`. The file should end up as:

```swift
import SwiftUI
import SwiftData

@main
struct DrawBitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(
            for: [Piece.self, AppSettings.self],
            inMemory: ProcessInfo.processInfo.arguments.contains("-UITest-reset")
        )
    }
}
```

- [ ] **Step 3: Temporarily give `GalleryView` an `onHome` parameter**

Edit `DrawBit/Views/Gallery/GalleryView.swift`. Add a stored property at the top of the struct (above the `@Environment` line):

```swift
struct GalleryView: View {
    var onHome: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
```

A default value of `{}` keeps the project compiling before Task 5 wires the home button. Task 5 also removes the default — leaving `var onHome: () -> Void`.

- [ ] **Step 4: Update the existing UI test to skip landing**

Edit `DrawBitUITests/HappyPathTests/DrawAndSaveTest.swift`. Change:

```swift
app.launchArguments = ["-UITest-reset"]
```

to:

```swift
app.launchArguments = ["-UITest-reset", "-UITest-skipLanding"]
```

- [ ] **Step 5: Regenerate, build, and run all tests**

Run:

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```

Expected: all existing unit and UI tests pass, including `DrawAndSaveTest.testCreatePieceDrawAndReopen` and `PixelFontTests.testPressStart2PIsRegistered`.

- [ ] **Step 6: Commit**

```bash
git add DrawBit/Views/Support/RootView.swift DrawBit/DrawBitApp.swift \
        DrawBit/Views/Gallery/GalleryView.swift \
        DrawBitUITests/HappyPathTests/DrawAndSaveTest.swift
git commit -m "feat(app): root-level landing/gallery switch

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Gallery — home button, BITME title, pixel-font empty state

**Files:**
- Modify: `DrawBit/Views/Gallery/GalleryView.swift`

Replace the navigation title "Pieces" with an inline custom "BITME" in pixel font, add a leading home toolbar button, and replace `ContentUnavailableView` with a hand-rolled empty state so fonts can be overridden. Remove the default value from `onHome` now that `RootView` always supplies one.

- [ ] **Step 1: Drop the default from `onHome`**

In `DrawBit/Views/Gallery/GalleryView.swift`, change:

```swift
var onHome: () -> Void = {}
```

to:

```swift
var onHome: () -> Void
```

- [ ] **Step 2: Replace the nav title with an inline pixel-font title, add home toolbar button, and swap the empty state**

Edit the `body` to match this structure (only the changed pieces are shown; the rest stays as-is):

```swift
    var body: some View {
        NavigationStack {
            ScrollView {
                if pieces.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text("NO PIECES YET")
                            .font(.pixel(16))
                            .foregroundStyle(.primary)
                        Text("Tap + New to create your first canvas.")
                            .font(.pixel(11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(pieces) { piece in
                            PieceThumbnailView(piece: piece)
                                .onTapGesture { selectedPiece = piece }
                                .contextMenu {
                                    Button("Rename") {
                                        renameTarget = piece
                                        renameDraft = piece.name ?? ""
                                    }
                                    Button("Duplicate") { duplicate(piece) }
                                    Divider()
                                    Button("Delete", role: .destructive) { deleteTarget = piece }
                                }
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("BITME")
                        .font(.pixel(20))
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onHome()
                    } label: {
                        Image(systemName: "house.fill")
                    }
                    .accessibilityIdentifier("HomeButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewSheet = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .accessibilityIdentifier("NewButton")
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
                EditorView(piece: piece)
            }
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
        }
    }
```

Note: `.navigationTitle("Pieces")` is deleted — a `ToolbarItem(placement: .principal)` replaces it so we can control the font. `navigationBarTitleDisplayMode(.inline)` keeps the bar compact.

- [ ] **Step 3: Regenerate and build**

Run:

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run existing UI test (sanity check)**

Run:

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitUITests/DrawAndSaveTest
```

Expected: PASS. The test still launches with `-UITest-skipLanding`, so it lands on the gallery with the new toolbar. `NewButton` is still trailing; `HomeButton` is leading and unused by this test.

- [ ] **Step 5: Commit**

```bash
git add DrawBit/Views/Gallery/GalleryView.swift
git commit -m "feat(gallery): BITME title, home button, pixel-font empty state

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: UI tests — landing → gallery → landing

**Files:**
- Create: `DrawBitUITests/LandingScreenTests.swift`

- [ ] **Step 1: Write the tests**

Create `DrawBitUITests/LandingScreenTests.swift` with:

```swift
import XCTest

final class LandingScreenTests: XCTestCase {
    private func landingStart(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "LandingStart").firstMatch
    }

    func testStartTapEntersGallery() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset"]
        app.launch()

        let start = landingStart(app)
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.buttons["NewButton"].waitForExistence(timeout: 3))
    }

    func testHomeIconReturnsToLanding() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-reset"]
        app.launch()

        let start = landingStart(app)
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.buttons["HomeButton"].waitForExistence(timeout: 3))
        app.buttons["HomeButton"].tap()

        XCTAssertTrue(landingStart(app).waitForExistence(timeout: 3))
    }
}
```

Note: we query `LandingStart` via `descendants(matching: .any)` because `.accessibilityAddTraits(.isButton)` on a custom view can land in either `buttons` or `otherElements` depending on the SDK — this form is resilient either way.

- [ ] **Step 2: Regenerate and run the new UI tests**

Run:

```bash
rm -rf DrawBit.xcodeproj && xcodegen generate
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitUITests/LandingScreenTests
```

Expected: both tests PASS.

- [ ] **Step 3: Commit**

```bash
git add DrawBitUITests/LandingScreenTests.swift
git commit -m "test(ui): landing start + home-icon round trip

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Pixel font in `NewPieceSheet`

**Files:**
- Modify: `DrawBit/Views/Gallery/NewPieceSheet.swift`

- [ ] **Step 1: Apply the pixel font to size name and pixel count**

Edit `NewPieceSheet.swift`. Replace the `List` body:

```swift
            List(CanvasSize.allCases) { size in
                Button {
                    onCreate(size)
                    dismiss()
                } label: {
                    HStack {
                        Text(size.displayName)
                            .font(.pixel(16))
                        Spacer()
                        Text("\(size.pixelCount) pixels")
                            .foregroundStyle(.secondary)
                            .font(.pixel(11))
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("NewPiece-\(size.rawValue)")
            }
            .navigationTitle("New piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("NEW PIECE")
                        .font(.pixel(14))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.pixel(12))
                }
            }
```

Note: `.navigationTitle("New piece")` stays as the VoiceOver label but is visually replaced by the principal `ToolbarItem`. Keep both — the title string is used by accessibility even when the principal item is present.

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Gallery/NewPieceSheet.swift
git commit -m "feat(chrome): pixel font on NewPieceSheet

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Pixel font in `EditorView` top bar

**Files:**
- Modify: `DrawBit/Views/Editor/EditorView.swift`

- [ ] **Step 1: Apply the pixel font to top-bar chrome text**

Edit `EditorView.swift`. Replace the `topBar` property:

```swift
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("GALLERY")
                        .font(.pixel(11))
                }
            }
            .accessibilityIdentifier("Gallery")
            Spacer()
            Text(piece.size.displayName)
                .font(.pixel(12))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button {
                showingShareSheet = true
            } label: {
                Text("SHARE")
                    .font(.pixel(11))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
```

- [ ] **Step 2: Build and run existing UI test**

Run:

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test -only-testing:DrawBitUITests/DrawAndSaveTest
```

Expected: PASS. The test looks up `app.buttons["Gallery"]` by accessibility identifier, which is still set.

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Editor/EditorView.swift
git commit -m "feat(chrome): pixel font on editor top bar

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Pixel font in `ToolBar`

**Files:**
- Modify: `DrawBit/Views/Editor/ToolBar.swift`

- [ ] **Step 1: Apply the pixel font to tool name labels**

Edit `ToolBar.swift`. Replace the `iconLabel` helper:

```swift
    private func iconLabel(systemImage: String, title: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
            Text(title.uppercased())
                .font(.pixel(8))
        }
        .frame(minWidth: 44, minHeight: 44)
    }
```

Note: 8pt Press Start 2P is very small but still readable; the toolbar is vertically tight and the glyph above carries most of the meaning. `.uppercased()` keeps labels consistent with the font's blocky feel.

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Editor/ToolBar.swift
git commit -m "feat(chrome): pixel font on editor toolbar

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Pixel font in `ShareSheet`

**Files:**
- Modify: `DrawBit/Views/Editor/ShareSheet.swift`

- [ ] **Step 1: Apply the pixel font to form labels**

Edit `ShareSheet.swift`. Replace the `body`:

```swift
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Scale", selection: $selectedScale) {
                        ForEach([1, 2, 4, 8, 16], id: \.self) { s in
                            let edge = piece.size.dimension * s
                            Text("\(s)× · \(edge) × \(edge)")
                                .font(.pixel(12))
                                .tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("SCALE")
                        .font(.pixel(11))
                }
                Section {
                    Button {
                        share()
                    } label: {
                        Text("SHARE")
                            .font(.pixel(14))
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EXPORT")
                        .font(.pixel(14))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.pixel(12))
                }
            }
        }
    }
```

Note: `.navigationTitle("Export")` is retained for accessibility — the principal toolbar item replaces it visually.

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add DrawBit/Views/Editor/ShareSheet.swift
git commit -m "feat(chrome): pixel font on share sheet

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Full test suite green

**Files:** none

- [ ] **Step 1: Run the entire test suite on the target simulator**

Run:

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```

Expected: all unit tests and all UI tests (`DrawAndSaveTest`, `LandingScreenTests`, `PixelFontTests`) PASS.

- [ ] **Step 2: Device compile-check (no simulator; catches signing-free device issues)**

Run:

```bash
xcodebuild -project DrawBit.xcodeproj -scheme DrawBit -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

No commit in this task — verification only. Anything that fails here goes back to the task that introduced it.
