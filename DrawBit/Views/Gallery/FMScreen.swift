import SwiftUI

/// The DrawBit FM destination — pushed onto the gallery `NavigationStack` from
/// the `FMTile`. Gives the station its own place to live: an identity strip
/// (wordmark + ON AIR badge + waveform), big transport with scrubbing, and a
/// tap-to-play track list. Reads the app-global `RadioController` from the
/// environment so playback continuity is preserved across navigation.
struct FMScreen: View {
    @Environment(RadioController.self) private var radio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 32) {
                    identityStrip
                    transportSection
                    trackList
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
        }
        .background(Color(white: 0.10).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // NB: don't attach `.accessibilityElement(children: .contain)` here —
        // wrapping the root collapses descendants in a way that hides Buttons
        // (e.g. the track rows) from XCUITest queries. Tests identify the
        // screen via unique children (`FM.playPause`, `FM.trackRow.0`).
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("GALLERY").font(.pixel(11))
                }
            }
            .foregroundStyle(.white)
            .accessibilityIdentifier("Gallery")

            Spacer()

            Text("DRAWBIT FM")
                .font(.pixel(12))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            // Visual balance with the leading "GALLERY" button so the title
            // sits truly centered. No action; just spacing.
            Color.clear.frame(width: 80, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    // MARK: - Identity strip

    private var identityStrip: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                onAirBadge
                Spacer()
                waveform
            }

            Text("DRAWBIT FM")
                .font(.pixel(28))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("FM.wordmark")

            Text("BUNDLED STATION • \(radio.tracks.count) TRACKS")
                .font(.pixel(8))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(white: 0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // ON-AIR badge with a blinking dot while playing. `.repeatForever` is gated
    // on `!UITestSupport.isRunning` so XCUITest's idle wait never wedges.
    private var onAirBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(radio.isPlaying ? Color.red : Color.white.opacity(0.3))
                .frame(width: 8, height: 8)
                .opacity(blinkOn ? 1 : 0.3)
                .animation(
                    radio.isPlaying && !UITestSupport.isRunning
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : nil,
                    value: blinkOn
                )
                .onAppear {
                    // Kick the animation off once so the .repeatForever has a
                    // value change to chew on.
                    if !UITestSupport.isRunning { blinkOn.toggle() }
                }
            Text(radio.isPlaying ? "ON AIR" : "OFF AIR")
                .font(.pixel(9))
                .foregroundStyle(.white.opacity(radio.isPlaying ? 0.9 : 0.4))
        }
        .accessibilityIdentifier("FM.onAirBadge")
    }

    @State private var blinkOn = false
    @State private var wavePulse = false

    // 4-bar animated waveform. Each bar's height drives off the same `wavePulse`
    // with a different scale mapping so they look phase-offset without needing
    // 4 separate timers. Frozen when not playing.
    private var waveform: some View {
        HStack(alignment: .bottom, spacing: 3) {
            waveBar(low: 0.30, high: 0.95)
            waveBar(low: 0.85, high: 0.40)
            waveBar(low: 0.50, high: 0.80)
            waveBar(low: 0.70, high: 0.25)
        }
        .frame(width: 36, height: 22)
        .onAppear {
            if !UITestSupport.isRunning { wavePulse.toggle() }
        }
        .accessibilityHidden(true)
    }

    private func waveBar(low: Double, high: Double) -> some View {
        let h: Double = radio.isPlaying ? (wavePulse ? high : low) : 0.35
        return Rectangle()
            .fill(Color.white.opacity(radio.isPlaying ? 0.9 : 0.3))
            .frame(width: 4, height: 22 * h)
            .animation(
                radio.isPlaying && !UITestSupport.isRunning
                    ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
                    : nil,
                value: wavePulse
            )
    }

    // MARK: - Transport

    private var transportSection: some View {
        VStack(spacing: 14) {
            // Current track title sits above the controls — larger than the
            // tile so the destination feels like the player's "home".
            Text(currentTrackTitle)
                .font(.pixel(12))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.white.opacity(radio.hasTracks ? 0.9 : 0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("FM.currentTitle")

            HStack(spacing: 18) {
                transportButton("backward.fill", "PREV",
                                id: "FM.previous", label: "Previous track",
                                size: 28) { radio.previous() }
                transportButton(radio.isPlaying ? "pause.fill" : "play.fill",
                                radio.isPlaying ? "PAUSE" : "PLAY",
                                id: "FM.playPause",
                                label: radio.isPlaying ? "Pause station" : "Play station",
                                size: 36) { radio.togglePlayPause() }
                transportButton("forward.fill", "NEXT",
                                id: "FM.next", label: "Next track",
                                size: 28) { radio.next() }
            }
            .frame(maxWidth: .infinity)

            ScrubBar(progress: radio.progress, enabled: radio.hasTracks) {
                radio.seek(toFraction: $0)
            }
        }
        .opacity(radio.hasTracks ? 1 : 0.5)
        .disabled(!radio.hasTracks)
    }

    private var currentTrackTitle: String {
        guard radio.hasTracks else { return "NO STATION" }
        return radio.currentTitle.isEmpty ? "—" : radio.currentTitle
    }

    private func transportButton(_ image: String, _ title: String,
                                 id: String, label: String, size: CGFloat,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: image).font(.system(size: size, weight: .regular))
                Text(title).font(.pixel(8)).lineLimit(1)
            }
            .frame(minWidth: 64, minHeight: 64)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }

    // MARK: - Track list

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRACKS")
                .font(.pixel(10))
                .foregroundStyle(.white.opacity(0.6))

            // NB: don't put an `accessibilityIdentifier` on this container —
            // SwiftUI propagates it to every descendant, clobbering the
            // per-row `FM.trackRow.<n>` ids below. (Same pitfall as the
            // historical `RadioStrip` container.)
            VStack(spacing: 0) {
                ForEach(Array(radio.tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(index: index, track: track)
                    if index < radio.tracks.count - 1 {
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                }
            }
            .background(Color(white: 0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if radio.tracks.isEmpty {
                Text("NO TRACKS BUNDLED")
                    .font(.pixel(8))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func trackRow(index: Int, track: AudioTrack) -> some View {
        let isCurrent = index == radio.currentIndex
        Button {
            radio.play(trackAt: index)
        } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", index + 1))
                    .font(.pixel(10))
                    .foregroundStyle(.white.opacity(isCurrent ? 0.9 : 0.4))
                    .frame(width: 30, alignment: .leading)
                Text(track.title)
                    .font(.pixel(10))
                    .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                marker(isCurrent: isCurrent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isCurrent ? Color.white.opacity(0.08) : Color.clear)
            // contentShape extends the hit (and accessibility) frame to the
            // full 44pt height even when the background is `.clear`. Without
            // this, non-current rows collapse to the size of their Text glyph
            // and XCUITest taps miss the row entirely.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("FM.trackRow.\(index)")
        .accessibilityLabel(track.title)
    }

    @ViewBuilder
    private func marker(isCurrent: Bool) -> some View {
        if isCurrent {
            Image(systemName: radio.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }
}
