import SwiftUI

/// Hero card for the DrawBit FM station, slotted as the first cell in the
/// `GalleryView` grid (before the piece thumbnails). Same square footprint and
/// 6pt corner radius as `PieceThumbnailView`, but a distinct treatment: pixel
/// wordmark up top, current track title at the bottom-left, an inline 44pt
/// play/pause button at the bottom-right.
///
/// Tapping the tile body opens the full FM destination (`FMScreen`). The
/// inline play/pause button captures its own taps so it pauses in place
/// without triggering navigation.
struct FMTile: View {
    @Environment(RadioController.self) private var radio

    var body: some View {
        ZStack {
            Color(white: 0.09)

            VStack(alignment: .leading, spacing: 0) {
                // Header: radio-wave glyph + wordmark
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .regular))
                    Text("DRAWBIT FM").font(.pixel(11))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)

                Spacer(minLength: 0)

                // Footer: now-playing + inline play/pause
                HStack(alignment: .bottom, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NOW PLAYING")
                            .font(.pixel(7))
                            .foregroundStyle(.white.opacity(0.4))
                        Text(titleText)
                            .font(.pixel(8))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .foregroundStyle(.white.opacity(radio.hasTracks ? 0.85 : 0.4))
                            .accessibilityIdentifier("FM.tile.title")
                    }
                    Spacer(minLength: 0)
                    playPauseButton
                }
            }
            .padding(10)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        // NB: don't collapse the tile into a single accessibility element with
        // `.contain` here — it interferes with the parent `.onTapGesture` set
        // by `GalleryView` for navigation. Each child (`FM.tile.title`,
        // `FM.tile.playPause`) remains individually queryable, and the parent
        // is matched in tests via a unique child or the resulting `FMScreen`.
    }

    private var titleText: String {
        guard radio.hasTracks else { return "NO STATION" }
        return radio.currentTitle.isEmpty ? "—" : radio.currentTitle
    }

    /// Inline play/pause. `.buttonStyle(.plain)` + a `Button` inside the tile
    /// captures taps inside its frame, so a tap here doesn't bubble to the
    /// tile's outer `onTapGesture` (set on `GalleryView`'s side) and won't
    /// open the FM destination.
    private var playPauseButton: some View {
        Button {
            radio.togglePlayPause()
        } label: {
            Image(systemName: radio.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .regular))
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(.white.opacity(radio.hasTracks ? 1 : 0.3))
        }
        .buttonStyle(.plain)
        .disabled(!radio.hasTracks)
        .accessibilityIdentifier("FM.tile.playPause")
        .accessibilityLabel(radio.isPlaying ? "Pause station" : "Play station")
    }
}
