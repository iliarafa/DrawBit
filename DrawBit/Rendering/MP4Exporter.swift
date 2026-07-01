import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// Encodes a list of composited RGBA keyframes into an H.264 `.mp4` time-lapse.
///
/// sRGB + nearest-neighbor throughout (matches every other export path). MP4 has
/// no alpha, so transparent pixels are painted onto an opaque `matte`. The final
/// frame is held for `holdLastSeconds` so the finished art lingers.
enum MP4Exporter {
    static let defaultMatte = RGBA(r: 26, g: 26, b: 26, a: 255)

    enum ExportError: Error { case badInput, setup, writeFailed }

    static func export(keyframes: [Data], size: CanvasSize, scale: Int, fps: Int,
                       matte: RGBA = defaultMatte, holdLastSeconds: Double = 1.2,
                       to url: URL) throws {
        guard !keyframes.isEmpty, scale >= 1, fps >= 1 else { throw ExportError.badInput }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw ExportError.setup }

        let artW = size.width * scale
        let artH = size.height * scale
        let outW = artW + (artW % 2)     // H.264 needs even dims
        let outH = artH + (artH % 2)

        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw ExportError.setup
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outW,
            AVVideoHeightKey: outH,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outW,
                kCVPixelBufferHeightKey as String: outH,
            ])
        guard writer.canAdd(input) else { throw ExportError.setup }
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.setup }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw ExportError.setup }

        // Presentation order: every keyframe once, then the last held.
        let hold = max(0, Int((holdLastSeconds * Double(fps)).rounded()))
        var order = Array(keyframes.indices)
        if let last = order.last { order.append(contentsOf: Array(repeating: last, count: hold)) }

        let timescale: CMTimeScale = 600
        for (present, kf) in order.enumerated() {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }

            guard let frameImage = composeFrame(rgba: keyframes[kf], size: size,
                                                artW: artW, artH: artH, outW: outW, outH: outH,
                                                matte: matte, colorSpace: colorSpace),
                  let pb = pixelBuffer(from: frameImage, outW: outW, outH: outH,
                                       pool: pool, colorSpace: colorSpace)
            else { throw ExportError.writeFailed }

            let t = CMTime(value: CMTimeValue(Double(present) / Double(fps) * Double(timescale)),
                           timescale: timescale)
            guard adaptor.append(pb, withPresentationTime: t) else { throw ExportError.writeFailed }
        }
        input.markAsFinished()
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()
        guard writer.status == .completed else { throw ExportError.writeFailed }
    }

    /// Matte-filled, nearest-neighbor-scaled frame as a CGImage (GIFExporter style).
    private static func composeFrame(rgba: Data, size: CanvasSize,
                                     artW: Int, artH: Int, outW: Int, outH: Int,
                                     matte: RGBA, colorSpace: CGColorSpace) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: outW, height: outH,
                                  bitsPerComponent: 8, bytesPerRow: outW * 4, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.setFillColor(red: CGFloat(matte.r) / 255, green: CGFloat(matte.g) / 255,
                         blue: CGFloat(matte.b) / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
        if let cg = bufferToCGImage(CompositedBuffer(data: rgba, size: size)) {
            ctx.draw(cg, in: CGRect(x: 0, y: outH - artH, width: artW, height: artH))
        }
        return ctx.makeImage()
    }

    /// Blit a CGImage into a pooled BGRA pixel buffer (no flip — CGContext(data:)
    /// is top-down here, matching CVPixelBuffer).
    private static func pixelBuffer(from image: CGImage, outW: Int, outH: Int,
                                    pool: CVPixelBufferPool, colorSpace: CGColorSpace) -> CVPixelBuffer? {
        var pbOut: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut) == kCVReturnSuccess,
              let pb = pbOut else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb),
              let ctx = CGContext(data: base, width: outW, height: outH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                            | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        return pb
    }
}
