import XCTest
@testable import DrawBit

final class BresenhamLineTests: XCTestCase {
    func testSinglePoint() {
        assertLine(bresenhamLine(from: (3, 4), to: (3, 4)), [(3, 4)])
    }

    func testHorizontal() {
        assertLine(
            bresenhamLine(from: (0, 0), to: (3, 0)),
            [(0, 0), (1, 0), (2, 0), (3, 0)]
        )
    }

    func testVertical() {
        assertLine(
            bresenhamLine(from: (0, 0), to: (0, 3)),
            [(0, 0), (0, 1), (0, 2), (0, 3)]
        )
    }

    func testDiagonal() {
        assertLine(
            bresenhamLine(from: (0, 0), to: (3, 3)),
            [(0, 0), (1, 1), (2, 2), (3, 3)]
        )
    }

    func testReverseDirection() {
        assertLine(
            bresenhamLine(from: (3, 3), to: (0, 0)),
            [(3, 3), (2, 2), (1, 1), (0, 0)]
        )
    }

    func testSteepLineHasNoGaps() {
        let pts = bresenhamLine(from: (0, 0), to: (2, 10))
        let ys = Set(pts.map(\.1))
        XCTAssertEqual(ys, Set(0...10))
    }

    private func assertLine(_ lhs: [(Int, Int)], _ rhs: [(Int, Int)], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for (a, b) in zip(lhs, rhs) {
            XCTAssertEqual(a.0, b.0, file: file, line: line)
            XCTAssertEqual(a.1, b.1, file: file, line: line)
        }
    }
}
