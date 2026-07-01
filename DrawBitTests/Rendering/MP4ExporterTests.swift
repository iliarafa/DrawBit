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
        XCTAssertEqual(Int(px.r), 26, accuracy: 18)
        XCTAssertEqual(Int(px.g), 26, accuracy: 18)
        XCTAssertEqual(Int(px.b), 26, accuracy: 18)
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
