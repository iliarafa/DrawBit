import SwiftUI

/// The "DRAWBIT FM" player strip shown under the GALLERY header. Reads the
/// app-global ``RadioController`` from the environment. Styled to match the
/// editor toolbar (pixel font, monochrome, 44pt hit targets, group dividers).
struct RadioStrip: View {
    @Environment(RadioController.self) private var radio

    var body: some View {
        VStack(spacing: 4) {
            header
            controls
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.09))
        .overlay(alignment: .top) {
            Divider().overlay(Color.white.opacity(0.08))
        }
        // NB: don't put an accessibilityIdentifier on this container — SwiftUI
        // propagates it to every descendant, clobbering the per-control ids below.
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .regular))
            Text("DRAWBIT FM").font(.pixel(11))
            Spacer()
        }
        .foregroundStyle(.white)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            transportButton("backward.fill", "PREV",
                            id: "RadioStrip.previous", label: "Previous track") { radio.previous() }
            transportButton(radio.isPlaying ? "pause.fill" : "play.fill",
                            radio.isPlaying ? "PAUSE" : "PLAY",
                            id: "RadioStrip.playPause",
                            label: radio.isPlaying ? "Pause station" : "Play station") { radio.togglePlayPause() }
            transportButton("forward.fill", "NEXT",
                            id: "RadioStrip.next", label: "Next track") { radio.next() }

            Divider().frame(height: 36).overlay(Color.white.opacity(0.15))

            VStack(alignment: .leading, spacing: 5) {
                Text(titleText)
                    .font(.pixel(8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white.opacity(radio.hasTracks ? 0.85 : 0.4))
                    .accessibilityIdentifier("RadioStrip.title")
                ScrubBar(progress: radio.progress, enabled: radio.hasTracks) { radio.seek(toFraction: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(radio.hasTracks ? 1 : 0.5)
        .disabled(!radio.hasTracks)
    }

    private var titleText: String {
        guard radio.hasTracks else { return "NO STATION" }
        return radio.currentTitle.isEmpty ? "—" : radio.currentTitle
    }

    private func transportButton(_ image: String, _ title: String,
                                 id: String, label: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: image).font(.system(size: 20, weight: .regular))
                Text(title).font(.pixel(8)).lineLimit(1)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }
}

/// Thin pixel-styled seek bar: a track with a filled portion and a square thumb.
/// While dragging it follows the finger and reports the final fraction on release.
private struct ScrubBar: View {
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
        .accessibilityIdentifier("RadioStrip.scrubber")
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
