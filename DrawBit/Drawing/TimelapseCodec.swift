import Foundation

/// Binary container for a time-lapse recording (a list of already-zlib-compressed
/// keyframe blobs). Mirrors FrameCodec's style.
///
/// Layout (big-endian):
///   4 bytes  ASCII "DBTL" magic
///   1 byte   version (1)
///   4 bytes  frame count (UInt32)
///   per frame: 4 bytes blob length (UInt32) + N bytes blob
enum TimelapseCodec {
    static let magic: [UInt8] = Array("DBTL".utf8)
    static let version: UInt8 = 1

    static func encode(_ frames: [Data]) -> Data {
        var out = Data()
        out.append(contentsOf: magic)
        out.append(version)
        appendU32(UInt32(frames.count), to: &out)
        for f in frames {
            appendU32(UInt32(f.count), to: &out)
            out.append(f)
        }
        return out
    }

    static func decode(_ data: Data) -> [Data]? {
        var i = data.startIndex
        func remaining() -> Int { data.endIndex - i }
        guard remaining() >= magic.count + 1 + 4 else { return nil }
        guard Array(data[i..<i + magic.count]) == magic else { return nil }
        i += magic.count
        guard data[i] == version else { return nil }
        i += 1
        let count = readU32(data, &i)
        var frames: [Data] = []
        frames.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard remaining() >= 4 else { return nil }
            let len = Int(readU32(data, &i))
            guard remaining() >= len else { return nil }
            frames.append(data.subdata(in: i..<i + len))
            i += len
        }
        return frames
    }

    private static func appendU32(_ v: UInt32, to out: inout Data) {
        out.append(UInt8((v >> 24) & 0xFF)); out.append(UInt8((v >> 16) & 0xFF))
        out.append(UInt8((v >> 8) & 0xFF));  out.append(UInt8(v & 0xFF))
    }

    private static func readU32(_ data: Data, _ i: inout Data.Index) -> UInt32 {
        let v = (UInt32(data[i]) << 24) | (UInt32(data[i + 1]) << 16)
              | (UInt32(data[i + 2]) << 8) | UInt32(data[i + 3])
        i += 4
        return v
    }
}
