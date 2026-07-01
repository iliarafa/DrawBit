import Foundation

/// The growing list of compressed canvas keyframes for one drawing's time-lapse.
/// Value type; pure. Storage/compression happen outside (KeyframeCodec) — this
/// only owns the accumulation rules.
struct TimelapseRecording {
    private(set) var frames: [Data]

    init(frames: [Data] = []) { self.frames = frames }

    /// Append a compressed keyframe. Skips a no-op step (identical to the last
    /// frame). When the list exceeds the cap it halves by keeping every other
    /// frame — even coverage across the WHOLE session, both ends preserved
    /// (the cap is even so the trigger count is odd and `stride(by: 2)` includes
    /// the final index).
    mutating func append(_ blob: Data) {
        if blob == frames.last { return }
        frames.append(blob)
        if frames.count > Timelapse.maxStoredKeyframes {
            frames = stride(from: 0, to: frames.count, by: 2).map { frames[$0] }
        }
    }
}
