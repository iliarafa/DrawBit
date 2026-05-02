import Foundation

/// Versioned binary encoder/decoder for Frame.
///
/// Layout (big-endian where multibyte):
///   4  bytes   ASCII "DBFR" magic
///   1  byte    format version (currently 1)
///   2  bytes   layer count
///   16 bytes   active layer UUID
///   per layer:
///     16 bytes   layer UUID
///     1  byte    flags (bit 0 = visible, bit 1 = locked)
///     1  byte    name byte length (0..255)
///     N  bytes   name UTF-8
///     4  bytes   pixel byte count
///     N  bytes   raw RGBA pixel data
enum FrameCodec {
    static let magic: [UInt8] = Array("DBFR".utf8)
    static let currentVersion: UInt8 = 1

    enum DecodeError: Error {
        case badMagic
        case unsupportedVersion(UInt8)
        case truncated
        case malformed(String)
    }

    static func hasV1MagicPrefix(_ data: Data) -> Bool {
        guard data.count >= magic.count else { return false }
        return Array(data.prefix(magic.count)) == magic
    }

    static func wrapV1Data(_ pixels: Data, defaultName: String) -> Frame {
        let layer = Layer(name: defaultName, pixels: pixels)
        return Frame(layers: [layer], activeLayerID: layer.id)
    }

    static func encode(_ frame: Frame) -> Data {
        var out = Data()
        out.append(contentsOf: magic)
        out.append(currentVersion)

        let count = UInt16(frame.layers.count)
        out.append(UInt8((count >> 8) & 0xFF))
        out.append(UInt8(count & 0xFF))

        appendUUID(frame.activeLayerID, to: &out)

        for layer in frame.layers {
            appendUUID(layer.id, to: &out)
            var flags: UInt8 = 0
            if layer.isVisible { flags |= 0b0000_0001 }
            if layer.isLocked  { flags |= 0b0000_0010 }
            out.append(flags)

            let nameBytes = Array(layer.name.utf8.prefix(255))
            out.append(UInt8(nameBytes.count))
            out.append(contentsOf: nameBytes)

            let pixelLen = UInt32(layer.pixels.count)
            out.append(UInt8((pixelLen >> 24) & 0xFF))
            out.append(UInt8((pixelLen >> 16) & 0xFF))
            out.append(UInt8((pixelLen >>  8) & 0xFF))
            out.append(UInt8( pixelLen        & 0xFF))
            out.append(layer.pixels)
        }
        return out
    }

    static func decode(_ data: Data) throws -> Frame {
        var cursor = 0
        let bytes = [UInt8](data)

        func need(_ n: Int) throws {
            if cursor + n > bytes.count { throw DecodeError.truncated }
        }

        try need(magic.count)
        guard Array(bytes[cursor..<cursor+magic.count]) == magic else { throw DecodeError.badMagic }
        cursor += magic.count

        try need(1)
        let version = bytes[cursor]; cursor += 1
        guard version == currentVersion else { throw DecodeError.unsupportedVersion(version) }

        try need(2)
        let layerCount = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor+1])
        cursor += 2

        try need(16)
        let activeID = readUUID(bytes, at: cursor)
        cursor += 16

        var layers: [Layer] = []
        layers.reserveCapacity(Int(layerCount))

        for _ in 0..<Int(layerCount) {
            try need(16)
            let layerID = readUUID(bytes, at: cursor); cursor += 16

            try need(1)
            let flags = bytes[cursor]; cursor += 1
            let isVisible = (flags & 0b0000_0001) != 0
            let isLocked  = (flags & 0b0000_0010) != 0

            try need(1)
            let nameLen = Int(bytes[cursor]); cursor += 1
            try need(nameLen)
            let name = String(bytes: bytes[cursor..<cursor+nameLen], encoding: .utf8) ?? ""
            cursor += nameLen

            try need(4)
            let pixelLen =
                (UInt32(bytes[cursor    ]) << 24) |
                (UInt32(bytes[cursor + 1]) << 16) |
                (UInt32(bytes[cursor + 2]) <<  8) |
                 UInt32(bytes[cursor + 3])
            cursor += 4

            try need(Int(pixelLen))
            let pixels = Data(bytes[cursor..<cursor+Int(pixelLen)])
            cursor += Int(pixelLen)

            layers.append(Layer(id: layerID, name: name, pixels: pixels, isVisible: isVisible, isLocked: isLocked))
        }

        guard !layers.isEmpty else { throw DecodeError.malformed("zero layers") }
        guard layers.contains(where: { $0.id == activeID }) else {
            throw DecodeError.malformed("activeID does not match any layer")
        }
        return Frame(layers: layers, activeLayerID: activeID)
    }

    private static func appendUUID(_ id: UUID, to out: inout Data) {
        let t = id.uuid
        out.append(contentsOf: [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7,
                                t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15])
    }

    private static func readUUID(_ bytes: [UInt8], at offset: Int) -> UUID {
        let t: uuid_t = (
            bytes[offset    ], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3],
            bytes[offset + 4], bytes[offset + 5], bytes[offset + 6], bytes[offset + 7],
            bytes[offset + 8], bytes[offset + 9], bytes[offset + 10], bytes[offset + 11],
            bytes[offset + 12], bytes[offset + 13], bytes[offset + 14], bytes[offset + 15]
        )
        return UUID(uuid: t)
    }
}
