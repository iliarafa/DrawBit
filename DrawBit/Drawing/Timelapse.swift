import Foundation

/// Shared constants + the even-downsample used by both the export preview and
/// the MP4 encoder. Pure; no UI, no persistence.
enum Timelapse {
    /// Cap on stored keyframes. Even, so the "> cap" thin trigger lands on an odd
    /// count and `stride(by: 2)` keeps BOTH ends. See `TimelapseRecording`.
    static let maxStoredKeyframes = 240
    /// Max frames in an exported clip (before the held tail). 120 @ 24fps ≈ 5s.
    static let targetClipFrames = 120
    /// Playback rate of the exported clip.
    static let clipFPS = 24

    /// Evenly pick at most `target` items across `items`, always preserving the
    /// first and last. Passthrough when already small enough. Order preserved.
    static func sample<T>(_ items: [T], to target: Int) -> [T] {
        guard target >= 1 else { return [] }
        guard items.count > target else { return items }
        if target == 1 { return [items[0]] }
        let n = items.count
        return (0..<target).map { i in
            let idx = Int((Double(i) * Double(n - 1) / Double(target - 1)).rounded())
            return items[idx]
        }
    }
}
