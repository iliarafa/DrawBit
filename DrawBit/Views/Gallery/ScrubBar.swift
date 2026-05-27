import SwiftUI

/// Thin pixel-styled seek bar: a track with a filled portion and a square thumb.
/// While dragging it follows the finger and reports the final fraction on release.
///
/// Used by `FMScreen` (and previously `RadioStrip`) to scrub the current track.
/// Lives outside any one view because both compact and full FM surfaces want it.
struct ScrubBar: View {
    let progress: Double          // 0...1 from the controller
    let enabled: Bool
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        let shown = clamp(dragFraction ?? progress)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.15)).frame(height: 4)
                Rectangle().fill(Color.white.opacity(enabled ? 0.85 : 0.25))
                    .frame(width: shown * w, height: 4)
                Rectangle().fill(Color.white.opacity(enabled ? 1 : 0.25))
                    .frame(width: 8, height: 12)
                    .offset(x: shown * w - 4)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard enabled, w > 0 else { return }
                        dragFraction = clamp(v.location.x / w)
                    }
                    .onEnded { v in
                        guard enabled, w > 0 else { return }
                        let f = clamp(v.location.x / w)
                        onSeek(f)
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityIdentifier("FM.scrubber")
        .accessibilityLabel("Track position")
        .accessibilityValue("\(Int(shown * 100)) percent")
        .accessibilityAdjustableAction { dir in
            guard enabled else { return }
            let step = 0.05
            let base = dragFraction ?? progress
            onSeek(clamp(dir == .increment ? base + step : base - step))
        }
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
