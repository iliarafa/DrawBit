import Foundation

struct CompositedBuffer: Equatable {
    let data: Data
    let size: CanvasSize
}

enum Compositor {
    /// Composites visible layers using a "topmost non-transparent pixel wins" rule. Output's
    /// alpha is always 0 or 255 — preserved by the no-opacity scope of the layers feature.
    static func composite(_ frame: Frame, size: CanvasSize) -> CompositedBuffer {
        let byteCount = size.byteCount
        var out = Data(count: byteCount)

        // Walk layers top→bottom, painting only into still-transparent positions.
        let visible = frame.layers.filter { $0.isVisible }
        out.withUnsafeMutableBytes { outRaw in
            let dst = outRaw.bindMemory(to: UInt8.self)
            for layer in visible.reversed() {
                layer.pixels.withUnsafeBytes { srcRaw in
                    let src = srcRaw.bindMemory(to: UInt8.self)
                    var i = 0
                    while i < byteCount {
                        // Only fill if dst pixel is still fully transparent AND src is opaque.
                        if dst[i + 3] == 0 && src[i + 3] == 255 {
                            dst[i    ] = src[i    ]
                            dst[i + 1] = src[i + 1]
                            dst[i + 2] = src[i + 2]
                            dst[i + 3] = 255
                        }
                        i += 4
                    }
                }
            }
        }
        return CompositedBuffer(data: out, size: size)
    }
}
