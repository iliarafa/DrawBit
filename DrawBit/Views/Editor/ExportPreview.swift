import SwiftUI

/// The hero preview in the export sheet. Shows exactly what the selected format will produce:
/// PNG → the active frame (static); GIF/APNG → all frames looped at the piece's fps;
/// Sprite → the frames laid out in the exporter's grid. Nearest-neighbor throughout, on a
/// checkerboard backdrop so transparency reads.
struct ExportPreview: View {
    let frames: [Frame]
    let activeIndex: Int
    let size: CanvasSize
    let fps: Int
    let format: ShareSheet.ExportFormat
    /// Output edge (px) of the currently-selected scale — shown in the badge.
    let outputEdge: Int

    /// Cached nearest-neighbor renders of every frame (built once; reused by all modes).
    @State private var images: [CGImage] = []

    private var isAnimated: Bool { format == .gif || format == .apng }
    private var safeFPS: Int { max(1, fps) }

    var body: some View {
        ZStack {
            checkerboard
            content
            badge
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        .task(id: frames.count) { renderImages() }
        .accessibilityIdentifier("ExportPreview")
    }

    @ViewBuilder
    private var content: some View {
        if images.isEmpty {
            EmptyView()
        } else if format == .spriteSheet {
            spriteGrid
        } else if isAnimated && images.count > 1 && !UITestSupport.isRunning {
            // Stateless loop: derive the frame index from wall-clock so there's no Timer to manage.
            // Gated off under UI test — a live periodic timeline never lets XCUITest reach idle.
            TimelineView(.periodic(from: .now, by: 1.0 / Double(safeFPS))) { ctx in
                let i = Int(ctx.date.timeIntervalSinceReferenceDate * Double(safeFPS)) % images.count
                frameImage(images[i])
            }
        } else {
            // PNG, single-frame, or under-test animated → static. Animated starts on frame 0.
            frameImage(images[staticIndex])
        }
    }

    private var staticIndex: Int {
        if isAnimated { return 0 }
        return images.indices.contains(activeIndex) ? activeIndex : 0
    }

    private func frameImage(_ cg: CGImage) -> some View {
        Image(decorative: cg, scale: 1.0, orientation: .up)
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .aspectRatio(1, contentMode: .fit)
            .padding(8)
    }

    private var spriteGrid: some View {
        let g = SpriteSheetExporter.grid(count: images.count)
        return VStack(spacing: 1) {
            ForEach(0..<g.rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<g.columns, id: \.self) { col in
                        let idx = row * g.columns + col
                        if idx < images.count {
                            Image(decorative: images[idx], scale: 1.0, orientation: .up)
                                .resizable()
                                .interpolation(.none)
                                .antialiased(false)
                                .aspectRatio(1, contentMode: .fit)
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
        .aspectRatio(CGFloat(g.columns) / CGFloat(g.rows), contentMode: .fit)
        .padding(8)
    }

    private var badge: some View {
        Text(badgeText)
            .font(.pixel(9))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .allowsHitTesting(false)
    }

    private var badgeText: String {
        switch format {
        case .png:
            return "PNG · \(outputEdge)px"
        case .gif, .apng:
            let secs = Double(max(1, frames.count)) / Double(safeFPS)
            return "\(format.label) · \(String(format: "%.1f", secs))s"
        case .spriteSheet:
            let g = SpriteSheetExporter.grid(count: max(1, frames.count))
            return "SPRITE · \(g.columns)×\(g.rows)"
        }
    }

    private var checkerboard: some View {
        Canvas { ctx, sz in
            let s: CGFloat = 12
            for y in stride(from: 0, to: sz.height, by: s) {
                for x in stride(from: 0, to: sz.width, by: s) {
                    let isDark = (Int(x / s) + Int(y / s)) % 2 == 0
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(isDark ? Color(white: 0.16) : Color(white: 0.22)))
                }
            }
        }
    }

    private func renderImages() {
        guard images.isEmpty, !frames.isEmpty else { return }
        images = frames.compactMap {
            FrameThumbnailRenderer.renderCGImage(frame: $0, size: size, targetEdge: 512)
        }
    }
}
