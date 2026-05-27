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

            // Layout sizing notes: the tile is 120pt square. After 10pt
            // padding on each side, ~100pt of usable width remains, and the
            // 44pt play/pause hit target leaves ~50pt for the title column.
            // Pixel fonts are roughly 1ch ≈ 1pt at the named size, so the
            // wordmark at pixel(8) ("DRAWBIT FM" ≈ 80pt) sits on one line
            // alongside a small radio glyph, and titles up to ~7 characters
            // (pixel(7)) fit on one line beside the play button. Longer
            // titles wrap cleanly to two lines.
            VStack(alignment: .leading, spacing: 0) {
                // Header: small radio-wave glyph + wordmark on one line.
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 9, weight: .regular))
                    Text("DRAWBIT FM").font(.pixel(8))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)

                Spacer(minLength: 0)

                // Footer: just the current track title + inline play/pause.
                // The "NOW PLAYING" label is redundant on a tile that
                // literally is the FM station, so it's dropped to give the
                // title room to render without truncating.
                HStack(alignment: .bottom, spacing: 4) {
                    Text(titleText)
                        .font(.pixel(7))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundStyle(.white.opacity(radio.hasTracks ? 0.85 : 0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("FM.tile.title")
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
                .font(.system(size: 14, weight: .regular))
                .frame(width: 44, height: 44)
                .foregroundStyle(.white.opacity(radio.hasTracks ? 1 : 0.3))
        }
        .buttonStyle(.plain)
        .disabled(!radio.hasTracks)
        .accessibilityIdentifier("FM.tile.playPause")
        .accessibilityLabel(radio.isPlaying ? "Pause station" : "Play station")
    }
}
