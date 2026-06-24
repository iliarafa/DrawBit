import Foundation

struct RGBA: Equatable, Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    static let transparent = RGBA(r: 0, g: 0, b: 0, a: 0)
}

struct PixelGrid: Equatable {
    private(set) var data: Data
    let size: CanvasSize

    init(size: CanvasSize) {
        self.size = size
        self.data = Data(count: size.byteCount)
    }

    init(data: Data, size: CanvasSize) {
        precondition(data.count == size.byteCount, "data length must equal size.byteCount")
        // Defensive copy: normalizes start-index so data[0] always points at the first byte.
        // A sliced Data would otherwise trap on data[0] or hand the wrong bytes to CGDataProvider.
        self.data = Data(data)
        self.size = size
    }

    /// Square-only back-compat alias (== `width`). Non-square callers must use width/height.
    var dimension: Int { size.dimension }
    var width: Int { size.width }
    var height: Int { size.height }

    func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    func pixel(x: Int, y: Int) -> RGBA {
        guard contains(x: x, y: y) else { return .transparent }
        let i = (y * width + x) * 4
        return RGBA(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3])
    }

    mutating func setPixel(x: Int, y: Int, color: RGBA) {
        guard contains(x: x, y: y) else { return }
        let i = (y * width + x) * 4
        data[i] = color.r
        data[i + 1] = color.g
        data[i + 2] = color.b
        data[i + 3] = color.a
    }
}
