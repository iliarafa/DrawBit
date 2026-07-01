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
