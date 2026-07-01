import Foundation

/// Lossless zlib (de)compression for a single composited RGBA canvas buffer.
/// Pixel art is mostly flat runs, so zlib shrinks a canvas to a few KB while
/// staying bit-exact — the time-lapse must never blur a pixel.
enum KeyframeCodec {
    static func compress(_ rgba: Data) -> Data? {
        try? (rgba as NSData).compressed(using: .zlib) as Data
    }

    static func decompress(_ blob: Data) -> Data? {
        try? (blob as NSData).decompressed(using: .zlib) as Data
    }
}
