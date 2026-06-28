import XCTest
@testable import DrawBit

/// `LineTool.apply` stamps a straight pixel line onto a COPY of a baseline buffer — the operation
/// behind the pencil's "hold to straighten." Because it always starts from `base`, re-aiming the
/// line is just "recompute from the pre-stroke snapshot," and these tests pin that purity.
final class LineToolTests: XCTestCase {
    private let size = CanvasSize(8)               // 8×8
    private let red = RGBA(r: 255, g: 0, b: 0, a: 255)

    private func blank() -> Data { Data(count: size.byteCount) }
    private func isSet(_ data: Data, _ x: Int, _ y: Int) -> Bool {
        PixelGrid(data: data, size: size).pixel(x: x, y: y) != .transparent
    }

    func testHorizontalLine() {
        let out = LineTool.apply(to: blank(), size: size, from: (1, 2), to: (5, 2), color: red, mirror: false)
        for x in 1...5 { XCTAssertEqual(PixelGrid(data: out, size: size).pixel(x: x, y: 2), red) }
        XCTAssertFalse(isSet(out, 0, 2))
        XCTAssertFalse(isSet(out, 6, 2))
        XCTAssertFalse(isSet(out, 3, 3))
    }

    func testVerticalLine() {
        let out = LineTool.apply(to: blank(), size: size, from: (3, 1), to: (3, 6), color: red, mirror: false)
        for y in 1...6 { XCTAssertTrue(isSet(out, 3, y)) }
        XCTAssertFalse(isSet(out, 3, 0))
        XCTAssertFalse(isSet(out, 3, 7))
    }

    func testDiagonalMatchesBresenham() {
        let out = LineTool.apply(to: blank(), size: size, from: (0, 0), to: (4, 4), color: red, mirror: false)
        for p in bresenhamLine(from: (0, 0), to: (4, 4)) { XCTAssertTrue(isSet(out, p.0, p.1)) }
    }

    /// Starts from `base`: a pixel that isn't on the line must survive (this is what makes re-aim a
    /// clean restore — the freehand wobble, captured in the snapshot, is what gets replaced).
    func testRestoresFromBaseOffLinePixelsSurvive() {
        var g = PixelGrid(data: blank(), size: size)
        let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
        g.setPixel(x: 7, y: 7, color: blue)
        let out = LineTool.apply(to: g.data, size: size, from: (0, 0), to: (3, 0), color: red, mirror: false)
        XCTAssertEqual(PixelGrid(data: out, size: size).pixel(x: 7, y: 7), blue)
        XCTAssertTrue(isSet(out, 0, 0))
    }

    /// Pure: two applies from the same base don't accumulate — the second sees only its own line.
    func testApplyIsPureNotCumulative() {
        let base = blank()
        _ = LineTool.apply(to: base, size: size, from: (0, 0), to: (5, 0), color: red, mirror: false)
        let out2 = LineTool.apply(to: base, size: size, from: (0, 5), to: (3, 5), color: red, mirror: false)
        XCTAssertFalse(isSet(out2, 5, 0))
        XCTAssertTrue(isSet(out2, 0, 5))
    }

    /// Mirror reflects across the vertical centerline: on width 8, x → 7−x.
    func testMirrorReflectsAcrossVerticalCenter() {
        let out = LineTool.apply(to: blank(), size: size, from: (1, 1), to: (1, 4), color: red, mirror: true)
        for y in 1...4 {
            XCTAssertTrue(isSet(out, 1, y), "primary column")
            XCTAssertTrue(isSet(out, 6, y), "mirrored column")
        }
    }

    func testEndpointEqualsAnchorPaintsSingleDot() {
        let out = LineTool.apply(to: blank(), size: size, from: (2, 2), to: (2, 2), color: red, mirror: false)
        XCTAssertTrue(isSet(out, 2, 2))
        XCTAssertFalse(isSet(out, 3, 2))
    }

    // MARK: - isPerfectAngle (hold-to-straighten detent)

    func testPerfectHorizontal() {
        XCTAssertTrue(LineTool.isPerfectAngle(from: (1, 4), to: (9, 4)))
        XCTAssertTrue(LineTool.isPerfectAngle(from: (9, 4), to: (1, 4)))   // direction-agnostic
    }

    func testPerfectVertical() {
        XCTAssertTrue(LineTool.isPerfectAngle(from: (3, 1), to: (3, 8)))
    }

    func testPerfect45Degrees() {
        XCTAssertTrue(LineTool.isPerfectAngle(from: (0, 0), to: (5, 5)))
        XCTAssertTrue(LineTool.isPerfectAngle(from: (5, 5), to: (0, 0)))   // negative deltas via abs
        XCTAssertTrue(LineTool.isPerfectAngle(from: (5, 0), to: (0, 5)))   // other diagonal
    }

    func testJaggedAnglesAreNotPerfect() {
        XCTAssertFalse(LineTool.isPerfectAngle(from: (0, 0), to: (5, 2)))
        XCTAssertFalse(LineTool.isPerfectAngle(from: (0, 0), to: (5, 3)))
        XCTAssertFalse(LineTool.isPerfectAngle(from: (0, 0), to: (2, 1)))  // 2:1 iso is NOT in the v1 set
    }

    func testZeroLengthIsNotPerfect() {
        XCTAssertFalse(LineTool.isPerfectAngle(from: (4, 4), to: (4, 4)))
    }
}
