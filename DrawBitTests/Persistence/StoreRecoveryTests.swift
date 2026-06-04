import XCTest
@testable import DrawBit

final class StoreRecoveryTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMovesStoreAndSidecarsAsidePreservingContent() throws {
        let store = dir.appendingPathComponent("default.store")
        let payloads: [String: Data] = [
            "": Data("main".utf8),
            "-shm": Data("shm".utf8),
            "-wal": Data("wal".utf8),
        ]
        for (suffix, data) in payloads {
            try data.write(to: store.appendingToFileName(suffix))
        }

        let moved = StoreRecovery.moveStoreAside(at: store, now: Date(timeIntervalSince1970: 42))
        XCTAssertEqual(moved.count, 3)

        // Originals are gone…
        for suffix in StoreRecovery.sidecarSuffixes {
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.appendingToFileName(suffix).path),
                           "original \(suffix.isEmpty ? "store" : suffix) should have moved")
        }
        // …and the quarantined copies hold the original bytes.
        for (suffix, data) in payloads {
            let q = store.appendingToFileName(".quarantine-42\(suffix)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: q.path))
            XCTAssertEqual(try Data(contentsOf: q), data)
        }
    }

    func testNoFilesIsNoOp() {
        let store = dir.appendingPathComponent("default.store")
        let moved = StoreRecovery.moveStoreAside(at: store, now: Date(timeIntervalSince1970: 1))
        XCTAssertTrue(moved.isEmpty)
    }

    func testAppendingToFileName() {
        let base = URL(fileURLWithPath: "/tmp/foo.store")
        XCTAssertEqual(base.appendingToFileName("").path, "/tmp/foo.store")
        XCTAssertEqual(base.appendingToFileName("-wal").path, "/tmp/foo.store-wal")
    }
}
