import SwiftUI
import UIKit

struct PieceThumbnailView: View {
    let piece: Piece

    var body: some View {
        ZStack {
            Color(white: 0.10)
            Canvas { ctx, size in
                // Confine the gridlines to the aspect-fit art region so a non-square
                // piece letterboxes with pure dark bands (no grid in the bands).
                let cw = piece.size.width
                let ch = piece.size.height
                let s = min(size.width / CGFloat(cw), size.height / CGFloat(ch))
                let aw = CGFloat(cw) * s
                let ah = CGFloat(ch) * s
                let ox = (size.width - aw) / 2
                let oy = (size.height - ah) / 2
                let cell = aw / CGFloat(cw)
                var path = Path()
                for i in 0...cw {
                    let x = ox + CGFloat(i) * cell
                    path.move(to: CGPoint(x: x, y: oy)); path.addLine(to: CGPoint(x: x, y: oy + ah))
                }
                for j in 0...ch {
                    let y = oy + CGFloat(j) * cell
                    path.move(to: CGPoint(x: ox, y: y)); path.addLine(to: CGPoint(x: ox + aw, y: y))
                }
                ctx.stroke(path, with: .color(Color(white: 0.22)), lineWidth: 0.5)
            }
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
        .galleryTileLift()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("PieceThumbnail")
    }

    private var thumbnailImage: UIImage? {
        guard !piece.thumbnail.isEmpty else { return nil }
        return UIImage(data: piece.thumbnail)
    }
}

struct NewPieceTile: View {
    var body: some View {
        ZStack {
            Color(white: 0.14)
            PixelArtIcon(pattern: NewPieceTile.plusPattern, size: 56)
                .foregroundStyle(.white.opacity(0.5))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
        .galleryTileLift()
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
    }

    static let plusPattern: [String] = [
        "....#....",
        "....#....",
        "....#....",
        "....#....",
        "#########",
        "....#....",
        "....#....",
        "....#....",
        "....#....",
    ]
}

struct CheckerboardView: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 8
            for y in stride(from: 0, to: size.height, by: tile) {
                for x in stride(from: 0, to: size.width, by: tile) {
                    let isDark = (Int(x / tile) + Int(y / tile)) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: tile, height: tile)),
                        with: .color(isDark ? Color(white: 0.88) : Color.white)
                    )
                }
            }
        }
    }
}
