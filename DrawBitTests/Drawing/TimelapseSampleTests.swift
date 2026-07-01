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
