import SwiftUI
import UIKit

struct PieceThumbnailView: View {
    let piece: Piece

    var body: some View {
        ZStack {
            CheckerboardView()
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
        .accessibilityIdentifier("PieceThumbnail")
    }

    private var thumbnailImage: UIImage? {
        guard !piece.thumbnail.isEmpty else { return nil }
        return UIImage(data: piece.thumbnail)
    }
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
