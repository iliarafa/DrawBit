import XCTest
@testable import DrawBit

final class SingleFrameNonRegressionTests: XCTestCase {
    /// A single-frame piece must export byte-identical PNGs after a V2-sequence
    /// round-trip. The "before" reference is `PNGExporter.export(frame:)` called on
    /// a one-Frame `Frame` directly; the "after" goes through
    /// `FrameCodec.encodeSequence` → `decodeSequence` and exports the same way.
    /// The export path itself is unchanged, so any divergence here would mean
    /// the V2 codec is corrupting frame data.
    func testSingleFrameSingleLayerPNGByteIdentity() throws {
        for size in CanvasSize.allCases {
            for scale in [1, 2, 4, 8] {
                let pixels = Self.makeFixturePixels(size: size)
                let layer = Layer(name: "Layer 1", pixels: pixels)
                let frame = Frame(name: "Frame 1",
                                  layers: [layer],
                                  activeLayerID: layer.id)
                let direct = PNGExporter.export(frame: frame, size: size, scale: scale)

                // Round-trip through encode/decode V2 sequence — should produce identical pixels.
                let blob = FrameCodec.encodeSequence(frames: [frame],
                                                    activeFrameIndex: 0,
                                                    fps: 12)
                let (decoded, _, _) = try FrameCodec.decodeSequence(blob)
                let viaSequence = PNGExporter.export(frame: decoded[0], size: size, scale: scale)

                XCTAssertNotNil(direct)
                XCTAssertNotNil(viaSequence)
                XCTAssertEqual(direct, viaSequence,
                               "Single-frame PNG must be byte-identical pre/post sequence round-trip at \(size) ×\(scale)")
            }
        }
    }

    private static func makeFixturePixels(size: CanvasSize) -> Data {
        // Deterministic pseudo-random pattern — alpha exactly 0 or 255 to honor the invariant.
        var data = Data(count: size.byteCount)
        let edge = size.dimension
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for y in 0..<edge {
                for x in 0..<edge {
                    let i = (y * edge + x) * 4
                    let visible = ((x ^ y) & 0x07) != 0
                    p[i    ] = UInt8((x * 7) & 0xFF)
                    p[i + 1] = UInt8((y * 11) & 0xFF)
                    p[i + 2] = UInt8(((x + y) * 13) & 0xFF)
                    p[i + 3] = visible ? 255 : 0
                }
            }
        }
        return data
    }
}
