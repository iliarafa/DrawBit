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
        let expectedByteCount = layers[0].pixels.count
        guard layers.dropFirst().allSatisfy({ $0.pixels.count == expectedByteCount }) else {
            throw DecodeError.malformed("inconsistent pixel byte counts across layers")
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

// MARK: - V2 Sequence format

extension FrameCodec {

    static let sequenceMagic: [UInt8] = Array("DBFS".utf8)
    static let sequenceCurrentVersion: UInt8 = 1
    static let defaultFPS: Int = 12

    static func hasV2SequenceMagicPrefix(_ data: Data) -> Bool {
        guard data.count >= sequenceMagic.count else { return false }
        return Array(data.prefix(sequenceMagic.count)) == sequenceMagic
    }

    static func encodeSequence(frames: [Frame], activeFrameIndex: Int, fps: Int) -> Data {
        precondition(!frames.isEmpty, "Sequence must hold at least one frame")
        precondition((0..<frames.count).contains(activeFrameIndex), "activeFrameIndex out of range")

        var out = Data()
        out.append(contentsOf: sequenceMagic)
        out.append(sequenceCurrentVersion)

        let count = UInt16(frames.count)
        out.append(UInt8((count >> 8) & 0xFF))
        out.append(UInt8(count & 0xFF))

        let active = UInt16(activeFrameIndex)
        out.append(UInt8((active >> 8) & 0xFF))
        out.append(UInt8(active & 0xFF))

        let fpsClamped = UInt16(max(1, min(120, fps)))
        out.append(UInt8((fpsClamped >> 8) & 0xFF))
        out.append(UInt8(fpsClamped & 0xFF))

        for frame in frames {
            appendUUID(frame.id, to: &out)

            let nameBytes = Array(frame.name.utf8.prefix(255))
            out.append(UInt8(nameBytes.count))
            out.append(contentsOf: nameBytes)

            let inner = FrameCodec.encode(frame)
            let innerLen = UInt32(inner.count)
            out.append(UInt8((innerLen >> 24) & 0xFF))
            out.append(UInt8((innerLen >> 16) & 0xFF))
            out.append(UInt8((innerLen >>  8) & 0xFF))
            out.append(UInt8( innerLen        & 0xFF))
            out.append(inner)
        }
        return out
    }

    static func decodeSequence(_ data: Data) throws
        -> (frames: [Frame], activeFrameIndex: Int, fps: Int)
    {
        if hasV1MagicPrefix(data) {
            // Legacy single-frame blob: decode via V1 and wrap.
            let frame = try decode(data)
            return ([frame], 0, defaultFPS)
        }
        guard hasV2SequenceMagicPrefix(data) else {
            throw DecodeError.badMagic
        }

        var cursor = sequenceMagic.count
        let bytes = [UInt8](data)

        func need(_ n: Int) throws {
            if cursor + n > bytes.count { throw DecodeError.truncated }
        }

        try need(1)
        let version = bytes[cursor]; cursor += 1
        guard version == sequenceCurrentVersion else {
            throw DecodeError.unsupportedVersion(version)
        }

        try need(2)
        let frameCount = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor + 1])
        cursor += 2

        try need(2)
        let activeIdxRaw = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor + 1])
        cursor += 2

        try need(2)
        let fps = (UInt16(bytes[cursor]) << 8) | UInt16(bytes[cursor + 1])
        cursor += 2

        var frames: [Frame] = []
        frames.reserveCapacity(Int(frameCount))

        for _ in 0..<Int(frameCount) {
            try need(16)
            let frameID = readUUID(bytes, at: cursor); cursor += 16

            try need(1)
            let nameLen = Int(bytes[cursor]); cursor += 1
            try need(nameLen)
            let name = String(bytes: bytes[cursor..<cursor + nameLen], encoding: .utf8) ?? "Frame"
            cursor += nameLen

            try need(4)
            let innerLen =
                (UInt32(bytes[cursor    ]) << 24) |
                (UInt32(bytes[cursor + 1]) << 16) |
                (UInt32(bytes[cursor + 2]) <<  8) |
                 UInt32(bytes[cursor + 3])
            cursor += 4
            try need(Int(innerLen))
            let innerData = Data(bytes[cursor..<cursor + Int(innerLen)])
            cursor += Int(innerLen)

            // Inner V1 blob is decoded; we then override id/name from the wrapper.
            let inner = try decode(innerData)
            frames.append(Frame(id: frameID,
                                name: name,
                                layers: inner.layers,
                                activeLayerID: inner.activeLayerID))
        }

        guard !frames.isEmpty else { throw DecodeError.malformed("zero frames") }
        let activeIndex = Int(activeIdxRaw)
        guard (0..<frames.count).contains(activeIndex) else {
            throw DecodeError.malformed("activeFrameIndex out of range")
        }
        let fpsRaw = Int(fps)
        let fpsValidated = fpsRaw == 0 ? defaultFPS : max(1, min(120, fpsRaw))
        return (frames, activeIndex, fpsValidated)
    }

    /// Decodes any persisted Piece blob into a frame sequence: V2 directly, V1 single-frame
    /// wrapped as a one-frame sequence, or pre-Layers-v2 raw RGBA bytes wrapped as one
    /// frame with one layer. The `fallbackByteCount` is used to construct an empty layer
    /// if the blob is too short to be raw bytes (defensive: returns a one-pixel-empty frame).
    static func decodeAnyFrameData(_ data: Data,
                                    fallbackByteCount: Int)
        -> (frames: [Frame], activeFrameIndex: Int, fps: Int)
    {
        if hasV2SequenceMagicPrefix(data),
           let result = try? decodeSequence(data) {
            return result
        }
        if hasV1MagicPrefix(data),
           let frame = try? decode(data) {
            return ([frame], 0, defaultFPS)
        }
        // Pre-Layers-v2 raw bytes path. If `data` doesn't match expected pixel byte count,
        // fall back to an empty frame at the requested size.
        let payload = data.count == fallbackByteCount ? data : Data(count: fallbackByteCount)
        let frame = wrapV1Data(payload, defaultName: "Layer 1")
        return ([frame], 0, defaultFPS)
    }

    /// Like `decodeAnyFrameData`, but a blob whose magic identifies it as V2 (or V1) yet fails to
    /// decode is treated as **corrupt** and the error is rethrown — instead of silently degrading
    /// to a blank frame that a subsequent save would make permanent (the silent-data-loss path).
    /// Only genuinely unrecognized raw/empty/legacy blobs keep the tolerant behavior; new pieces
    /// always carry valid V2 magic, so this never affects the happy path. Mirrors the safe fast
    /// path in `PieceRepository.loadFrames`. The editor opens through this, not `decodeAnyFrameData`.
    static func decodeForEditing(_ data: Data, fallbackByteCount: Int) throws
        -> (frames: [Frame], activeFrameIndex: Int, fps: Int)
    {
        if hasV2SequenceMagicPrefix(data) {
            return try decodeSequence(data)
        }
        if hasV1MagicPrefix(data) {
            return ([try decode(data)], 0, defaultFPS)
        }
        return decodeAnyFrameData(data, fallbackByteCount: fallbackByteCount)
    }
}
