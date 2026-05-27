import XCTest
@testable import DrawBit

/// Tests for the pre-flight budget check that `ShareSheet` consults before
/// enabling a scale tile. The predicate must mirror `SpriteSheetExporter`'s grid
/// math exactly so the UI's "TOO BIG" verdict matches what the exporter would
/// actually try to allocate.
final class ExportSizeBudgetTests: XCTestCase {

    // MARK: - The worst case the user called out

    /// 64 frames × 128 canvas × 16 scale, sprite sheet:
    ///   cellEdge = 2048, grid = 8 × 8, output = 16384 × 16384 — over the 8192 cap.
    /// Without this check, `CGContext(...)` returns nil and the export silently aborts.
    func testSpriteSheetAtMaxFramesAndScaleIsOverBudget() {
        XCTAssertTrue(ExportSizeBudget.isOverBudget(
            format: .spriteSheet,
            canvasEdge: 128,
            scale: 16,
            frameCount: 64
        ))
    }

    func testSpriteSheetAtModerateConfigIsSafe() {
        // 8 frames × 32 canvas × 4 scale = 128px cell × 3×3 grid = 384px. Plenty of headroom.
        XCTAssertFalse(ExportSizeBudget.isOverBudget(
            format: .spriteSheet,
            canvasEdge: 32,
            scale: 4,
            frameCount: 8
        ))
    }

    /// 16 frames × 128 × 16 = 4 × 4 grid × 2048 = 8192 × 8192 exactly. Treat the
    /// edge case "exactly at cap" as still safe (≤). One more frame pushes the
    /// grid to 4 × 5 → 8192 × 10240, which crosses the limit.
    func testSpriteSheetAtExactlyMaxIsSafeButOneStepLargerIsNot() {
        XCTAssertFalse(ExportSizeBudget.isOverBudget(
            format: .spriteSheet, canvasEdge: 128, scale: 16, frameCount: 16
        ))
        XCTAssertTrue(ExportSizeBudget.isOverBudget(
            format: .spriteSheet, canvasEdge: 128, scale: 16, frameCount: 17
        ))
    }

    // MARK: - PNG is bounded at 2048 × 2048 — never overshoots at current limits

    func testPNGAtMaxScaleIsSafe() {
        // The largest output edge any canvas × scale combination produces today.
        XCTAssertFalse(ExportSizeBudget.isOverBudget(
            format: .png, canvasEdge: 128, scale: 16, frameCount: 1
        ))
    }

    // MARK: - Animated formats: per-frame edge fits, total bytes might not

    func testGIFAtLargeFrameCountAndScaleIsOverBudgetOnTotalBytes() {
        // 64 frames × 2048² × 4B = ~1 GB — past the 256 MB soft cap.
        XCTAssertTrue(ExportSizeBudget.isOverBudget(
            format: .gif, canvasEdge: 128, scale: 16, frameCount: 64
        ))
    }

    func testAPNGShortAnimationIsSafe() {
        // 4 frames × 128² × 4B = 256 KB. Fine.
        XCTAssertFalse(ExportSizeBudget.isOverBudget(
            format: .apng, canvasEdge: 32, scale: 4, frameCount: 4
        ))
    }

    // MARK: - Sprite sheet grid math mirrors SpriteSheetExporter

    /// From `SpriteSheetExporterTests`: 10 frames → 3 × 4 grid, 60 frames → 8 × 8.
    /// If this drifts from `SpriteSheetExporter`'s `columns = round(sqrt(N))` formula,
    /// the budget check will mis-predict the real output size.
    func testSpriteSheetGridMatchesExporterLayout() {
        let (c10, r10) = ExportSizeBudget.spriteSheetGrid(frameCount: 10)
        XCTAssertEqual(c10, 3)
        XCTAssertEqual(r10, 4)

        let (c60, r60) = ExportSizeBudget.spriteSheetGrid(frameCount: 60)
        XCTAssertEqual(c60, 8)
        XCTAssertEqual(r60, 8)
    }

    func testOutputDimensionsForSpriteSheet() {
        // 4 frames × 32 canvas × 1 scale: 2 × 2 grid = 64 × 64.
        let dims = ExportSizeBudget.outputDimensions(
            format: .spriteSheet, canvasEdge: 32, scale: 1, frameCount: 4
        )
        XCTAssertEqual(dims.width, 64)
        XCTAssertEqual(dims.height, 64)
    }

    func testOutputDimensionsForSingleFrameFormatsIgnoresFrameCount() {
        // PNG / GIF / APNG all share a single edge × edge worst-case context.
        for format in [ExportSizeBudget.Format.png, .gif, .apng] {
            let dims = ExportSizeBudget.outputDimensions(
                format: format, canvasEdge: 128, scale: 8, frameCount: 50
            )
            XCTAssertEqual(dims.width, 1024)
            XCTAssertEqual(dims.height, 1024)
        }
    }

    // MARK: - Edge cases

    func testZeroFrameCountIsTreatedAsSafe() {
        // Empty piece — the exporter would short-circuit to nil. Predicate must not crash.
        XCTAssertFalse(ExportSizeBudget.isOverBudget(
            format: .spriteSheet, canvasEdge: 128, scale: 16, frameCount: 0
        ))
    }
}
