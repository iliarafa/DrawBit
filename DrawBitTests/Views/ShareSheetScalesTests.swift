import XCTest
@testable import DrawBit

/// `ShareSheet`'s scale picker offers a fixed set of output sizes regardless of
/// canvas — the multiplier slides to compensate. This is what every dedicated
/// pixel-art app ships (see Pixaki's user-guide note on nearest-neighbour
/// magnification) because iOS Photos / social platforms apply bilinear smoothing
/// to anything they render at non-1:1, so a 256 px export looks mushy even when
/// the file bytes are mathematically pixel-perfect. The cure is bigger pixels,
/// not better pixels — these tests pin the contract.
final class ShareSheetScalesTests: XCTestCase {

    private let allCanvasSizes: [CanvasSize] = [.s16, .s32, .s64, .s128]

    // MARK: - Picker shape

    /// The UI is a five-column LazyVGrid — if the array drifts off five items the
    /// last row wraps awkwardly. Pin the count here so the grid stays balanced.
    func testEachCanvasOffersFiveScales() {
        for size in allCanvasSizes {
            XCTAssertEqual(
                ShareSheet.scales(for: size).count, 5,
                "Canvas \(size.dimension): expected 5 scale tiles, got \(ShareSheet.scales(for: size))"
            )
        }
    }

    func testScalesAreSortedAscending() {
        for size in allCanvasSizes {
            let s = ShareSheet.scales(for: size)
            XCTAssertEqual(s, s.sorted(),
                "Canvas \(size.dimension): scales must be ascending; got \(s)")
        }
    }

    // MARK: - Uniform output edges

    /// Every canvas should produce the same five output edges. Users pick an
    /// *output size*; we just spell it as a magnification number to keep the
    /// math integer (each source pixel becomes an exact N×N block on output).
    func testScalesProduceUniformOutputEdgesAcrossCanvases() {
        let expected = [128, 256, 512, 1024, 2048]
        for size in allCanvasSizes {
            let edges = ShareSheet.scales(for: size).map { $0 * size.dimension }
            XCTAssertEqual(edges, expected,
                "Canvas \(size.dimension): output edges \(edges) ≠ expected \(expected)")
        }
    }

    // MARK: - Default scale

    /// The selected-on-open tile must be one of the offered tiles — otherwise
    /// nothing reads as selected (or worse, the wrong tile does).
    func testDefaultScaleIsAmongOfferedScales() {
        for size in allCanvasSizes {
            let scales = ShareSheet.scales(for: size)
            let def = ShareSheet.defaultScale(for: size)
            XCTAssertTrue(scales.contains(def),
                "Canvas \(size.dimension): default \(def)× not in \(scales)")
        }
    }

    /// 1024 px is the community-accepted minimum that survives iOS Photos'
    /// bilinear preview smoothing. Smaller defaults make the preview look soft
    /// even though the file is correct — that's the bug this change fixes.
    func testDefaultProducesAtLeast1024pxOutput() {
        for size in allCanvasSizes {
            let edge = ShareSheet.defaultScale(for: size) * size.dimension
            XCTAssertGreaterThanOrEqual(edge, 1024,
                "Canvas \(size.dimension): default output edge \(edge) px is under the 1024 px target")
        }
    }
}
